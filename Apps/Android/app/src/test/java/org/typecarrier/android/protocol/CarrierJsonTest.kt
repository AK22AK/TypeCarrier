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
    fun encodesTextEnvelopeWithPostPasteReturnAction() {
        val envelope = CarrierEnvelope.text(
            payload = CarrierPayload(
                id = "5C6D00D8-8083-4303-B1D2-D02176E0AA5D",
                createdAt = "2026-07-05T07:00:00Z",
                text = "hello",
                postPasteAction = CarrierPostPasteAction.PressReturn,
            ),
            sender = CarrierDeviceIdentity(displayName = "Pixel"),
        )

        val json = CarrierJson.encode(envelope)
        val decoded = CarrierJson.decodeEnvelope(json)

        assertEquals(
            """{"version":1,"kind":"text","payload":{"id":"5C6D00D8-8083-4303-B1D2-D02176E0AA5D","createdAt":"2026-07-05T07:00:00Z","text":"hello","postPasteAction":"pressReturn"},"sender":{"displayName":"Pixel"}}""",
            json,
        )
        assertEquals(CarrierPostPasteAction.PressReturn, decoded.payload?.postPasteAction)
    }

    @Test
    fun plainTextEnvelopeOmitsPostPasteAction() {
        val envelope = CarrierEnvelope.text(
            payload = CarrierPayload(
                id = "7A4322BC-6460-40A7-B788-8799F466C75E",
                createdAt = "2026-07-05T07:10:00Z",
                text = "hello",
            ),
        )

        val json = CarrierJson.encode(envelope)

        assertEquals(false, json.contains("postPasteAction"))
    }
}
