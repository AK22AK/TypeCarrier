#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

report_error() {
  local message="$1"
  echo "::error::${message}"
  failures=$((failures + 1))
}

run_check() {
  local title="$1"
  shift
  echo "==> ${title}"
  if ! "$@"; then
    report_error "${title} failed"
  fi
}

check_project_generation() {
  local before
  local after

  before="$(git diff -- TypeCarrier.xcodeproj | shasum -a 256 | awk '{print $1}')"
  xcodegen generate
  after="$(git diff -- TypeCarrier.xcodeproj | shasum -a 256 | awk '{print $1}')"

  if [[ "$before" != "$after" ]]; then
    git diff -- TypeCarrier.xcodeproj
    return 1
  fi
}

check_plists() {
  local file
  while IFS= read -r file; do
    plutil -lint "$file" >/dev/null
  done < <(git ls-files '*.plist' '*.entitlements')
}

check_swift_source_hygiene() {
  local matches
  matches="$(git grep -n -E '\b(print|debugPrint|dump)\s*\(|try!| as!' -- '*.swift' || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches"
    report_error "Swift source contains debug output or force operations"
  fi
}

check_forbidden_files() {
  local matches
  matches="$(
    git ls-files | grep -E '(^|/)(\.env(\..*)?|Signing\.local\.xcconfig|GoogleService-Info\.plist|.*\.(p12|mobileprovision|provisionprofile|cer|der|pem|key|xcuserstate))$|(^|/)(xcuserdata|DerivedData)(/|$)' || true
  )"
  if [[ -n "$matches" ]]; then
    echo "$matches"
    report_error "Repository tracks files that should stay local or private"
  fi
}

check_signing_placeholders() {
  local matches
  matches="$(
    git grep -n -E 'DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}' -- '*.xcconfig' ':!Configs/Signing.example.xcconfig' || true
  )"
  if [[ -n "$matches" ]]; then
    echo "$matches"
    report_error "Repository contains a concrete Apple Developer Team ID outside example config"
  fi
}

check_secret_patterns() {
  local matches
  matches="$(
    git grep -I -n -E 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-[A-Za-z0-9]{32,}|xox[baprs]-[A-Za-z0-9-]{20,}|-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----|(^|[^A-Za-z0-9_])(api[_-]?key|client[_-]?secret|password|secret|token)[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9_./+=-]{16,}["'\'']' -- . ':!docs/github-history-remediation.md' || true
  )"
  if [[ -n "$matches" ]]; then
    echo "$matches"
    report_error "Repository contains text that looks like a secret or private key"
  fi
}

check_mac_record_action_toolbar() {
  local block
  block="$(
    awk '
      /^private struct ReceivedRecordDetail: View/ { in_block = 1 }
      /^private struct ReceiverStatusPage: View/ { in_block = 0 }
      in_block { print }
    ' Apps/macOS/Views/MainWindowView.swift
  )"

  if ! grep -q 'ToolbarItemGroup(placement: \.primaryAction)' <<<"$block"; then
    echo "ReceivedRecordDetail must keep copy/delete actions in the primaryAction toolbar."
    return 1
  fi

  if ! grep -q 'recordActionButtons' <<<"$block"; then
    echo "ReceivedRecordDetail toolbar must render recordActionButtons."
    return 1
  fi

  if grep -q 'recordActionBar' <<<"$block"; then
    echo "ReceivedRecordDetail must not render recordActionBar inside the detail content."
    return 1
  fi
}

check_mac_main_window_uses_single_scene_path() {
  if grep -q 'NSWindow(' Apps/macOS/App/MacAppCoordinator.swift; then
    echo "Mac main window must be reopened through the SwiftUI WindowGroup, not a second manual NSWindow path."
    return 1
  fi

  if grep -q 'NSHostingView(rootView: MainWindowView' Apps/macOS/App/MacAppCoordinator.swift; then
    echo "MacAppCoordinator must not construct a second MainWindowView hosting tree."
    return 1
  fi
}

check_paste_diagnostics_capture_focus_and_restore_timing() {
  local file="Apps/macOS/Services/PasteInjector.swift"
  for marker in frontApp focusedElementResult postWaitSeconds clipboardRestore postValueResult; do
    if ! grep -q "$marker" "$file"; then
      echo "PasteInjector diagnostics must include ${marker}."
      return 1
    fi
  done
}

check_clipboard_restore_is_opt_in() {
  if ! grep -q 'restoreDelay: TimeInterval? = nil' Apps/macOS/Services/PasteInjector.swift; then
    echo "PasteInjector clipboard restore must be optional and disabled by default."
    return 1
  fi

  if ! grep -q 'clipboardRestore", "disabledBySetting"' Apps/macOS/Services/PasteInjector.swift; then
    echo "PasteInjector must record when clipboard restore is disabled by setting."
    return 1
  fi

  if ! grep -q 'restoresClipboardAfterAutomaticPaste' Apps/macOS/Stores/MacCarrierStore.swift; then
    echo "MacCarrierStore must expose the clipboard restore setting."
    return 1
  fi
}

run_check "Whitespace check" git diff --check
run_check "Generated Xcode project is in sync" check_project_generation
run_check "Property lists are valid" check_plists
run_check "Forbidden local/private files are not tracked" check_forbidden_files
run_check "Signing placeholders stay generic" check_signing_placeholders
run_check "Secret patterns are absent" check_secret_patterns
run_check "Swift source hygiene" check_swift_source_hygiene
run_check "Mac received record actions stay in the toolbar" check_mac_record_action_toolbar
run_check "Mac main window uses the SwiftUI scene path" check_mac_main_window_uses_single_scene_path
run_check "Paste diagnostics capture focus and restore timing" check_paste_diagnostics_capture_focus_and_restore_timing
run_check "Clipboard restore is opt-in" check_clipboard_restore_is_opt_in

if [[ "$failures" -gt 0 ]]; then
  echo "CI sanity checks failed with ${failures} issue(s)."
  exit 1
fi

echo "CI sanity checks passed."
