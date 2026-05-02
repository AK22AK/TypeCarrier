public enum EditorTextReplacementPolicy {
    public static func nextEditorGeneration(
        currentText: String,
        newText: String,
        currentGeneration: Int
    ) -> Int {
        guard currentText != newText, newText.isEmpty else {
            return currentGeneration
        }

        return currentGeneration + 1
    }
}
