import Foundation
import TypeCarrierCore

@MainActor
final class AndroidTrustTokenStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "AndroidTrustTokensByDeviceID") {
        self.defaults = defaults
        self.key = key
    }

    func token(for deviceID: String) -> AndroidTrustToken? {
        guard let rawValue = tokensByDeviceID()[deviceID] else {
            return nil
        }
        return AndroidTrustToken(rawValue: rawValue)
    }

    func remember(_ token: AndroidTrustToken, for deviceID: String) {
        var tokens = tokensByDeviceID()
        tokens[deviceID] = token.rawValue
        defaults.set(tokens, forKey: key)
    }

    private func tokensByDeviceID() -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
