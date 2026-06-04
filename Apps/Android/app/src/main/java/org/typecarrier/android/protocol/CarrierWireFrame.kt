package org.typecarrier.android.protocol

sealed class CarrierWireFrameError(message: String) : IllegalArgumentException(message) {
    class PayloadTooLarge(val size: Int) : CarrierWireFrameError("Payload is too large: $size bytes")
}

object CarrierWireFrame {
    const val maxPayloadSize: Int = 1_048_576

    fun encode(payload: ByteArray): ByteArray {
        if (payload.size > maxPayloadSize) {
            throw CarrierWireFrameError.PayloadTooLarge(payload.size)
        }

        val frame = ByteArray(4 + payload.size)
        frame[0] = ((payload.size ushr 24) and 0xff).toByte()
        frame[1] = ((payload.size ushr 16) and 0xff).toByte()
        frame[2] = ((payload.size ushr 8) and 0xff).toByte()
        frame[3] = (payload.size and 0xff).toByte()
        payload.copyInto(frame, destinationOffset = 4)
        return frame
    }

    fun nextPayload(buffer: MutableList<Byte>): ByteArray? {
        if (buffer.size < 4) {
            return null
        }

        val length = ((buffer[0].toInt() and 0xff) shl 24) or
            ((buffer[1].toInt() and 0xff) shl 16) or
            ((buffer[2].toInt() and 0xff) shl 8) or
            (buffer[3].toInt() and 0xff)

        if (length > maxPayloadSize) {
            throw CarrierWireFrameError.PayloadTooLarge(length)
        }

        val frameLength = 4 + length
        if (buffer.size < frameLength) {
            return null
        }

        val payload = buffer.subList(4, frameLength).toByteArray()
        buffer.subList(0, frameLength).clear()
        return payload
    }
}
