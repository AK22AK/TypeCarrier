import Foundation
import XCTest
@testable import TypeCarrierCore

@MainActor
final class CarrierV2ClientSearchTimeoutTests: XCTestCase {
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        defaultsSuiteName = "CarrierV2ClientSearchTimeoutTests.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
    }

    private func makeClient(timeout: Duration = .milliseconds(150)) -> CarrierV2Client {
        CarrierV2Client(
            displayName: "Test iPhone",
            deviceID: "test-phone",
            trustStore: CarrierV2TrustStore(storage: CarrierV2MemoryStorage()),
            defaults: UserDefaults(suiteName: defaultsSuiteName)!,
            searchTimeout: timeout
        )
    }

    private func wait(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    func testSearchStopsAfterTimeoutWithNothingConnected() async {
        let client = makeClient()
        client.start()
        XCTAssertEqual(client.connectionState, .searching)

        await wait(.milliseconds(500))

        XCTAssertTrue(client.searchTimedOut)
        XCTAssertEqual(client.connectionState, .failed(CarrierV2Client.searchTimedOutMessage))
        client.stop()
    }

    func testRetrySearchStartsAFreshBoundedSearch() async {
        let client = makeClient()
        client.start()
        await wait(.milliseconds(500))
        XCTAssertTrue(client.searchTimedOut)

        client.retrySearch()
        XCTAssertFalse(client.searchTimedOut)
        XCTAssertEqual(client.connectionState, .searching)

        await wait(.milliseconds(500))
        XCTAssertTrue(client.searchTimedOut)
        client.stop()
    }

    func testSearchHoldKeepsSearchingAndRestartsATimedOutSearch() async {
        let client = makeClient()
        client.start()
        await wait(.milliseconds(500))
        XCTAssertTrue(client.searchTimedOut)

        client.beginSearchHold()
        XCTAssertFalse(client.searchTimedOut)
        XCTAssertEqual(client.connectionState, .searching)
        await wait(.milliseconds(500))
        XCTAssertFalse(client.searchTimedOut, "The Mac list keeps the search alive while it is open.")

        client.endSearchHold()
        await wait(.milliseconds(500))
        XCTAssertTrue(client.searchTimedOut)
        client.stop()
    }

    func testResumeRecoveryExtendsTheCurrentDeadline() async {
        let client = makeClient()
        client.start()
        client.extendCurrentSearchTimeoutForResumeRecovery(to: .seconds(5))

        await wait(.milliseconds(500))
        XCTAssertFalse(client.searchTimedOut)
        client.stop()
    }

    func testStopClearsTimedOutStateAndStartSearchesAgain() async {
        let client = makeClient()
        client.start()
        await wait(.milliseconds(500))
        XCTAssertTrue(client.searchTimedOut)

        client.stop()
        XCTAssertFalse(client.searchTimedOut)
        XCTAssertEqual(client.connectionState, .idle)

        client.start()
        XCTAssertEqual(client.connectionState, .searching)
        client.stop()
    }
}
