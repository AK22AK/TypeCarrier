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
