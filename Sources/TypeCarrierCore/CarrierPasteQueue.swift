import Foundation

/// Serializes the complete paste transaction, including its asynchronous clipboard restoration.
@MainActor
public final class CarrierPasteQueue {
    private var jobs: [@MainActor () async -> Void] = []
    private var isDraining = false

    public init() {}

    public func enqueue(_ job: @escaping @MainActor () async -> Void) {
        jobs.append(job)
        guard !isDraining else { return }
        isDraining = true
        Task { @MainActor in
            while !jobs.isEmpty {
                let next = jobs.removeFirst()
                await next()
            }
            isDraining = false
        }
    }
}

public enum ClipboardRestorePolicy {
    public static func shouldRestore(expectedChangeCount: Int, currentChangeCount: Int) -> Bool {
        expectedChangeCount == currentChangeCount
    }
}
