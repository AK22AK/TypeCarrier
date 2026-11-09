package org.typecarrier.android.transport

import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierJson
import uniffi.carrier_core.CoreCloseReason
import uniffi.carrier_core.CoreIdentity
import uniffi.carrier_core.CorePlatform
import uniffi.carrier_core.CoreResponderPolicy
import uniffi.carrier_core.CoreRole
import uniffi.carrier_core.CoreSession
import uniffi.carrier_core.CoreSessionEvent
import uniffi.carrier_core.generateStaticPrivateKey
import uniffi.carrier_core.publicKeyFor

/**
 * Runs the Android client against a receiver built on the same Rust core over real loopback TCP,
 * so the Kotlin socket handling, the JNA bindings and the protocol are exercised together.
 */
class AndroidV2CarrierClientTest {
    private val phoneKey = generateStaticPrivateKey()
    private val macKey = generateStaticPrivateKey()
    private val receiver = TestReceiver(macKey)

    @After
    fun tearDown() {
        receiver.close()
    }

    @Test
    fun pairsThenReconnectsAndDeliversTextWithReceipt() = runBlocking {
        receiver.pairingOpen = true
        val codes = mutableListOf<String>()
        val pairing = AndroidV2CarrierClient("127.0.0.1", receiver.port, phoneIdentity())
        val paired = pairing.connect(remoteStaticKey = null) { codes += it }

        assertTrue(paired is AndroidV2CarrierClient.Outcome.Established)
        assertEquals(receiver.codes.single(), codes.single())
        val macPublicKey = (paired as AndroidV2CarrierClient.Outcome.Established).peer.publicKey
        assertArrayEquals(publicKeyFor(macKey), macPublicKey)
        pairing.close()

        val reconnect = AndroidV2CarrierClient("127.0.0.1", receiver.port, phoneIdentity())
        val outcome = reconnect.connect(remoteStaticKey = macPublicKey)
        assertTrue(outcome is AndroidV2CarrierClient.Outcome.Established)
        val receipt = reconnect.sendText("你好，Mac", "Pixel", null)

        assertEquals(CarrierDeliveryReceipt.PasteStatus.Received, receipt?.pasteStatus)
        assertEquals("你好，Mac", receiver.texts.single())
        reconnect.close()
    }

    @Test
    fun unpairedReconnectIsRefused() = runBlocking {
        val client = AndroidV2CarrierClient("127.0.0.1", receiver.port, phoneIdentity())
        val outcome = client.connect(remoteStaticKey = publicKeyFor(macKey))

        assertEquals(CoreCloseReason.NOT_PAIRED, (outcome as AndroidV2CarrierClient.Outcome.Closed).reason)
        assertTrue(!client.isOpen)
    }

    @Test
    fun pairingRefusedWhileTheReceiverHasNotOpenedIt() = runBlocking {
        val client = AndroidV2CarrierClient("127.0.0.1", receiver.port, phoneIdentity())
        val outcome = client.connect(remoteStaticKey = null)

        assertEquals(CoreCloseReason.PAIRING_NOT_OPEN, (outcome as AndroidV2CarrierClient.Outcome.Closed).reason)
    }

    @Test
    fun nothingListeningFailsWithANetworkError() = runBlocking {
        val port = ServerSocket(0).use { it.localPort }
        val outcome = AndroidV2CarrierClient("127.0.0.1", port, phoneIdentity()).connect(remoteStaticKey = null)

        assertEquals(null, (outcome as AndroidV2CarrierClient.Outcome.Closed).reason)
    }

    private fun phoneIdentity() = CoreIdentity(phoneKey, "phone-1", "Pixel", CorePlatform.ANDROID, listOf("send.text"))
}

/** A minimal receiver: pairs when open (confirming automatically), trusts what it paired, answers texts with receipts. */
private class TestReceiver(private val staticKey: ByteArray) : AutoCloseable {
    private val server = ServerSocket(0)
    val port: Int = server.localPort
    @Volatile var pairingOpen = false
    private val trusted = CopyOnWriteArrayList<ByteArray>()
    val codes = CopyOnWriteArrayList<String>()
    val texts = CopyOnWriteArrayList<String>()

    init {
        thread(isDaemon = true) {
            while (!server.isClosed) {
                val socket = runCatching { server.accept() }.getOrNull() ?: break
                thread(isDaemon = true) { serve(socket) }
            }
        }
    }

    private fun serve(socket: Socket) {
        val policy = object : CoreResponderPolicy {
            override fun isTrusted(publicKey: ByteArray) = trusted.any { it.contentEquals(publicKey) }
            override fun isPairingOpen() = pairingOpen
        }
        val session = CoreSession(
            CoreRole.Responder,
            CoreIdentity(staticKey, "mac-1", "Test Mac", CorePlatform.MAC_OS, listOf("receive.paste", "receipt")),
            System.currentTimeMillis().toULong(),
            policy,
        )
        socket.use {
            val input = it.getInputStream()
            val output = it.getOutputStream()
            fun apply(events: List<CoreSessionEvent>) {
                for (event in events) {
                    when (event) {
                        is CoreSessionEvent.Write -> output.write(event.bytes)
                        is CoreSessionEvent.PairingCodeReady -> {
                            codes += event.code
                            trusted += event.peer.publicKey
                            apply(session.confirmPairing())
                        }
                        is CoreSessionEvent.Received -> {
                            val envelope = CarrierJson.decodeEnvelope(event.envelopeJson)
                            val payload = envelope.payload ?: continue
                            texts += payload.text
                            val receipt = """{"kind":"receipt","receipt":{"payloadID":"${payload.id}","receivedAt":"2026-11-06T00:00:00Z","pasteStatus":"received"},"version":1}"""
                            apply(session.sendEnvelope(receipt))
                        }
                        else -> Unit
                    }
                }
                output.flush()
            }
            val buffer = ByteArray(65_536)
            while (true) {
                val count = runCatching { input.read(buffer) }.getOrDefault(-1)
                if (count < 0 || session.isClosed()) break
                apply(session.receive(buffer.copyOf(count), System.currentTimeMillis().toULong()))
                if (session.isClosed()) break
            }
        }
    }

    override fun close() {
        server.close()
    }
}
