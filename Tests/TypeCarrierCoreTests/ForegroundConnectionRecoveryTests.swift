import XCTest
@testable import TypeCarrierCore

final class ForegroundConnectionRecoveryTests: XCTestCase {
    func testInitialActivationDoesNotRequestRecoveryWithoutBackgroundHistory() {
        var recovery = ForegroundConnectionRecovery(backgroundDisconnectGraceSeconds: 12)

        let action = recovery.didBecomeActive(
            at: Date(timeIntervalSince1970: 100),
            hasStarted: true,
            isSending: false,
            isConnected: false
        )

        XCTAssertEqual(action, .none)
    }

    func testLongBackgroundActivationRequestsFreshRestart() {
        var recovery = ForegroundConnectionRecovery(backgroundDisconnectGraceSeconds: 12)
        recovery.didEnterBackground(at: Date(timeIntervalSince1970: 100))

        let action = recovery.didBecomeActive(
            at: Date(timeIntervalSince1970: 120),
            hasStarted: true,
            isSending: false,
            isConnected: false
        )

        XCTAssertEqual(
            action,
            .resumeFreshConnect(
                restartsExistingService: true,
                message: "Restarting after 20.0 seconds in background."
            )
        )
    }

    func testRecoveryRestartIdleDoesNotTriggerImmediateFreshRetry() {
        var recovery = ForegroundConnectionRecovery(backgroundDisconnectGraceSeconds: 12)
        recovery.beginResumeRecovery(restartsExistingService: true, keepsRetryBudget: false)

        let restartIdleAction = recovery.didChangeConnectionState(
            isConnected: false,
            isIdleOrFailed: true,
            displayText: "Idle"
        )
        XCTAssertEqual(restartIdleAction, .none)

        let realFailureAction = recovery.didChangeConnectionState(
            isConnected: false,
            isIdleOrFailed: true,
            displayText: "Idle"
        )
        XCTAssertEqual(
            realFailureAction,
            .resumeFreshRetry(message: "Restarting once after resume recovery reached Idle.")
        )
    }
}
