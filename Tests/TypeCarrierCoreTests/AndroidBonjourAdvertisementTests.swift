import Testing
@testable import TypeCarrierCore

struct AndroidBonjourAdvertisementTests {
    @Test func descriptorUsesAndroidDiscoveryServiceTypeAndTxtRecord() {
        let descriptor = AndroidBonjourAdvertisement(name: "MacBook Pro", macID: "mac-123")

        #expect(descriptor.serviceType == "_typecarrier._tcp")

        let record = AndroidBonjourAdvertisement.txtRecordDictionary(from: descriptor.txtRecordData)
        #expect(record["macID"].flatMap { String(data: $0, encoding: .utf8) } == "mac-123")
        #expect(record["macName"].flatMap { String(data: $0, encoding: .utf8) } == "MacBook Pro")
    }

    @Test func discoveryInfoIncludesAndroidBridgePort() {
        let info = AndroidBonjourAdvertisement.discoveryInfo(macID: "mac-123", macName: "MacBook Pro", port: 17641)

        #expect(info["macID"] == "mac-123")
        #expect(info["macName"] == "MacBook Pro")
        #expect(info["androidPort"] == "17641")
    }
}
