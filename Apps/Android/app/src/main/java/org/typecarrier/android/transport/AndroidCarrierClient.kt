package org.typecarrier.android.transport

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
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
import org.typecarrier.android.protocol.CarrierPostPasteAction
import org.typecarrier.android.protocol.CarrierWireFrame
import java.io.Closeable
import java.io.EOFException
import java.net.InetSocketAddress
import java.net.Socket
import java.time.Instant
import java.util.UUID

class AndroidCarrierClient(
    private val service: MacService,
    private val onClosed: (CarrierConnection) -> Unit = {},
) : CarrierConnection {
    @Volatile private var socket: Socket? = null
    override val isOpen: Boolean get() = socket?.isClosed == false
    private val replies = Channel<CarrierEnvelope>(16)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val sendMutex = Mutex()
    private var senderID: String? = null

    suspend fun pair(
        deviceID: String,
        deviceName: String,
        pairingCode: String?,
        trustToken: String?,
    ): AndroidBridgeResponse =
        withContext(Dispatchers.IO) {
            senderID = deviceID
            val nextSocket = Socket()
            socket = nextSocket
            nextSocket.connect(InetSocketAddress(service.host, service.port), connectTimeoutMillis)
            nextSocket.soTimeout = readTimeoutMillis

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
            val decoded = CarrierJson.decodeBridgeResponse(readFrame().decodeToString())
            val response = if (decoded.status == AndroidBridgeResponseStatus.Accepted &&
                service.macID != null && decoded.macID != null && service.macID != decoded.macID
            ) {
                decoded.copy(status = AndroidBridgeResponseStatus.Rejected, message = "连接目标身份已变更，请重新选择 Mac", trustToken = null)
            } else decoded
            if (response.status != AndroidBridgeResponseStatus.Accepted) {
                close()
            } else {
                nextSocket.soTimeout = 0
                scope.launch {
                    try {
                        while (true) replies.send(CarrierJson.decodeEnvelope(readFrame().decodeToString()))
                    } catch (error: Exception) {
                        replies.close(error)
                        close()
                    }
                }
            }
            response
        }

    override suspend fun sendText(
        text: String,
        deviceName: String,
        postPasteAction: CarrierPostPasteAction?,
    ): CarrierDeliveryReceipt? =
        sendMutex.withLock { withContext(Dispatchers.IO) {
            val activeSocket = socket ?: error("尚未连接 Mac")
            if (activeSocket.isClosed) {
                error("连接已关闭")
            }

            val payload = CarrierPayload(
                id = UUID.randomUUID().toString().uppercase(),
                createdAt = Instant.now().toString(),
                text = text,
                postPasteAction = postPasteAction,
            )
            val envelope = CarrierEnvelope.text(
                payload = payload,
                sender = CarrierDeviceIdentity(displayName = deviceName, deviceID = senderID),
            )

            sendFrame(CarrierJson.encode(envelope).encodeToByteArray())
            withTimeout(readTimeoutMillis.toLong()) {
                var matched: CarrierDeliveryReceipt? = null
                while (matched == null) {
                    val receipt = replies.receive().receipt
                    if (receipt?.payloadID == payload.id) matched = receipt
                }
                matched
            }
        } }

    override fun close() {
        runCatching { socket?.close() }
        socket = null
        replies.close()
        scope.cancel()
        onClosed(this)
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

        if (length < 0 || length > CarrierWireFrame.maxPayloadSize) {
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
