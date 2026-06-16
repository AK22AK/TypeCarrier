package org.typecarrier.android.transport

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidDiscoveryLifecycleTest {
    @Test
    fun startStartsMacDiscoveryAndPairingReceiver() {
        val recorder = LifecycleRecorder()
        val lifecycle = recorder.makeLifecycle()

        lifecycle.start()

        assertEquals(
            listOf("mac.start", "pairing.start"),
            recorder.events,
        )
    }

    @Test
    fun refreshRestartsMacDiscoveryAndPairingReceiver() {
        val recorder = LifecycleRecorder()
        val lifecycle = recorder.makeLifecycle()

        lifecycle.refresh()

        assertEquals(
            listOf("mac.stop", "pairing.stop", "mac.start", "pairing.start"),
            recorder.events,
        )
    }

    @Test
    fun stopStopsMacDiscoveryAndPairingReceiver() {
        val recorder = LifecycleRecorder()
        val lifecycle = recorder.makeLifecycle()

        lifecycle.stop()

        assertEquals(
            listOf("mac.stop", "pairing.stop"),
            recorder.events,
        )
    }

    @Test
    fun closeStopsMacDiscoveryAndDisposesPairingReceiver() {
        val recorder = LifecycleRecorder()
        val lifecycle = recorder.makeLifecycle()

        lifecycle.close()

        assertEquals(
            listOf("mac.stop", "pairing.dispose"),
            recorder.events,
        )
    }
}

private class LifecycleRecorder {
    val events = mutableListOf<String>()

    fun makeLifecycle(): AndroidDiscoveryLifecycle =
        AndroidDiscoveryLifecycle(
            startMacDiscovery = { events += "mac.start" },
            stopMacDiscovery = { events += "mac.stop" },
            startPairingReceiver = { events += "pairing.start" },
            stopPairingReceiver = { events += "pairing.stop" },
            disposePairingReceiver = { events += "pairing.dispose" },
        )
}
