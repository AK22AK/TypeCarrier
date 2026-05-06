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
        case .received, .posted, .failed:
            false
        }
    }
}
