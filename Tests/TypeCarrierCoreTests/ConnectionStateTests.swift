import XCTest
@testable import TypeCarrierCore

final class ConnectionStateTests: XCTestCase {
    func testConnectionStateDisplayTextIsStableForUI() {
        XCTAssertEqual(ConnectionState.idle.displayText, "Idle")
        XCTAssertEqual(ConnectionState.searching.displayText, "Searching")
        XCTAssertEqual(ConnectionState.advertising.displayText, "Advertising")
        XCTAssertEqual(ConnectionState.connecting("MacBook Pro").displayText, "Connecting to MacBook Pro")
        XCTAssertEqual(ConnectionState.connected("MacBook Pro").displayText, "Connected to MacBook Pro")
        XCTAssertEqual(ConnectionState.failed("No peer").displayText, "No peer")
    }

    func testConnectionStateSemanticFlags() {
        XCTAssertTrue(ConnectionState.connected("Mac").isConnected)
        XCTAssertFalse(ConnectionState.searching.isConnected)
        XCTAssertTrue(ConnectionState.failed("Denied").isFailed)
        XCTAssertFalse(ConnectionState.advertising.isFailed)
    }
}
