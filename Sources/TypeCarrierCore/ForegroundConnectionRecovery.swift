import Foundation

public struct ForegroundConnectionRecovery: Equatable, Sendable {
    public enum BecameActiveAction: Equatable, Sendable {
        case none
        case resumeFastPath(message: String)
        case resumeFreshConnect(restartsExistingService: Bool, message: String)
    }

    public enum StateChangeAction: Equatable, Sendable {
        case none
        case resumeFreshRetry(message: String)
    }

    private let backgroundDisconnectGraceSeconds: TimeInterval
    private var backgroundEnteredAt: Date?
    private var wasStoppedForBackground = false
    private var isResumeRecoveryActive = false
    private var resumeRecoveryFreshRestartRemaining = 0
    private var resumeRecoveryRestartIdleEventsToIgnore = 0

    public init(backgroundDisconnectGraceSeconds: TimeInterval) {
        self.backgroundDisconnectGraceSeconds = backgroundDisconnectGraceSeconds
    }

    public var isInBackground: Bool {
        backgroundEnteredAt != nil
    }

    public mutating func didEnterBackground(at date: Date) {
        backgroundEnteredAt = date
        wasStoppedForBackground = false
    }

    public mutating func didDisconnectAfterBackgroundGrace() {
        backgroundEnteredAt = nil
        wasStoppedForBackground = true
    }

    public mutating func didTerminate() {
        backgroundEnteredAt = nil
        wasStoppedForBackground = false
        isResumeRecoveryActive = false
        resumeRecoveryFreshRestartRemaining = 0
        resumeRecoveryRestartIdleEventsToIgnore = 0
    }

    public mutating func didBecomeActive(
        at date: Date,
        hasStarted: Bool,
        isSending: Bool,
        isConnected: Bool
    ) -> BecameActiveAction {
        let backgroundDuration = backgroundEnteredAt.map { date.timeIntervalSince($0) }
        backgroundEnteredAt = nil

        guard !isSending else {
            return .none
        }

        if wasStoppedForBackground {
            wasStoppedForBackground = false
            return .resumeFreshConnect(
                restartsExistingService: false,
                message: "Restarting after background disconnect."
            )
        }

        guard hasStarted, let backgroundDuration else {
            return .none
        }

        if backgroundDuration >= backgroundDisconnectGraceSeconds {
            return .resumeFreshConnect(
                restartsExistingService: true,
                message: "Restarting after \(backgroundDuration) seconds in background."
            )
        }

        if isConnected {
            return .resumeFastPath(message: "Kept connection after short background.")
        }

        return .resumeFreshConnect(
            restartsExistingService: true,
            message: "Restarting after short background without connection."
        )
    }

    public mutating func beginResumeRecovery(restartsExistingService: Bool, keepsRetryBudget: Bool) {
        isResumeRecoveryActive = true
        if !keepsRetryBudget {
            resumeRecoveryFreshRestartRemaining = 1
        }
        if restartsExistingService {
            resumeRecoveryRestartIdleEventsToIgnore += 1
        }
    }

    public mutating func didChangeConnectionState(
        isConnected: Bool,
        isIdleOrFailed: Bool,
        displayText: String
    ) -> StateChangeAction {
        if isConnected {
            isResumeRecoveryActive = false
            resumeRecoveryFreshRestartRemaining = 0
            resumeRecoveryRestartIdleEventsToIgnore = 0
            return .none
        }

        guard isResumeRecoveryActive, isIdleOrFailed else {
            return .none
        }

        if resumeRecoveryRestartIdleEventsToIgnore > 0 {
            resumeRecoveryRestartIdleEventsToIgnore -= 1
            return .none
        }

        guard resumeRecoveryFreshRestartRemaining > 0 else {
            isResumeRecoveryActive = false
            return .none
        }

        resumeRecoveryFreshRestartRemaining -= 1
        return .resumeFreshRetry(message: "Restarting once after resume recovery reached \(displayText).")
    }
}
