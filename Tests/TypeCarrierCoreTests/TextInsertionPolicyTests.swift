import Foundation
import Testing
@testable import TypeCarrierCore

@Suite("TextInsertionPolicy")
struct TextInsertionPolicyTests {
    @Test("Insert text at UTF-16 cursor")
    func insertTextAtUTF16Cursor() {
        let updated = TextInsertionPolicy.replacingText(
            in: "hello world",
            selectedUTF16Range: NSRange(location: 5, length: 0),
            with: " typed"
        )

        #expect(updated == "hello typed world")
    }

    @Test("Replace selected UTF-16 range")
    func replaceSelectedUTF16Range() {
        let updated = TextInsertionPolicy.replacingText(
            in: "hello world",
            selectedUTF16Range: NSRange(location: 6, length: 5),
            with: "TypeCarrier"
        )

        #expect(updated == "hello TypeCarrier")
    }

    @Test("Handle non-ASCII UTF-16 ranges")
    func handleNonASCIIUTF16Ranges() {
        let updated = TextInsertionPolicy.replacingText(
            in: "你好🙂世界",
            selectedUTF16Range: NSRange(location: 4, length: 2),
            with: "Swift"
        )

        #expect(updated == "你好🙂Swift")
    }

    @Test("Reject invalid UTF-16 range")
    func rejectInvalidUTF16Range() {
        let updated = TextInsertionPolicy.replacingText(
            in: "hello",
            selectedUTF16Range: NSRange(location: 99, length: 1),
            with: "x"
        )

        #expect(updated == nil)
    }
}
