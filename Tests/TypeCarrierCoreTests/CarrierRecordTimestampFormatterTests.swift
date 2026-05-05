import XCTest
@testable import TypeCarrierCore

final class CarrierRecordTimestampFormatterTests: XCTestCase {
    func testHistoryTimestampUsesSlashSeparatedReminderStyle() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T01:58:00Z"))

        XCTAssertEqual(
            CarrierRecordTimestampFormatter.historyListText(for: date, timeZone: timeZone),
            "2026/5/5 09:58"
        )
    }

    func testHistoryTimestampDoesNotPadMonthOrDay() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-03-22T14:00:00Z"))

        XCTAssertEqual(
            CarrierRecordTimestampFormatter.historyListText(for: date, timeZone: timeZone),
            "2024/3/22 22:00"
        )
    }
}
