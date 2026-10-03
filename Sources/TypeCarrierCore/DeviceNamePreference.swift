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
    public var draft = ""
    public private(set) var isEditing = false
    private var originalEffectiveName = ""
    private var originallyCustom = false

    public init() {}

    public mutating func begin(effectiveName: String, hasCustomName: Bool) {
        originalEffectiveName = effectiveName
        originallyCustom = hasCustomName
        draft = effectiveName
        isEditing = true
    }

    public var canSave: Bool {
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return isEditing && normalized != originalEffectiveName && (!normalized.isEmpty || originallyCustom)
    }

    public mutating func savedName() -> String? {
        guard canSave else { return nil }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        return name
    }

    public mutating func cancel() {
        draft = ""
        isEditing = false
    }
}
