import CryptoKit
import Foundation
import Security

/// A device this one has paired with. Public keys are not secret, but whoever can add one here can
/// connect, so the list lives in the Keychain next to the private key rather than in UserDefaults.
public struct CarrierV2PairedDevice: Codable, Equatable, Sendable, Identifiable {
    public let deviceID: String
    public var deviceName: String
    public let platform: CarrierHello.Platform
    public let publicKey: Data
    public let pairedAt: Date
    public var lastConnectedAt: Date?

    public var id: String { deviceID }

    public init(
        deviceID: String,
        deviceName: String,
        platform: CarrierHello.Platform,
        publicKey: Data,
        pairedAt: Date = Date(),
        lastConnectedAt: Date? = nil
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.publicKey = publicKey
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
    }
}

/// Where the identity key and pairings are kept. The Keychain in the apps; memory in tests.
public protocol CarrierV2SecretStorage: AnyObject {
    func data(for account: String) throws -> Data?
    func set(_ data: Data?, for account: String) throws
}

public enum CarrierV2TrustStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
}

public final class CarrierV2TrustStore {
    static let identityAccount = "v2.identityKey"
    static let pairedDevicesAccount = "v2.pairedDevices"

    private let storage: CarrierV2SecretStorage
    private var cachedDevices: [CarrierV2PairedDevice]?

    public init(storage: CarrierV2SecretStorage = CarrierV2KeychainStorage()) {
        self.storage = storage
    }

    /// The device's long-term Noise key, created on first use. Regenerating it unpairs every peer.
    public func identityKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let raw = try storage.data(for: Self.identityAccount),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try storage.set(key.rawRepresentation, for: Self.identityAccount)
        return key
    }

    public func pairedDevices() throws -> [CarrierV2PairedDevice] {
        if let cachedDevices { return cachedDevices }
        let devices = try storage.data(for: Self.pairedDevicesAccount)
            .map { try Self.decoder.decode([CarrierV2PairedDevice].self, from: $0) } ?? []
        cachedDevices = devices
        return devices
    }

    public func pairedDevice(publicKey: Data) -> CarrierV2PairedDevice? {
        (try? pairedDevices())?.first { $0.publicKey == publicKey }
    }

    public func isTrusted(publicKey: Data) -> Bool {
        pairedDevice(publicKey: publicKey) != nil
    }

    /// Adds or replaces the pairing for this device ID. A re-pair carries a new key, so the old one stops working.
    public func pair(_ device: CarrierV2PairedDevice) throws {
        var devices = try pairedDevices().filter { $0.deviceID != device.deviceID && $0.publicKey != device.publicKey }
        devices.append(device)
        try save(devices)
    }

    public func unpair(deviceID: String) throws {
        try save(try pairedDevices().filter { $0.deviceID != deviceID })
    }

    public func recordConnection(publicKey: Data, deviceName: String, at date: Date = Date()) throws {
        var devices = try pairedDevices()
        guard let index = devices.firstIndex(where: { $0.publicKey == publicKey }) else { return }
        devices[index].lastConnectedAt = date
        devices[index].deviceName = deviceName
        try save(devices)
    }

    private func save(_ devices: [CarrierV2PairedDevice]) throws {
        try storage.set(try Self.encoder.encode(devices), for: Self.pairedDevicesAccount)
        cachedDevices = devices
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Generic-password Keychain items, readable only on this device once it has been unlocked
/// (never synced to iCloud: a pairing belongs to one physical device).
public final class CarrierV2KeychainStorage: CarrierV2SecretStorage {
    private let service: String

    public init(service: String = "TypeCarrier.transport") {
        self.service = service
    }

    public func data(for account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw CarrierV2TrustStoreError.keychain(status)
        }
    }

    public func set(_ data: Data?, for account: String) throws {
        let deleteStatus = SecItemDelete(baseQuery(account) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw CarrierV2TrustStoreError.keychain(deleteStatus)
        }
        guard let data else { return }
        var item = baseQuery(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw CarrierV2TrustStoreError.keychain(status) }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

public final class CarrierV2MemoryStorage: CarrierV2SecretStorage {
    private var items: [String: Data] = [:]

    public init() {}

    public func data(for account: String) throws -> Data? {
        items[account]
    }

    public func set(_ data: Data?, for account: String) throws {
        items[account] = data
    }
}
