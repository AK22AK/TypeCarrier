package org.typecarrier.android.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CarrierJsonTest {
    @Test
    fun encodesTextEnvelopeUsingSharedWireNames() {
        val envelope = CarrierEnvelope.text(
            payload = CarrierPayload(
                id = "4E1E869A-4537-4D56-A3E8-AABF449E5D87",
                createdAt = "2026-06-01T08:00:00Z",
                text = "hello",
            ),
            sender = CarrierDeviceIdentity(displayName = "Pixel"),
        )

        assertEquals(
            """{"version":1,"kind":"text","payload":{"id":"4E1E869A-4537-4D56-A3E8-AABF449E5D87","createdAt":"2026-06-01T08:00:00Z","text":"hello"},"sender":{"displayName":"Pixel"}}""",
            CarrierJson.encode(envelope),
        )
    }

    @Test
    fun decodesAcceptedPairingResponse() {
        val response = CarrierJson.decodeBridgeResponse(
            """{"message":"Paired.","status":"accepted","trustToken":"token-1"}""",
        )

        assertEquals(AndroidBridgeResponseStatus.Accepted, response.status)
        assertEquals("Paired.", response.message)
        assertEquals("token-1", response.trustToken)
    }

    @Test
    fun optionalNullsAreOmittedOnHandshake() {
        val handshake = AndroidBridgeHandshake(
            version = 1,
            deviceID = "android-1",
            deviceName = "Pixel",
            pairingCode = "123456",
        )

        val json = CarrierJson.encode(handshake)

        assertEquals(
            """{"version":1,"deviceID":"android-1","deviceName":"Pixel","pairingCode":"123456"}""",
            json,
        )
        assertNull(CarrierJson.decodeHandshake(json).tokenProof)
    }
}
