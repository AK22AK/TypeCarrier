import XCTest
@testable import TypeCarrierCore

@MainActor
final class DeliveryConfirmationWaitTests: XCTestCase {
    @MainActor
    private final class ManualSleep {
        var durations: [Duration] = []
        var continuations: [CheckedContinuation<Void, any Error>] = []

        func sleep(_ duration: Duration) async throws {
            durations.append(duration)
            try await withCheckedThrowingContinuation { continuations.append($0) }
        }

        func finish(_ index: Int) {
            // Deliberately ignore cancellation to exercise stale-task guards too.
            continuations[index].resume()
        }
    }

    private func drainTasks() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    func testRealSleepExpiresWithInjectedDuration() async {
        let wait = DeliveryConfirmationWait(timeout: .milliseconds(20))
        let id = UUID()
        let expired = expectation(description: "Confirmation expires")
        wait.begin(payloadID: id) { expired.fulfill() }

        let result = await XCTWaiter.fulfillment(of: [expired], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(wait.confirm(payloadID: id))
    }

    func testDefaultWaitExpiresOnceAndRejectsLateConfirmation() async {
        let sleep = ManualSleep()
        let wait = DeliveryConfirmationWait(sleep: { try await sleep.sleep($0) })
        let id = UUID()
        var timeoutCount = 0
        wait.begin(payloadID: id) { timeoutCount += 1 }
        await drainTasks()
        XCTAssertEqual(sleep.durations, [.seconds(5)])
        guard sleep.continuations.count == 1 else {
            return XCTFail("Wait did not start")
        }

        sleep.finish(0)
        await drainTasks()
        XCTAssertEqual(timeoutCount, 1)
        XCTAssertFalse(wait.confirm(payloadID: id))
    }

    func testMatchingConfirmationCancelsTimeoutAndCannotConfirmTwice() async {
        let sleep = ManualSleep()
        let wait = DeliveryConfirmationWait(sleep: { try await sleep.sleep($0) })
        let id = UUID()
        var timedOut = false
        wait.begin(payloadID: id) { timedOut = true }
        await drainTasks()
        guard sleep.continuations.count == 1 else {
            return XCTFail("Wait did not start")
        }

        XCTAssertTrue(wait.confirm(payloadID: id))
        XCTAssertFalse(wait.confirm(payloadID: id))
        sleep.finish(0)
        await drainTasks()
        XCTAssertFalse(timedOut)
    }

    func testUnrelatedConfirmationDoesNotEndWait() async {
        let sleep = ManualSleep()
        let wait = DeliveryConfirmationWait(sleep: { try await sleep.sleep($0) })
        let id = UUID()
        var timedOut = false
        wait.begin(payloadID: id) { timedOut = true }
        await drainTasks()
        guard sleep.continuations.count == 1 else {
            return XCTFail("Wait did not start")
        }

        XCTAssertFalse(wait.confirm(payloadID: UUID()))
        sleep.finish(0)
        await drainTasks()
        XCTAssertTrue(timedOut)
    }

    func testSendFailureCancellationRejectsConfirmationAndTimeout() async {
        let sleep = ManualSleep()
        let wait = DeliveryConfirmationWait(sleep: { try await sleep.sleep($0) })
        let id = UUID()
        var timedOut = false
        wait.begin(payloadID: id) { timedOut = true }
        await drainTasks()
        guard sleep.continuations.count == 1 else {
            return XCTFail("Wait did not start")
        }

        wait.cancel()
        XCTAssertFalse(wait.confirm(payloadID: id))
        sleep.finish(0)
        await drainTasks()
        XCTAssertFalse(timedOut)
    }

    func testOldConfirmationAndTimerCannotEndNewSend() async {
        let sleep = ManualSleep()
        let wait = DeliveryConfirmationWait(timeout: .seconds(2), sleep: { try await sleep.sleep($0) })
        let oldID = UUID()
        let newID = UUID()
        var oldTimedOut = false
        var newTimedOut = false
        wait.begin(payloadID: oldID) { oldTimedOut = true }
        await drainTasks()
        wait.begin(payloadID: newID) { newTimedOut = true }
        await drainTasks()
        XCTAssertEqual(sleep.durations, [.seconds(2), .seconds(2)])
        guard sleep.continuations.count == 2 else {
            return XCTFail("Both waits did not start")
        }

        XCTAssertFalse(wait.confirm(payloadID: oldID))
        sleep.finish(0)
        await drainTasks()
        XCTAssertFalse(oldTimedOut)
        XCTAssertFalse(newTimedOut)
        XCTAssertTrue(wait.confirm(payloadID: newID))
        sleep.finish(1)
        await drainTasks()
        XCTAssertFalse(newTimedOut)
    }

    func testLateConfirmationAfterTimeoutCannotConfirmNextSend() async {
        let sleep = ManualSleep()
        let wait = DeliveryConfirmationWait(sleep: { try await sleep.sleep($0) })
        let oldID = UUID()
        let newID = UUID()
        var timeoutCount = 0
        wait.begin(payloadID: oldID) { timeoutCount += 1 }
        await drainTasks()
        guard sleep.continuations.count == 1 else {
            return XCTFail("Wait did not start")
        }
        sleep.finish(0)
        await drainTasks()

        wait.begin(payloadID: newID) { timeoutCount += 1 }
        await drainTasks()
        guard sleep.continuations.count == 2 else {
            return XCTFail("Second wait did not start")
        }
        XCTAssertFalse(wait.confirm(payloadID: oldID))
        XCTAssertEqual(timeoutCount, 1)
        XCTAssertTrue(wait.confirm(payloadID: newID))
        sleep.finish(1)
        await drainTasks()
        XCTAssertEqual(timeoutCount, 1)
    }
}
