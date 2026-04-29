import Testing
@testable import TypeCarrierCore

@Suite("TextEditHistory")
struct TextEditHistoryTests {
    @Test("Undo and redo walk recorded text states")
    func undoAndRedoWalkRecordedTextStates() {
        var history = TextEditHistory()

        history.recordChange(from: "", to: "hello")
        history.recordChange(from: "hello", to: "hello world")

        #expect(history.canUndo)
        #expect(!history.canRedo)
        #expect(history.undo(current: "hello world") == "hello")
        #expect(history.canUndo)
        #expect(history.canRedo)
        #expect(history.undo(current: "hello") == "")
        #expect(!history.canUndo)
        #expect(history.canRedo)
        #expect(history.redo(current: "") == "hello")
        #expect(history.redo(current: "hello") == "hello world")
        #expect(!history.canRedo)
    }

    @Test("Recording a new change clears redo history")
    func recordingNewChangeClearsRedoHistory() {
        var history = TextEditHistory()

        history.recordChange(from: "", to: "one")
        #expect(history.undo(current: "one") == "")

        history.recordChange(from: "", to: "two")

        #expect(!history.canRedo)
        #expect(history.redo(current: "two") == nil)
    }

    @Test("Reset clears undo and redo history")
    func resetClearsUndoAndRedoHistory() {
        var history = TextEditHistory()

        history.recordChange(from: "", to: "draft")
        #expect(history.undo(current: "draft") == "")
        history.reset()

        #expect(!history.canUndo)
        #expect(!history.canRedo)
    }

    @Test("No-op edits are ignored")
    func noOpEditsAreIgnored() {
        var history = TextEditHistory()

        history.recordChange(from: "same", to: "same")

        #expect(!history.canUndo)
        #expect(!history.canRedo)
    }

    @Test("History limit drops oldest states")
    func historyLimitDropsOldestStates() {
        var history = TextEditHistory(limit: 2)

        history.recordChange(from: "", to: "a")
        history.recordChange(from: "a", to: "ab")
        history.recordChange(from: "ab", to: "abc")

        #expect(history.undo(current: "abc") == "ab")
        #expect(history.undo(current: "ab") == "a")
        #expect(history.undo(current: "a") == nil)
    }
}
