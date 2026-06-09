import Foundation

public struct AndroidBonjourAdvertisement: Equatable {
    public static let serviceType = "_typecarrier._tcp"
    public static let androidPortKey = "androidPort"
    public static let macIDKey = "macID"
    public static let macNameKey = "macName"

    public let name: String
    public let macID: String

    public init(name: String, macID: String) {
        self.name = name
        self.macID = macID
    }

    public var serviceType: String {
        Self.serviceType
    }

    public var txtRecordData: Data {
        Self.txtRecordData(macID: macID, macName: name)
    }

    public static func discoveryInfo(macID: String, macName: String, port: UInt16) -> [String: String] {
        [
            androidPortKey: String(port),
            macIDKey: macID,
            macNameKey: macName,
        ]
    }

    public static func txtRecordData(macID: String, macName: String) -> Data {
        NetService.data(fromTXTRecord: discoveryInfo(macID: macID, macName: macName, port: 0).mapValues { Data($0.utf8) })
    }

    public static func txtRecordDictionary(from data: Data) -> [String: Data] {
        NetService.dictionary(fromTXTRecord: data)
    }
}
