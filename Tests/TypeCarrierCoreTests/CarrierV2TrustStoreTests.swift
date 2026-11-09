import CryptoKit
import Foundation
import XCTest
@testable import TypeCarrierCore

final class CarrierV2TrustStoreTests: XCTestCase {
    func testIdentityKeyIsCreatedOnceAndReused() throws {
        let storage = CarrierV2MemoryStorage()
        let first = try CarrierV2TrustStore(storage: storage).identityKey()
        let second = try CarrierV2TrustStore(storage: storage).identityKey()

        XCTAssertEqual(first.rawRepresentation, second.rawRepresentation)
    }

    func testPairingTrustsTheKeyAndRepairingReplacesTheOldKey() throws {
        let storage = CarrierV2MemoryStorage()
        let store = CarrierV2TrustStore(storage: storage)
        let oldKey = Data(repeating: 1, count: 32)
        let newKey = Data(repeating: 2, count: 32)

        try store.pair(CarrierV2PairedDevice(deviceID: "phone", deviceName: "iPhone", platform: .iOS, publicKey: oldKey))
        XCTAssertTrue(store.isTrusted(publicKey: oldKey))

        try store.pair(CarrierV2PairedDevice(deviceID: "phone", deviceName: "iPhone", platform: .iOS, publicKey: newKey))
        let reloaded = CarrierV2TrustStore(storage: storage)
        XCTAssertFalse(reloaded.isTrusted(publicKey: oldKey))
        XCTAssertTrue(reloaded.isTrusted(publicKey: newKey))
        XCTAssertEqual(try reloaded.pairedDevices().count, 1)
    }

    func testUnpairStopsTrustingAndRecordConnectionUpdatesNameAndTime() throws {
        let store = CarrierV2TrustStore(storage: CarrierV2MemoryStorage())
        let key = Data(repeating: 3, count: 32)
        try store.pair(CarrierV2PairedDevice(deviceID: "mac", deviceName: "Mac", platform: .macOS, publicKey: key))
        let connectedAt = Date(timeIntervalSince1970: 1_780_000_000)

        try store.recordConnection(publicKey: key, deviceName: "Studio Mac", at: connectedAt)
        XCTAssertEqual(store.pairedDevice(publicKey: key)?.deviceName, "Studio Mac")
        XCTAssertEqual(store.pairedDevice(publicKey: key)?.lastConnectedAt, connectedAt)

        try store.unpair(deviceID: "mac")
        XCTAssertFalse(store.isTrusted(publicKey: key))
    }

    func testKeychainStorageRoundTrips() throws {
        let storage = CarrierV2KeychainStorage(service: "TypeCarrier.transport.tests.\(UUID().uuidString)")
        do {
            try storage.set(Data("secret".utf8), for: "item")
        } catch CarrierV2TrustStoreError.keychain(let status) where status == errSecMissingEntitlement || status == errSecInteractionNotAllowed {
            throw XCTSkip("Keychain unavailable to this test process (\(status)).")
        }
        defer { try? storage.set(nil, for: "item") }

        XCTAssertEqual(try storage.data(for: "item"), Data("secret".utf8))
        try storage.set(Data("replaced".utf8), for: "item")
        XCTAssertEqual(try storage.data(for: "item"), Data("replaced".utf8))
        try storage.set(nil, for: "item")
        XCTAssertNil(try storage.data(for: "item"))
    }
}

final class CarrierV2TrustStoreWriteTests: XCTestCase {
    func testRoutineReconnectsDoNotRewriteThePairingList() throws {
        let storage = CountingStorage()
        let store = CarrierV2TrustStore(storage: storage)
        let key = Data(repeating: 4, count: 32)
        let pairedAt = Date(timeIntervalSince1970: 1_780_000_000)
        try store.pair(CarrierV2PairedDevice(deviceID: "mac", deviceName: "Mac", platform: .macOS, publicKey: key, lastConnectedAt: pairedAt))
        let writesAfterPairing = storage.writes

        try store.recordConnection(publicKey: key, deviceName: "Mac", at: pairedAt.addingTimeInterval(60))
        try store.recordConnection(publicKey: key, deviceName: "Mac", at: pairedAt.addingTimeInterval(120))
        XCTAssertEqual(storage.writes, writesAfterPairing)

        try store.recordConnection(publicKey: key, deviceName: "Studio Mac", at: pairedAt.addingTimeInterval(180))
        XCTAssertEqual(storage.writes, writesAfterPairing + 1)
        XCTAssertEqual(CarrierV2TrustStore(storage: storage).pairedDevice(publicKey: key)?.deviceName, "Studio Mac")

        try store.recordConnection(publicKey: key, deviceName: "Studio Mac", at: pairedAt.addingTimeInterval(180 + CarrierV2TrustStore.connectionTimeWriteInterval))
        XCTAssertEqual(storage.writes, writesAfterPairing + 2)
    }

    func testIdentityKeyIsReadFromStorageOnce() throws {
        let storage = CountingStorage()
        let store = CarrierV2TrustStore(storage: storage)
        let first = try store.identityKey()
        let readsAfterFirst = storage.reads
        let second = try store.identityKey()

        XCTAssertEqual(first.rawRepresentation, second.rawRepresentation)
        XCTAssertEqual(storage.reads, readsAfterFirst)
    }
}

private final class CountingStorage: CarrierV2SecretStorage {
    private let inner = CarrierV2MemoryStorage()
    private(set) var reads = 0
    private(set) var writes = 0

    func data(for account: String) throws -> Data? {
        reads += 1
        return try inner.data(for: account)
    }

    func set(_ data: Data?, for account: String) throws {
        writes += 1
        try inner.set(data, for: account)
    }
}
