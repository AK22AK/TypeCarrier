#!/usr/bin/env python3
"""Measure iPhone -> Mac reconnect time across repeated background/foreground cycles.

Each cycle sends the iOS app to the background (by opening Settings), waits long
enough for the connection to drop, brings the app back, and times how long the Mac
receiver takes to log a connected session for that phone. Timing comes from the Mac
diagnostic log, so the Mac app must be running as the receiver.

Usage:
  script/connection_soak.py --device <UDID or name> [--cycles 200] [--background 15]
  script/connection_soak.py --simulator booted --cycles 20

Results are written as CSV plus a summary checked against the launch gate.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAC_LOG = Path.home() / "Library/Application Support/TypeCarrier/ConnectionDiagnostics/mac-connection-events.jsonl"
CONNECTED_EVENTS = {"session.connected", "v2.session.ready"}
DISCONNECTED_EVENTS = {"session.notConnected", "v2.session.closed"}
SETTINGS_BUNDLE_ID = "com.apple.Preferences"

GATE_P50 = 1.0
GATE_P95 = 2.0
GATE_SLOW = 10.0
GATE_MAX_SLOW = 1


def default_bundle_id() -> str:
    config = ROOT / "Configs/Signing.local.xcconfig"
    if config.exists():
        match = re.search(r"^TYPECARRIER_BUNDLE_PREFIX\s*=\s*(\S+)", config.read_text(), re.MULTILINE)
        if match:
            return f"{match.group(1)}.ios"
    return "com.example.typecarrier.ios"


def parse_timestamp(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


class MacLog:
    """Tails the Mac receiver JSONL log from the current end of file."""

    def __init__(self, path: Path):
        self.path = path
        self.offset = path.stat().st_size if path.exists() else 0
        self.pending = b""

    def read_new(self) -> list[dict]:
        if not self.path.exists():
            return []
        with self.path.open("rb") as handle:
            handle.seek(self.offset)
            chunk = handle.read()
        self.offset += len(chunk)
        data = self.pending + chunk
        lines = data.split(b"\n")
        self.pending = lines.pop()
        events = []
        for line in lines:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return events


class Launcher:
    def __init__(self, device: str | None, simulator: str | None, bundle_id: str, background_bundle_id: str):
        self.background_bundle_id = background_bundle_id
        self.device = device
        self.simulator = simulator
        self.bundle_id = bundle_id

    def _launch(self, bundle_id: str) -> None:
        if self.simulator:
            command = ["xcrun", "simctl", "launch", self.simulator, bundle_id]
        else:
            command = ["xcrun", "devicectl", "device", "process", "launch", "--device", self.device, bundle_id]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            # The first launch of a system app on a freshly booted simulator can fail transiently.
            time.sleep(1)
            result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"{' '.join(command)} failed: {result.stderr.strip() or result.stdout.strip()}")

    def background(self) -> None:
        self._launch(self.background_bundle_id)

    def foreground(self) -> None:
        self._launch(self.bundle_id)


def peer_matches(event: dict, peer: str | None) -> bool:
    return peer is None or peer in (event.get("peerName") or "")


def run_cycle(index: int, args, launcher: Launcher, log: MacLog) -> dict:
    """One cycle. A cycle only counts when the connection really dropped in the background."""

    def disconnect_seen(events: list[dict]) -> bool:
        return any(e.get("name") in DISCONNECTED_EVENTS and peer_matches(e, args.peer) for e in events)

    log.read_new()
    launcher.background()
    background_started = time.time()
    disconnected = False
    # Stay in the background at least --background seconds, and keep waiting (bounded) until the
    # Mac logs the disconnect, so every counted cycle measures a real reconnect.
    while True:
        disconnected |= disconnect_seen(log.read_new())
        elapsed = time.time() - background_started
        if elapsed >= args.background and (disconnected or elapsed >= args.background + args.timeout):
            break
        time.sleep(0.2)

    foreground_requested = datetime.now(timezone.utc)
    launcher.foreground()
    foreground_returned = datetime.now(timezone.utc)

    connected_at = None
    deadline = time.time() + args.timeout
    while disconnected and time.time() < deadline and connected_at is None:
        for event in log.read_new():
            if event.get("name") in CONNECTED_EVENTS and peer_matches(event, args.peer):
                stamp = parse_timestamp(event["timestamp"])
                if stamp >= foreground_requested.replace(microsecond=0):
                    connected_at = stamp
                    break
        time.sleep(0.05)

    def seconds_since(start: datetime) -> float | str:
        return round(max(0.0, (connected_at - start).total_seconds()), 3) if connected_at else ""

    row = {
        "cycle": index,
        "foreground_requested": foreground_requested.isoformat(),
        "launch_command_seconds": round((foreground_returned - foreground_requested).total_seconds(), 3),
        "counted": disconnected,
        "connected": connected_at is not None,
        # Measured from when the launch command returned (the app is in front by then); the
        # launch command itself can take seconds on a simulator and is reported separately.
        "connect_seconds": seconds_since(foreground_returned),
        "connect_seconds_from_request": seconds_since(foreground_requested),
    }
    if disconnected:
        time.sleep(args.dwell)
    return row


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(fraction * len(ordered)))]


def summarize(rows: list[dict], timeout: float) -> str:
    counted = [r for r in rows if r["counted"]]
    connect = [r["connect_seconds"] for r in counted if r["connected"]]
    failures = [r for r in counted if not r["connected"]]
    slow = [s for s in connect if s > GATE_SLOW]
    lines = [
        f"cycles: {len(rows)} (counted {len(counted)}; {len(rows) - len(counted)} skipped, no disconnect in background)",
        f"connected: {len(connect)}",
        f"no connect within {timeout:.0f}s: {len(failures)}",
    ]
    if connect:
        p50, p95 = percentile(connect, 0.5), percentile(connect, 0.95)
        lines += [f"p50: {p50:.3f}s", f"p95: {p95:.3f}s", f"max: {max(connect):.3f}s", f"over {GATE_SLOW:.0f}s: {len(slow)}"]
        passed = p50 < GATE_P50 and p95 < GATE_P95 and len(slow) + len(failures) <= GATE_MAX_SLOW
        lines.append(
            f"gate (p50<{GATE_P50}s, p95<{GATE_P95}s, at most {GATE_MAX_SLOW} over {GATE_SLOW:.0f}s or failed): "
            + ("PASS" if passed else "FAIL")
        )
    launch = [r["launch_command_seconds"] for r in rows]
    if launch:
        lines.append(f"launch command p50: {percentile(launch, 0.5):.3f}s (not included in connect times)")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--device", help="physical device UDID or name (devicectl)")
    target.add_argument("--simulator", help="simulator UDID or 'booted' (simctl)")
    parser.add_argument("--bundle-id", default=default_bundle_id())
    parser.add_argument("--background-app", default=SETTINGS_BUNDLE_ID, help="app opened to background TypeCarrier")
    parser.add_argument("--peer", help="only count Mac log events whose peerName contains this text")
    parser.add_argument("--cycles", type=int, default=200)
    parser.add_argument("--background", type=float, default=15, help="seconds in background per cycle")
    parser.add_argument("--dwell", type=float, default=3, help="seconds to stay foreground after connecting")
    parser.add_argument("--timeout", type=float, default=30, help="seconds to wait for a connection")
    parser.add_argument("--output", type=Path, help="CSV path (default: dist/soak/<timestamp>.csv)")
    args = parser.parse_args()

    output = args.output or ROOT / "dist/soak" / f"connection-soak-{datetime.now():%Y%m%d-%H%M%S}.csv"
    output.parent.mkdir(parents=True, exist_ok=True)
    launcher = Launcher(args.device, args.simulator, args.bundle_id, args.background_app)
    log = MacLog(MAC_LOG)

    rows: list[dict] = []
    with output.open("w", newline="") as handle:
        writer = None
        try:
            for index in range(1, args.cycles + 1):
                row = run_cycle(index, args, launcher, log)
                rows.append(row)
                if writer is None:
                    writer = csv.DictWriter(handle, fieldnames=list(row))
                    writer.writeheader()
                writer.writerow(row)
                handle.flush()
                status = f"{row['connect_seconds']}s" if row["connected"] else "NO CONNECT"
                print(f"[{index}/{args.cycles}] {status}", flush=True)
        except KeyboardInterrupt:
            print("interrupted", file=sys.stderr)

    summary = summarize(rows, args.timeout) if rows else "no cycles completed"
    output.with_suffix(".txt").write_text(summary + "\n")
    print(f"\n{summary}\n\nCSV: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
