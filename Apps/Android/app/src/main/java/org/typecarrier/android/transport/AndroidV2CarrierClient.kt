package org.typecarrier.android.transport

import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierDeviceIdentity
import org.typecarrier.android.protocol.CarrierEnvelope
import org.typecarrier.android.protocol.CarrierJson
import org.typecarrier.android.protocol.CarrierPayload
import org.typecarrier.android.protocol.CarrierPostPasteAction
import uniffi.carrier_core.CoreCloseReason
import uniffi.carrier_core.CoreHelloMode
import uniffi.carrier_core.CoreIdentity
import uniffi.carrier_core.CorePeer
import uniffi.carrier_core.CoreRole
import uniffi.carrier_core.CoreSession
import uniffi.carrier_core.CoreSessionEvent
import uniffi.carrier_core.CoreSessionException

/**
 * One protocol v2 connection from this phone to a Mac. The protocol (handshake, encryption,
 * pairing codes, heartbeats) runs in the shared Rust core; this class owns the socket, the read
 * loop and the heartbeat timer, and turns sent texts into envelopes with delivery receipts.
 */
class AndroidV2CarrierClient(
    private val host: String,
    private val port: Int,
    private val identity: CoreIdentity,
    private val onClosed: (CarrierConnection) -> Unit = {},
) : CarrierConnection {
    sealed interface Outcome {
        data class Established(val peer: CorePeer) : Outcome
        /** `reason` is null when the network failed rather than the protocol closing. */
        data class Closed(val reason: CoreCloseReason?, val message: String) : Outcome
    }

    @Volatile private var socket: Socket? = null
    @Volatile private var session: CoreSession? = null
    @Volatile var peer: CorePeer? = null
        private set
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val outcome = CompletableDeferred<Outcome>()
    private val envelopes = Channel<CarrierEnvelope>(Channel.BUFFERED)
    private val writeLock = Any()
    private val sendMutex = Mutex()
    private val closed = AtomicBoolean(false)
    private var onPairingCode: (String) -> Unit = {}

    override val isOpen: Boolean get() = !closed.get() && session?.isEstablished() == true

    /**
     * Pairs when [remoteStaticKey] is null (the phone shows a code and waits for the Mac's
     * confirmation), otherwise reconnects to the Mac that owns that key.
     */
    suspend fun connect(remoteStaticKey: ByteArray?, onPairingCode: (String) -> Unit = {}): Outcome =
        withContext(Dispatchers.IO) {
            this@AndroidV2CarrierClient.onPairingCode = onPairingCode
            val nextSocket = Socket()
            socket = nextSocket
            try {
                nextSocket.tcpNoDelay = true
                nextSocket.keepAlive = true
                nextSocket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            } catch (error: IOException) {
                close()
                return@withContext Outcome.Closed(null, error.localizedMessage ?: "无法连接设备")
            }
            val mode = if (remoteStaticKey == null) CoreHelloMode.PAIR else CoreHelloMode.CONNECT
            val nextSession = CoreSession(CoreRole.Initiator(mode, remoteStaticKey), identity, nowMs(), null)
            session = nextSession
            scope.launch { readLoop(nextSocket, nextSession) }
            apply(nextSession.start())

            val deadline = if (remoteStaticKey == null) PAIRING_TIMEOUT_MS else HANDSHAKE_TIMEOUT_MS
            val result = withTimeoutOrNull(deadline) { outcome.await() }
                ?: Outcome.Closed(CoreCloseReason.HANDSHAKE_FAILED, "连接超时")
            if (result is Outcome.Established) {
                scope.launch { tickLoop(nextSession) }
            } else {
                close()
            }
            result
        }

    override suspend fun sendText(
        text: String,
        deviceName: String,
        postPasteAction: CarrierPostPasteAction?,
    ): CarrierDeliveryReceipt? = sendMutex.withLock {
        withContext(Dispatchers.IO) {
            val activeSession = session?.takeIf { isOpen } ?: error("连接已关闭")
            val payload = CarrierPayload(
                id = UUID.randomUUID().toString().uppercase(),
                // Whole seconds: the Mac decodes ISO 8601 without fractions.
                createdAt = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString(),
                text = text,
                postPasteAction = postPasteAction,
            )
            val envelope = CarrierEnvelope.text(
                payload = payload,
                sender = CarrierDeviceIdentity(displayName = deviceName, deviceID = identity.deviceId),
            )
            val events = try {
                activeSession.sendEnvelope(CarrierJson.encode(envelope))
            } catch (error: CoreSessionException.MessageTooLarge) {
                error("文本过长")
            }
            apply(events)
            withTimeout(RECEIPT_TIMEOUT_MS) {
                var matched: CarrierDeliveryReceipt? = null
                while (matched == null) {
                    val receipt = envelopes.receive().receipt
                    if (receipt?.payloadID == payload.id) matched = receipt
                }
                matched
            }
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        session?.let { runCatching { write(it.shutdown()) } }
        if (!outcome.isCompleted) outcome.complete(Outcome.Closed(CoreCloseReason.SHUTDOWN, "连接已关闭"))
        runCatching { socket?.close() }
        envelopes.close()
        scope.cancel()
        onClosed(this)
    }

    // MARK: - Socket

    private fun readLoop(socket: Socket, session: CoreSession) {
        val buffer = ByteArray(READ_BUFFER_SIZE)
        val message = try {
            val input = socket.getInputStream()
            while (!closed.get()) {
                val count = input.read(buffer)
                if (count < 0) break
                apply(session.receive(buffer.copyOf(count), nowMs()))
            }
            "设备已断开连接"
        } catch (error: IOException) {
            error.localizedMessage ?: "连接已断开"
        }
        if (!outcome.isCompleted) outcome.complete(Outcome.Closed(null, message))
        close()
    }

    private suspend fun tickLoop(session: CoreSession) {
        while (scope.isActive && !closed.get()) {
            delay(TICK_INTERVAL_MS)
            apply(session.tick(nowMs()))
        }
    }

    private fun apply(events: List<CoreSessionEvent>) {
        for (event in events) {
            when (event) {
                is CoreSessionEvent.Write -> write(listOf(event))
                is CoreSessionEvent.PairingCodeReady -> {
                    peer = event.peer
                    onPairingCode(event.code)
                }
                is CoreSessionEvent.Established -> {
                    peer = event.peer
                    outcome.complete(Outcome.Established(event.peer))
                }
                is CoreSessionEvent.Received ->
                    runCatching { CarrierJson.decodeEnvelope(event.envelopeJson) }.getOrNull()?.let { envelopes.trySend(it) }
                is CoreSessionEvent.Closed -> {
                    outcome.complete(Outcome.Closed(event.reason, closeMessage(event.reason)))
                    close()
                }
            }
        }
    }

    private fun write(events: List<CoreSessionEvent>) {
        val output = socket?.takeUnless { it.isClosed }?.getOutputStream() ?: return
        synchronized(writeLock) {
            for (event in events) {
                if (event is CoreSessionEvent.Write) output.write(event.bytes)
            }
            output.flush()
        }
    }

    companion object {
        const val CONNECT_TIMEOUT_MS = 5_000
        const val HANDSHAKE_TIMEOUT_MS = 8_000L
        /** How long the person has to compare codes and confirm on the Mac. */
        const val PAIRING_TIMEOUT_MS = 70_000L
        const val RECEIPT_TIMEOUT_MS = 10_000L
        const val TICK_INTERVAL_MS = 2_000L
        private const val READ_BUFFER_SIZE = 64 * 1024

        private fun nowMs(): ULong = System.currentTimeMillis().toULong()

        fun closeMessage(reason: CoreCloseReason): String = when (reason) {
            CoreCloseReason.PAIRING_REJECTED -> "设备拒绝了配对，可以重新发起。"
            CoreCloseReason.PAIRING_NOT_OPEN -> "设备正在处理另一个配对请求，请稍后重试。"
            CoreCloseReason.NOT_PAIRED -> "这台设备已移除与本机的配对，请重新配对。"
            CoreCloseReason.UNSUPPORTED_VERSION -> "设备上的 TypeCarrier 版本不兼容，请把两边都更新到最新版。"
            CoreCloseReason.HANDSHAKE_FAILED -> "加密握手失败，设备可能已重置，请重新配对。"
            CoreCloseReason.REPLACED -> "已在别处重新连接。"
            CoreCloseReason.HEARTBEAT_TIMEOUT -> "设备长时间无响应。"
            CoreCloseReason.PROTOCOL_VIOLATION -> "通信异常，请重试。"
            CoreCloseReason.SHUTDOWN -> "连接已关闭。"
        }
    }
}
