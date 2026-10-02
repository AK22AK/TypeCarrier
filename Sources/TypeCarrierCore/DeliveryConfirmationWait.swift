import Foundation

/// Tracks one send's confirmation and prevents cancelled waits from affecting later sends.
@MainActor
public final class DeliveryConfirmationWait {
    private let timeout: Duration
    private let sleep: @MainActor (Duration) async throws -> Void
    private var task: Task<Void, Never>?
    private var pendingPayloadID: UUID?
    private var pendingTargetID: String?
    private var generation = UUID()

    public init(
        timeout: Duration = .seconds(5),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.timeout = timeout
        self.sleep = sleep
    }

    deinit {
        task?.cancel()
    }

    public func begin(payloadID: UUID, targetID: String? = nil, onTimeout: @escaping @MainActor () -> Void) {
        cancel()
        pendingPayloadID = payloadID
        pendingTargetID = targetID
        let generation = generation
        let timeout = timeout
        let sleep = sleep
        task = Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.generation == generation,
                  self.pendingPayloadID == payloadID else {
                return
            }
            self.cancel()
            onTimeout()
        }
    }

    /// Returns true only for the send currently awaiting confirmation.
    public func confirm(payloadID: UUID, sourceID: String? = nil) -> Bool {
        guard pendingPayloadID == payloadID, pendingTargetID == sourceID else {
            return false
        }
        cancel()
        return true
    }

    public func cancel() {
        task?.cancel()
        task = nil
        pendingPayloadID = nil
        pendingTargetID = nil
        generation = UUID()
    }
}
