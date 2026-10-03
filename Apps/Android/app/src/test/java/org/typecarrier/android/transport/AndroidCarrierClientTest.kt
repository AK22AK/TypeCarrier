package org.typecarrier.android.transport

import java.io.DataInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.typecarrier.android.protocol.AndroidBridgeResponseStatus
import org.typecarrier.android.protocol.AndroidTrustToken
import org.typecarrier.android.protocol.CarrierJson
import org.typecarrier.android.protocol.CarrierWireFrame

class AndroidCarrierClientTest {
    @Test fun rejectedPairingDoesNotCreateUsableConnection() = runBlocking {
        ServerSocket(0).use { listener ->
            val failure = AtomicReference<Throwable?>()
            val worker = thread {
                try {
                    listener.accept().use { socket ->
                        val handshake = CarrierJson.decodeHandshake(socket.readFrame())
                        assertEquals("000000", handshake.pairingCode)
                        assertNull(handshake.tokenProof)
                        socket.writeFrame("""{"status":"invalidPairing","message":"bad code"}""")
                    }
                } catch (error: Throwable) { failure.set(error) }
            }
            val client = AndroidCarrierClient(MacService("Mac", "127.0.0.1", listener.localPort))
            val reply = client.pair("phone", "Phone", "000000", null)
            assertEquals(AndroidBridgeResponseStatus.InvalidPairing, reply.status)
            assertFalse(client.isOpen)
            worker.join(3000)
            failure.get()?.let { throw it }
            client.close()
        }
    }

    @Test fun changedReceiverIdentityIsRejectedInsteadOfChangingSendTarget() = runBlocking {
        ServerSocket(0).use { listener ->
            val worker = thread {
                listener.accept().use { socket ->
                    socket.readFrame()
                    socket.writeFrame("""{"status":"accepted","macID":"other-mac","macName":"Other"}""")
                }
            }
            val client = AndroidCarrierClient(MacService("Chosen", "127.0.0.1", listener.localPort, macID = "chosen-mac"))
            assertEquals(AndroidBridgeResponseStatus.Rejected, client.pair("phone", "Phone", "123456", null).status)
            assertFalse(client.isOpen)
            worker.join(3000)
            client.close()
        }
    }

    @Test fun tokenAuthenticationPreservesDeviceIdentityAndMatchesOnlyOwnReceipt() = runBlocking {
        ServerSocket(0).use { listener ->
            val failure = AtomicReference<Throwable?>()
            val worker = thread {
                try {
                    listener.accept().use { socket ->
                        val handshake = CarrierJson.decodeHandshake(socket.readFrame())
                        assertEquals("phone-a", handshake.deviceID)
                        assertNull(handshake.pairingCode)
                        assertTrue(AndroidTrustToken("test-only-token").verify(handshake.challenge!!, handshake.tokenProof!!))
                        socket.writeFrame("""{"status":"accepted","macID":"mac-a","macName":"Mac"}""")
                        val envelope = CarrierJson.decodeEnvelope(socket.readFrame())
                        assertEquals("phone-a", envelope.sender?.deviceID)
                        assertEquals("hello", envelope.payload?.text)
                        socket.writeFrame(receipt("other-payload"))
                        socket.writeFrame(receipt(envelope.payload!!.id))
                    }
                } catch (error: Throwable) { failure.set(error) }
            }
            val client = AndroidCarrierClient(MacService("Mac", "127.0.0.1", listener.localPort))
            assertEquals(AndroidBridgeResponseStatus.Accepted, client.pair("phone-a", "Phone", null, "test-only-token").status)
            val reply = client.sendText("hello", "Phone", null)
            assertNotEquals("other-payload", reply?.payloadID)
            assertEquals(org.typecarrier.android.protocol.CarrierDeliveryReceipt.PasteStatus.Received, reply?.pasteStatus)
            worker.join(3000)
            failure.get()?.let { throw it }
            client.close()
        }
    }

    private fun receipt(id: String) = """{"kind":"receipt","receipt":{"payloadID":"$id","receivedAt":"2026-10-02T00:00:00Z","pasteStatus":"received"}}"""
    private fun Socket.readFrame(): String {
        val input = DataInputStream(getInputStream())
        val bytes = ByteArray(input.readInt())
        input.readFully(bytes)
        return bytes.decodeToString()
    }
    private fun Socket.writeFrame(text: String) {
        getOutputStream().write(CarrierWireFrame.encode(text.encodeToByteArray()))
        getOutputStream().flush()
    }
}
