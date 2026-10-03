import Foundation

/// Stores a display-name override independently of stable device and pairing identities.
public struct DeviceNamePreference {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public var customName: String {
        (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public func save(_ name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(normalized, forKey: key)
        }
        return normalized
    }
}

/// Local editing state. Only a changed save produces a preference command.
public struct DeviceNameEditState: Equatable {
    public enum Source: Equatable { case system, custom }
    public var draft = ""
    public private(set) var isEditing = false
    private var originalEffectiveName = ""
    private var originallyCustom = false
    private var selectedSystemName: String?

    public init() {}

    public mutating func begin(effectiveName: String, hasCustomName: Bool) {
        originalEffectiveName = effectiveName
        originallyCustom = hasCustomName
        selectedSystemName = nil
        draft = effectiveName
        isEditing = true
    }

    public mutating func selectSystemName(_ name: String) {
        guard isEditing else { return }
        selectedSystemName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = name
    }

    public var pendingSource: Source {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == selectedSystemName || (!originallyCustom && name == originalEffectiveName) {
            return .system
        }
        return .custom
    }

    public var canSave: Bool {
        guard isEditing else { return false }
        if pendingSource == .system { return originallyCustom }
        return !originallyCustom || draft.trimmingCharacters(in: .whitespacesAndNewlines) != originalEffectiveName
    }

    public mutating func savedName() -> String? {
        guard canSave else { return nil }
        let name = pendingSource == .system ? "" : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        return name
    }

    public mutating func cancel() {
        draft = ""
        selectedSystemName = nil
        isEditing = false
    }
}
