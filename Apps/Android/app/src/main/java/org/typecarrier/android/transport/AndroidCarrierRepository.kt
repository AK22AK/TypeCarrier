package org.typecarrier.android.transport

import android.content.Context
import android.os.Build
import java.io.Closeable
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierPostPasteAction
import uniffi.carrier_core.CoreCloseReason
import uniffi.carrier_core.CoreIdentity
import uniffi.carrier_core.CorePlatform

/** Shown while pairing: the same code appears on the Mac, which confirms it. */
data class AndroidPairingPrompt(val macName: String, val code: String)

sealed interface AndroidConnectResult {
    data object Connected : AndroidConnectResult
    /** `pairingRemoved` is true when the Mac no longer knows this phone and the stored pairing was dropped. */
    data class Rejected(val message: String, val pairingRemoved: Boolean = false) : AndroidConnectResult
}

interface AndroidCarrierRepository : Closeable {
    val connectedServices: StateFlow<List<MacService>>
    val services: StateFlow<List<MacService>>
    val discoveryError: StateFlow<String?>
    val discoveryPrecondition: StateFlow<AndroidDiscoveryPrecondition>
    val deviceName: String
    val trustedMacs: List<MacService>
    val pairingPrompt: StateFlow<AndroidPairingPrompt?>
    var manualHost: String
    var manualPort: String
    var senderDisplayName: String
    var launchesIntoInputMode: Boolean
    var enablesSendReturnGesture: Boolean

    fun startDiscovery()
    fun stopDiscovery()
    fun refreshDiscovery()
    fun isPaired(service: MacService): Boolean
    fun forgetTrustedMac(service: MacService)
    /** Reconnects to a paired Mac, or pairs first (publishing [pairingPrompt]) when it is new. */
    suspend fun connect(service: MacService): AndroidConnectResult
    suspend fun sendText(
        service: MacService,
        text: String,
        senderDisplayName: String,
        postPasteAction: CarrierPostPasteAction? = null,
    ): CarrierDeliveryReceipt?
    fun closeConnection(service: MacService? = null)
}

class AndroidCarrierRepositoryImpl(
    context: Context,
) : AndroidCarrierRepository {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("typecarrier", Context.MODE_PRIVATE)
    private val _services = MutableStateFlow(emptyList<MacService>())
    private val _discoveryError = MutableStateFlow<String?>(null)
    private val _discoveryPrecondition = MutableStateFlow(AndroidNetworkDiscoveryPreconditions.current(appContext))
    private val connections = AndroidConnectionPool()
    override val connectedServices: StateFlow<List<MacService>> = connections.connectedServices
    private var manualHostValue = ""
    private var manualPortValue = defaultCarrierPort.toString()
    private val trustStore = AndroidV2TrustStore(prefs, KeystoreSecretSealer())
    private val _pairingPrompt = MutableStateFlow<AndroidPairingPrompt?>(null)
    override val pairingPrompt: StateFlow<AndroidPairingPrompt?> = _pairingPrompt
    private val discovery = MacDiscovery(
        context = appContext,
        onServicesChanged = { services ->
            connections.refreshDisplayNames(services)
            _services.value = services
        },
        onError = {
            errorMessage = it
            _discoveryError.value = it
        },
    )
    private var errorMessage: String? = null

    override val services: StateFlow<List<MacService>> = _services
    override val discoveryError: StateFlow<String?> = _discoveryError
    override val discoveryPrecondition: StateFlow<AndroidDiscoveryPrecondition> = _discoveryPrecondition

    override val deviceName: String = localDeviceName()

    override val trustedMacs: List<MacService>
        get() = trustStore.pairedMacs().mapNotNull { mac ->
            val host = mac.host ?: return@mapNotNull null
            val port = mac.port ?: return@mapNotNull null
            MacService(name = mac.name, host = host, port = port, macID = mac.macID)
        }.sortedBy { it.name }

    override var manualHost: String
        get() = manualHostValue
        set(value) {
            manualHostValue = value.trim()
        }

    override var manualPort: String
        get() = manualPortValue
        set(value) {
            manualPortValue = value.filter(Char::isDigit).take(5)
        }

    override var senderDisplayName: String
        get() = prefs.getString("sender_display_name", "") ?: ""
        set(value) {
            prefs.edit().putString("sender_display_name", value.trim()).apply()
        }

    override var launchesIntoInputMode: Boolean
        get() = prefs.getBoolean("launches_into_input_mode", true)
        set(value) {
            prefs.edit().putBoolean("launches_into_input_mode", value).apply()
        }

    override var enablesSendReturnGesture: Boolean
        get() = prefs.getBoolean("enables_send_return_gesture", false)
        set(value) {
            prefs.edit().putBoolean("enables_send_return_gesture", value).apply()
        }

    private val deviceID: String
        get() = prefs.getString("device_id", null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString("device_id", it).apply()
        }

    override fun startDiscovery() {
        refreshDiscoveryPrecondition()
        discovery.start()
    }

    override fun stopDiscovery() {
        discovery.stop()
    }

    override fun refreshDiscovery() {
        refreshDiscoveryPrecondition()
        discovery.stop()
        discovery.start()
    }

    override fun isPaired(service: MacService): Boolean = pairedMac(service) != null

    override fun forgetTrustedMac(service: MacService) {
        pairedMac(service)?.let { trustStore.unpair(it.macID) }
    }

    override suspend fun connect(service: MacService): AndroidConnectResult {
        val paired = pairedMac(service)
        val client = AndroidV2CarrierClient(service.host, service.port, identity(), onClosed = connections::remove)
        val outcome = try {
            client.connect(paired?.publicKeyBytes) { code ->
                _pairingPrompt.value = AndroidPairingPrompt(macName = service.name, code = code)
            }
        } finally {
            _pairingPrompt.value = null
        }
        return when (outcome) {
            is AndroidV2CarrierClient.Outcome.Established -> {
                val peer = outcome.peer
                if (paired == null) {
                    trustStore.pair(
                        AndroidPairedMac(
                            macID = peer.deviceId,
                            name = peer.deviceName,
                            publicKey = AndroidPairedMac.encodeKey(peer.publicKey),
                            host = service.host,
                            port = service.port,
                        ),
                    )
                } else {
                    trustStore.recordConnection(peer.deviceId, peer.deviceName, service.host, service.port)
                }
                connections.addAuthenticated(service.copy(name = peer.deviceName, macID = peer.deviceId), client)
                AndroidConnectResult.Connected
            }
            is AndroidV2CarrierClient.Outcome.Closed -> {
                // The Mac removed this phone, or it was reset and now has a different key.
                val pairingRemoved = paired != null &&
                    (outcome.reason == CoreCloseReason.NOT_PAIRED || outcome.reason == CoreCloseReason.HANDSHAKE_FAILED)
                if (pairingRemoved) trustStore.unpair(paired!!.macID)
                AndroidConnectResult.Rejected(outcome.message, pairingRemoved)
            }
        }
    }

    override suspend fun sendText(
        service: MacService,
        text: String,
        senderDisplayName: String,
        postPasteAction: CarrierPostPasteAction?,
    ): CarrierDeliveryReceipt? =
        connections.send(service, text, senderDisplayName.ifBlank { displayName }, postPasteAction)

    override fun closeConnection(service: MacService?) {
        if (service == null) connections.close() else connections.disconnect(service)
    }

    override fun close() {
        discovery.stop()
        closeConnection()
    }

    private val displayName: String
        get() = senderDisplayName.ifBlank { deviceName }

    private fun refreshDiscoveryPrecondition() {
        _discoveryPrecondition.value = AndroidNetworkDiscoveryPreconditions.current(appContext)
    }

    private fun identity(): CoreIdentity = CoreIdentity(
        staticPrivateKey = trustStore.identityKey(),
        deviceId = deviceID,
        deviceName = displayName,
        platform = CorePlatform.ANDROID,
        capabilities = listOf("send.text"),
    )

    /** Discovered Macs carry their ID; a manually entered address matches the last place a Mac answered. */
    private fun pairedMac(service: MacService): AndroidPairedMac? =
        trustStore.pairedMac(service.macID)
            ?: trustStore.pairedMacs().firstOrNull { service.macID == null && it.host == service.host && it.port == service.port }
}

fun manualService(host: String, port: String): MacService? {
    val cleanHost = host.trim()
    val cleanPort = port.toIntOrNull()
    if (cleanHost.isBlank() || cleanPort == null || cleanPort !in 1..65_535) {
        return null
    }
    return MacService(name = "手动输入的设备", host = cleanHost, port = cleanPort)
}

private const val defaultCarrierPort = 17642

fun localDeviceName(): String {
    val manufacturer = Build.MANUFACTURER.orEmpty()
    val model = Build.MODEL.orEmpty()
    val name = if (model.lowercase(Locale.getDefault()).startsWith(manufacturer.lowercase(Locale.getDefault()))) {
        model
    } else {
        "$manufacturer $model"
    }
    return name.trim().ifBlank { "Android" }
}
