import XCTest
@testable import TypeCarrierCore

final class CarrierPasteQueueTests: XCTestCase {
    @MainActor
    func testFIFOIncludesRestoreAndReentrantArrivalBeforeNextSnapshot() async {
        let queue = CarrierPasteQueue()
        let finished = expectation(description: "three complete transactions")
        finished.expectedFulfillmentCount = 3
        var events: [String] = []
        var clipboard = "original"
        var active = 0
        var maximumActive = 0
        func enqueue(_ name: String, addsDuringWait: Bool = false) {
            queue.enqueue {
                active += 1
                maximumActive = max(active, maximumActive)
                let original = clipboard
                events.append("snapshot:\(name):\(original)")
                clipboard = name
                events.append("commandV:\(name)")
                if addsDuringWait { enqueue("manual") }
                await Task.yield()
                events.append("return:\(name)")
                await Task.yield()
                clipboard = original
                events.append("restore:\(name)")
                active -= 1
                finished.fulfill()
            }
        }
        enqueue("apple", addsDuringWait: true)
        enqueue("android")
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(maximumActive, 1)
        XCTAssertEqual(events, [
            "snapshot:apple:original", "commandV:apple", "return:apple", "restore:apple",
            "snapshot:android:original", "commandV:android", "return:android", "restore:android",
            "snapshot:manual:original", "commandV:manual", "return:manual", "restore:manual"
        ])
        XCTAssertEqual(clipboard, "original")
    }

    @MainActor
    func testExternalClipboardChangeSurvivesRestoreAndIsNextSnapshot() async {
        let queue = CarrierPasteQueue()
        let finished = expectation(description: "complete")
        var clipboard = "original"
        var changeCount = 0
        queue.enqueue {
            clipboard = "first"
            changeCount += 1
            let pasteCount = changeCount
            await Task.yield()
            clipboard = "user copy"
            changeCount += 1
            if ClipboardRestorePolicy.shouldRestore(expectedChangeCount: pasteCount, currentChangeCount: changeCount) {
                clipboard = "original"
            }
        }
        queue.enqueue {
            XCTAssertEqual(clipboard, "user copy")
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(clipboard, "user copy")
    }
}
