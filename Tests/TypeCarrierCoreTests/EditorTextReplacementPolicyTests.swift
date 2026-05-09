import Testing
@testable import TypeCarrierCore

@Suite("EditorTextReplacementPolicy")
struct EditorTextReplacementPolicyTests {
    @Test("Programmatic emptying rebuilds the editor identity")
    func programmaticEmptyingRebuildsEditorIdentity() {
        let generation = EditorTextReplacementPolicy.nextEditorGeneration(
            currentText: "sent text",
            newText: "",
            currentGeneration: 4,
            rebuildsWhenEmptying: true
        )

        #expect(generation == 5)
    }

    @Test("Emptying can preserve the active input session")
    func emptyingCanPreserveActiveInputSession() {
        let generation = EditorTextReplacementPolicy.nextEditorGeneration(
            currentText: "draft text",
            newText: "",
            currentGeneration: 4,
            rebuildsWhenEmptying: false
        )

        #expect(generation == 4)
    }

    @Test("Undo and redo emptying preserve the active input session")
    func undoRedoEmptyingPreservesActiveInputSession() {
        let generation = EditorTextReplacementPolicy.nextEditorGenerationAfterUndoRedo(
            currentText: "draft text",
            newText: "",
            currentGeneration: 4
        )

        #expect(generation == 4)
    }

    @Test("Delivery receipts clear only after verified target insertion")
    func deliveryReceiptsClearOnlyAfterVerifiedTargetInsertion() {
        #expect(!EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(.received))
        #expect(EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(.posted))
        #expect(!EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(.failed))
    }

    @Test("Draft save clears editor only after local persistence succeeds")
    func draftSaveClearsEditorOnlyAfterLocalPersistenceSucceeds() {
        #expect(EditorTextReplacementPolicy.shouldClearEditorAfterDraftSave(succeeded: true))
        #expect(!EditorTextReplacementPolicy.shouldClearEditorAfterDraftSave(succeeded: false))
    }

    @Test("Non-empty replacements keep the editor identity")
    func nonEmptyReplacementsKeepEditorIdentity() {
        let generation = EditorTextReplacementPolicy.nextEditorGeneration(
            currentText: "old text",
            newText: "new text",
            currentGeneration: 4
        )

        #expect(generation == 4)
    }

    @Test("Entering text into an empty editor keeps the editor identity")
    func enteringTextIntoEmptyEditorKeepsEditorIdentity() {
        let generation = EditorTextReplacementPolicy.nextEditorGeneration(
            currentText: "",
            newText: "new text",
            currentGeneration: 4
        )

        #expect(generation == 4)
    }

    @Test("Empty no-op replacements keep the editor identity")
    func emptyNoOpReplacementsKeepEditorIdentity() {
        let generation = EditorTextReplacementPolicy.nextEditorGeneration(
            currentText: "",
            newText: "",
            currentGeneration: 4
        )

        #expect(generation == 4)
    }
}
