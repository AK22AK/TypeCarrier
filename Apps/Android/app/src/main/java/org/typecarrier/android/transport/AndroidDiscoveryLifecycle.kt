package org.typecarrier.android.transport

class AndroidDiscoveryLifecycle(
    private val startMacDiscovery: () -> Unit,
    private val stopMacDiscovery: () -> Unit,
    private val startPairingReceiver: () -> Unit,
    private val stopPairingReceiver: () -> Unit,
    private val disposePairingReceiver: () -> Unit,
) {
    fun start() {
        startMacDiscovery()
        startPairingReceiver()
    }

    fun stop() {
        stopMacDiscovery()
        stopPairingReceiver()
    }

    fun refresh() {
        stop()
        start()
    }

    fun close() {
        stopMacDiscovery()
        disposePairingReceiver()
    }
}
