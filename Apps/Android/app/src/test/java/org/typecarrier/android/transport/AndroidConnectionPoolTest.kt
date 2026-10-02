package org.typecarrier.android.transport

import java.io.IOException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierPostPasteAction

class AndroidConnectionPoolTest {
    @Test fun sameNameReceiversRouteOnlyToSelectedIdentityAndDisconnectIndependently() = runBlocking {
        val pool = AndroidConnectionPool()
        val a = MacService("Mac", "host-a", 1, macID = "a")
        val b = MacService("Mac", "host-b", 2, macID = "b")
        val first = FakeConnection()
        val second = FakeConnection()
        pool.addAuthenticated(a, first)
        pool.addAuthenticated(b, second)
        pool.send(b, "to B", "sender", CarrierPostPasteAction.PressReturn)
        assertEquals(emptyList<String>(), first.texts)
        assertEquals(listOf("to B"), second.texts)
        assertEquals(CarrierPostPasteAction.PressReturn, second.action)
        pool.disconnect(b)
        assertEquals(listOf(a), pool.connectedServices.value)
        assertTrue(second.closed)
        assertFalse(first.closed)
        try { pool.send(b, "offline", "sender", null); fail("must not fall back to A") } catch (_: IllegalStateException) {}
        assertTrue(first.texts.isEmpty())
    }

    @Test fun failedSelectedSendAndOldDisconnectCannotCloseAnotherConnection() = runBlocking {
        val pool = AndroidConnectionPool()
        val a = MacService("Mac", "host-a", 1, macID = "a")
        val b = MacService("Mac", "host-b", 2, macID = "b")
        val old = FakeConnection()
        val replacement = FakeConnection()
        val other = FakeConnection()
        pool.addAuthenticated(a, old)
        pool.addAuthenticated(b, other)
        pool.addAuthenticated(a, replacement)
        assertTrue(old.closed)
        pool.remove(old)
        assertEquals(2, pool.connectedServices.value.size)
        replacement.fails = true
        try { pool.send(a, "fail", "sender", null); fail("expected failure") } catch (_: IOException) {}
        assertEquals(listOf(b), pool.connectedServices.value)
        assertFalse(other.closed)
        pool.send(b, "still usable", "sender", null)
        assertEquals(listOf("still usable"), other.texts)
    }

    private class FakeConnection : CarrierConnection {
        var closed = false
        var fails = false
        val texts = mutableListOf<String>()
        var action: CarrierPostPasteAction? = null
        override suspend fun sendText(text: String, deviceName: String, postPasteAction: CarrierPostPasteAction?): CarrierDeliveryReceipt? {
            if (fails) throw IOException("disconnected")
            texts.add(text)
            action = postPasteAction
            return null
        }
        override fun close() { closed = true }
    }
}
