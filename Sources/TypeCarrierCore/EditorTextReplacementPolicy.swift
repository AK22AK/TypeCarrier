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
}
