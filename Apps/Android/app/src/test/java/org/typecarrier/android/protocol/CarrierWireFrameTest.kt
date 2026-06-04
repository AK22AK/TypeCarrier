package org.typecarrier.android.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CarrierWireFrameTest {
    @Test
    fun encodePrefixesPayloadWithBigEndianLength() {
        val frame = CarrierWireFrame.encode(byteArrayOf(0x41, 0x42, 0x43))

        assertArrayEquals(byteArrayOf(0, 0, 0, 3, 0x41, 0x42, 0x43), frame)
    }

    @Test
    fun nextPayloadWaitsForCompleteFrame() {
        val buffer = mutableListOf<Byte>(0, 0, 0, 5, 0x48, 0x65)

        assertNull(CarrierWireFrame.nextPayload(buffer))
        assertEquals(listOf<Byte>(0, 0, 0, 5, 0x48, 0x65), buffer)
    }

    @Test
    fun nextPayloadConsumesOneFrameAndLeavesStickyBytes() {
        val first = CarrierWireFrame.encode("one".encodeToByteArray())
        val second = CarrierWireFrame.encode("two".encodeToByteArray())
        val buffer = (first + second).toMutableList()

        assertEquals("one", CarrierWireFrame.nextPayload(buffer)?.decodeToString())
        assertEquals(second.toList(), buffer)
    }

    @Test
    fun nextPayloadRejectsOversizedFrame() {
        val buffer = mutableListOf<Byte>(0, 0x10, 0, 1)

        val error = kotlin.runCatching { CarrierWireFrame.nextPayload(buffer) }.exceptionOrNull()

        assertTrue(error is CarrierWireFrameError.PayloadTooLarge)
        assertEquals(listOf<Byte>(0, 0x10, 0, 1), buffer)
    }
}
