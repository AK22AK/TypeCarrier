package org.typecarrier.android.transport

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MacDiscoveryResolutionQueueTest {
    @Test
    fun enqueueStartsFirstServiceAndQueuesTheRest() {
        val queue = MacDiscoveryResolutionQueue<String> { it }

        assertEquals("Mac A", queue.enqueue("Mac A"))
        assertNull(queue.enqueue("Mac B"))
        assertNull(queue.enqueue("Mac C"))

        assertEquals("Mac B", queue.finishCurrent())
        assertEquals("Mac C", queue.finishCurrent())
        assertNull(queue.finishCurrent())
    }

    @Test
    fun clearDropsActiveAndPendingServices() {
        val queue = MacDiscoveryResolutionQueue<String> { it }

        assertEquals("Mac A", queue.enqueue("Mac A"))
        assertNull(queue.enqueue("Mac B"))

        queue.clear()

        assertEquals("Mac C", queue.enqueue("Mac C"))
        assertNull(queue.finishCurrent())
    }
}
