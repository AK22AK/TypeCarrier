package org.typecarrier.android.transport

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.typecarrier.android.protocol.AndroidBridgeHandshake
import org.typecarrier.android.protocol.AndroidBridgeResponse
import org.typecarrier.android.protocol.AndroidBridgeResponseStatus
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierDeviceIdentity
import org.typecarrier.android.protocol.CarrierEnvelope
import org.typecarrier.android.protocol.CarrierJson
import org.typecarrier.android.protocol.CarrierPayload
import org.typecarrier.android.protocol.CarrierWireFrame
import java.io.Closeable
import java.io.EOFException
import java.net.InetSocketAddress
import java.net.Socket
import java.time.Instant
import java.util.UUID

class AndroidCarrierClient(
    private val service: MacService,
) : Closeable {
    private var socket: Socket? = null

    suspend fun pair(
        deviceID: String,
        deviceName: String,
        pairingCode: String?,
        trustToken: String?,
    ): AndroidBridgeResponse =
        withContext(Dispatchers.IO) {
            close()
            val nextSocket = Socket()
            nextSocket.connect(InetSocketAddress(service.host, service.port), connectTimeoutMillis)
            nextSocket.soTimeout = readTimeoutMillis
            socket = nextSocket

            val challenge = trustToken?.let { UUID.randomUUID().toString() }
            val handshake = if (trustToken != null && challenge != null) {
                AndroidBridgeHandshake(
                    deviceID = deviceID,
                    deviceName = deviceName,
                    tokenProof = org.typecarrier.android.protocol.AndroidTrustToken(trustToken).proof(challenge),
                    challenge = challenge,
                )
            } else {
                AndroidBridgeHandshake(
                    deviceID = deviceID,
                    deviceName = deviceName,
                    pairingCode = pairingCode,
                )
            }
            sendFrame(CarrierJson.encode(handshake).encodeToByteArray())
            val response = CarrierJson.decodeBridgeResponse(readFrame().decodeToString())
            if (response.status != AndroidBridgeResponseStatus.Accepted) {
                close()
            }
            response
        }

    suspend fun sendText(text: String, deviceName: String): CarrierDeliveryReceipt? =
        withContext(Dispatchers.IO) {
            val activeSocket = socket ?: error("尚未连接 Mac")
            if (activeSocket.isClosed) {
                error("连接已关闭")
            }

            val payload = CarrierPayload(
                id = UUID.randomUUID().toString().uppercase(),
                createdAt = Instant.now().toString(),
                text = text,
            )
            val envelope = CarrierEnvelope.text(
                payload = payload,
                sender = CarrierDeviceIdentity(displayName = deviceName),
            )

            sendFrame(CarrierJson.encode(envelope).encodeToByteArray())
            val reply = CarrierJson.decodeEnvelope(readFrame().decodeToString())
            reply.receipt
        }

    override fun close() {
        runCatching { socket?.close() }
        socket = null
    }

    private fun sendFrame(payload: ByteArray) {
        val output = socket?.getOutputStream() ?: error("尚未连接 Mac")
        output.write(CarrierWireFrame.encode(payload))
        output.flush()
    }

    private fun readFrame(): ByteArray {
        val input = socket?.getInputStream() ?: error("尚未连接 Mac")
        val header = input.readFully(4)
        val length = ((header[0].toInt() and 0xff) shl 24) or
            ((header[1].toInt() and 0xff) shl 16) or
            ((header[2].toInt() and 0xff) shl 8) or
            (header[3].toInt() and 0xff)

        if (length > CarrierWireFrame.maxPayloadSize) {
            error("响应过大：$length bytes")
        }
        return input.readFully(length)
    }

    private fun java.io.InputStream.readFully(size: Int): ByteArray {
        val bytes = ByteArray(size)
        var offset = 0
        while (offset < size) {
            val read = read(bytes, offset, size - offset)
            if (read < 0) {
                throw EOFException("连接已断开")
            }
            offset += read
        }
        return bytes
    }

    private companion object {
        const val connectTimeoutMillis = 5_000
        const val readTimeoutMillis = 10_000
    }
}
