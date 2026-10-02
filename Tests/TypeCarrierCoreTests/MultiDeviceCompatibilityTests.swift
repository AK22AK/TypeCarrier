import XCTest
@testable import TypeCarrierCore

final class MultiDeviceCompatibilityTests: XCTestCase {
    func testOldDeviceIdentityAndRecordDecodeWithoutNewSourceIDs() throws {
        let identity = try JSONDecoder().decode(CarrierDeviceIdentity.self, from: Data(#"{"displayName":"Phone"}"#.utf8))
        XCTAssertNil(identity.deviceID)
        let record = CarrierRecord(kind: .incoming, status: .received, text: "Legacy", sourceDeviceName: "Phone", sourceDeviceID: "id")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json.removeValue(forKey: "sourceDeviceID")
        let decoded = try JSONDecoder().decode(CarrierRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.sourceDeviceID)
        XCTAssertEqual(decoded.text, record.text)
        XCTAssertEqual(decoded.sourceDeviceName, "Phone")
    }

    func testStableSourceIDsRoundTrip() throws {
        let identity = CarrierDeviceIdentity(displayName: "Phone", deviceID: "stable-phone")
        XCTAssertEqual(try JSONDecoder().decode(CarrierDeviceIdentity.self, from: JSONEncoder().encode(identity)), identity)
        let record = CarrierRecord(kind: .incoming, status: .received, text: "New", sourceDeviceName: "Phone", sourceDeviceID: "stable-phone")
        XCTAssertEqual(try JSONDecoder().decode(CarrierRecord.self, from: JSONEncoder().encode(record)), record)
    }
}
