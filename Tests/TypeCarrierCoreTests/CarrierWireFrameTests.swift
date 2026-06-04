import Foundation
import XCTest
@testable import TypeCarrierCore

final class CarrierWireFrameTests: XCTestCase {
    func testEncodesPayloadWithFourByteBigEndianLengthPrefix() throws {
        let payload = Data([0x7B, 0x7D])

        let frame = try CarrierWireFrame.encode(payload)

        XCTAssertEqual(Array(frame.prefix(4)), [0x00, 0x00, 0x00, 0x02])
        XCTAssertEqual(frame.dropFirst(4), payload)
    }

    func testNextPayloadWaitsForPartialFramesAndConsumesCompleteFrame() throws {
        let first = try CarrierWireFrame.encode(Data("first".utf8))
        let second = try CarrierWireFrame.encode(Data("second".utf8))
        var buffer = Data()

        buffer.append(first.prefix(6))
        XCTAssertNil(try CarrierWireFrame.nextPayload(from: &buffer))
        XCTAssertEqual(buffer, first.prefix(6))

        buffer.append(first.dropFirst(6))
        buffer.append(second)

        XCTAssertEqual(try CarrierWireFrame.nextPayload(from: &buffer), Data("first".utf8))
        XCTAssertEqual(try CarrierWireFrame.nextPayload(from: &buffer), Data("second".utf8))
        XCTAssertNil(try CarrierWireFrame.nextPayload(from: &buffer))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testRejectsOversizedFrameBeforeConsumingBuffer() throws {
        var buffer = Data([0x00, 0x10, 0x00, 0x01])

        XCTAssertThrowsError(try CarrierWireFrame.nextPayload(from: &buffer)) { error in
            XCTAssertEqual(error as? CarrierWireFrameError, .payloadTooLarge(1_048_577))
        }
        XCTAssertEqual(buffer, Data([0x00, 0x10, 0x00, 0x01]))
    }
}
