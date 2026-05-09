public enum EditorTextReplacementPolicy {
    public static func nextEditorGeneration(
        currentText: String,
        newText: String,
        currentGeneration: Int,
        rebuildsWhenEmptying: Bool = true
    ) -> Int {
        guard rebuildsWhenEmptying, currentText != newText, newText.isEmpty else {
            return currentGeneration
        }

        return currentGeneration + 1
    }

    public static func shouldClearEditorAfterDeliveryReceipt(
        _ pasteStatus: CarrierDeliveryReceipt.PasteStatus
    ) -> Bool {
        switch pasteStatus {
        case .posted:
            true
        case .received, .failed:
            false
        }
    }

    public static func shouldClearEditorAfterDraftSave(succeeded: Bool) -> Bool {
        succeeded
    }

    public static func nextEditorGenerationAfterUndoRedo(
        currentText: String,
        newText: String,
        currentGeneration: Int
    ) -> Int {
        nextEditorGeneration(
            currentText: currentText,
            newText: newText,
            currentGeneration: currentGeneration,
            rebuildsWhenEmptying: false
        )
    }
}
