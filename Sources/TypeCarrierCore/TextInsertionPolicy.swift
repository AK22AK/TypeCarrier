import Foundation

public enum TextInsertionPolicy {
    public static func replacingText(
        in currentText: String,
        selectedUTF16Range: NSRange,
        with replacementText: String
    ) -> String? {
        guard let range = Range(selectedUTF16Range, in: currentText) else {
            return nil
        }

        return currentText.replacingCharacters(in: range, with: replacementText)
    }
}
