# Android Sender MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the minimum Android -> Mac path so an Android phone can pair with TypeCarrier Mac and send text to the current Mac cursor.

**Architecture:** Keep the existing iPhone Multipeer path intact. Add a platform-neutral TCP wire layer and pairing primitives in `TypeCarrierCore`, then add a macOS Android bridge using `Network.NWListener`; Android gets an independent Kotlin/Compose project with matching protocol tests.

**Tech Stack:** Swift 6, Network.framework, XCTest, Kotlin, Gradle, Jetpack Compose, `androidx.compose.material3`, Coroutines, kotlinx.serialization.

---

### Task 1: Swift Wire Protocol and Pairing Primitives

**Files:**
- Create: `Sources/TypeCarrierCore/CarrierWireFrame.swift`
- Create: `Sources/TypeCarrierCore/AndroidPairing.swift`
- Create: `Tests/TypeCarrierCoreTests/CarrierWireFrameTests.swift`
- Create: `Tests/TypeCarrierCoreTests/AndroidPairingTests.swift`

- [x] Write failing XCTest coverage for length-prefixed JSON frames, malformed frames, pairing code format, trust token generation, and token proof validation.
- [x] Implement the smallest Swift core types needed to pass those tests.
- [x] Run `xcodebuild test -project TypeCarrier.xcodeproj -scheme TypeCarrierCore -destination 'platform=macOS' -derivedDataPath /private/tmp/typecarrier-android-mvp-core CODE_SIGNING_ALLOWED=NO`.

### Task 2: Mac Android Bridge Skeleton

**Files:**
- Create: `Apps/macOS/Services/AndroidCarrierBridge.swift`
- Modify: `Apps/macOS/Stores/MacCarrierStore.swift`
- Modify: `project.yml`
- Test: `Tests/TypeCarrierCoreTests` for bridge-independent logic.

- [x] Extract Mac text-envelope handling so Multipeer and Android bridge can share save/history/paste/receipt behavior.
- [x] Add an Android bridge object with start/stop state, pairing gate, active-sender busy policy, and a testable connection handler.
- [x] Reuse `_typecarrier._tcp` for Mac Bonjour discovery and include Android bridge metadata in TXT records; generate Xcode project only when implementation needs it.
- [x] Verify iPhone Multipeer behavior still builds and the core tests remain green.

### Task 3: Android Project Scaffold

**Files:**
- Create: `Apps/Android/settings.gradle.kts`
- Create: `Apps/Android/build.gradle.kts`
- Create: `Apps/Android/app/build.gradle.kts`
- Create: `Apps/Android/app/src/main/AndroidManifest.xml`
- Create: `Apps/Android/local.properties` only if needed for this local machine; do not commit secrets.

- [x] Scaffold Kotlin Android app with Compose and Material 3.
- [x] Point the local SDK to `/opt/homebrew/share/android-commandlinetools`.
- [x] Run `./gradlew testDebugUnitTest` and `./gradlew assembleDebug`.

### Task 4: Android Protocol, Transport, and UI

**Files:**
- Create: protocol, pairing, discovery, transport, store/viewmodel, and UI files under `Apps/Android/app/src/main/java/...`.
- Create: matching unit tests under `Apps/Android/app/src/test/java/...`.

- [x] Add Kotlin models matching Swift `CarrierEnvelope`, frame codec tests using the same JSON fixture, and pairing token tests.
- [x] Add NSD discovery and TCP transport.
- [x] Add Compose first screen: status, target Mac, text input, send, refresh/reconnect, pairing field, and inline errors.
- [x] Build a debug APK at `Apps/Android/app/build/outputs/apk/debug/app-debug.apk`.
- [x] Add manual host fallback if NSD discovery is unreliable during real-device validation.

### Task 5: End-to-End Verification

**Files:**
- Modify docs only if validation reveals changed constraints.

- [x] Run Swift core tests.
- [x] Run Android unit tests and `assembleDebug`.
- [x] Verify Mac bridge listens on fixed TCP port `17641`.
- [x] Verify Android real-device hotspot flow through manual IP + `17641`: connect, pair, send, and Mac receive/history.
- [ ] Verify Android real-device flow: automatic discovery, restart app, reconnect without pairing, busy handling.
- [ ] Regression-check iPhone -> Mac path still starts and sends.

### 2026-06-01 Validation Note

- Working MVP path: Android phone hotspot + Mac connected to hotspot + Android manual Mac address + fixed port `17641`.
- Mac Android bridge must keep manual TCP listening independent from Bonjour / NSD publishing. Bonjour publish can fail with `Network.NWError error -65555 - NoAuth`; that should not block manual connect.
- Current confirmed behavior: Android -> Mac transport reaches Mac, Mac writes received text to history, and post-receive handling shares the same paste path as iOS.
