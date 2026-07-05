package org.typecarrier.android.transport

import android.content.Context
import android.os.Build
import java.io.Closeable
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.typecarrier.android.protocol.AndroidBridgeResponse
import org.typecarrier.android.protocol.AndroidBridgeResponseStatus
import org.typecarrier.android.protocol.AndroidPairingCode
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierPostPasteAction

interface AndroidCarrierRepository : Closeable {
    val services: StateFlow<List<MacService>>
    val discoveryError: StateFlow<String?>
    val discoveryPrecondition: StateFlow<AndroidDiscoveryPrecondition>
    val deviceName: String
    val localPairingCode: String
    val trustedMacs: List<MacService>
    var manualHost: String
    var manualPort: String
    var senderDisplayName: String
    var launchesIntoInputMode: Boolean
    var enablesSendReturnGesture: Boolean

    fun startDiscovery()
    fun stopDiscovery()
    fun refreshDiscovery()
    fun hasSavedTrustToken(service: MacService): Boolean
    fun forgetTrustedMac(service: MacService)
    suspend fun connect(service: MacService, pairingCode: String?): AndroidBridgeResponse
    suspend fun sendText(
        text: String,
        senderDisplayName: String,
        postPasteAction: CarrierPostPasteAction? = null,
    ): CarrierDeliveryReceipt?
    fun closeConnection()
}

class AndroidCarrierRepositoryImpl(
    context: Context,
) : AndroidCarrierRepository {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("typecarrier", Context.MODE_PRIVATE)
    private val _services = MutableStateFlow(emptyList<MacService>())
    private val _discoveryError = MutableStateFlow<String?>(null)
    private val _discoveryPrecondition = MutableStateFlow(AndroidNetworkDiscoveryPreconditions.current(appContext))
    private var client: AndroidCarrierClient? = null
    private var manualHostValue = ""
    private var manualPortValue = defaultAndroidBridgePort.toString()
    private val discovery = MacDiscovery(
        context = appContext,
        onServicesChanged = { _services.value = it },
        onError = {
            errorMessage = it
            _discoveryError.value = it
        },
    )
    private val pairingReceiver = AndroidPairingReceiver(
        context = appContext,
        deviceID = { deviceID },
        deviceName = { displayName },
        localPairingCode = { localPairingCode },
        onAssociated = { associatedMac ->
            prefs.edit()
                .putString(AndroidTrustTokenKeys.tokenKey(associatedMac.macID), associatedMac.trustToken)
                .apply()
            rememberTrustedMac(
                MacService(
                    name = associatedMac.macName,
                    host = associatedMac.host,
                    port = defaultAndroidBridgePort,
                    macID = associatedMac.macID,
                ),
            )
        },
        onError = { errorMessage = it },
    )
    private val discoveryLifecycle = AndroidDiscoveryLifecycle(
        startMacDiscovery = discovery::start,
        stopMacDiscovery = discovery::stop,
        startPairingReceiver = pairingReceiver::start,
        stopPairingReceiver = pairingReceiver::close,
        disposePairingReceiver = pairingReceiver::dispose,
    )
    private var errorMessage: String? = null

    override val services: StateFlow<List<MacService>> = _services
    override val discoveryError: StateFlow<String?> = _discoveryError
    override val discoveryPrecondition: StateFlow<AndroidDiscoveryPrecondition> = _discoveryPrecondition

    override val deviceName: String = localDeviceName()

    override val localPairingCode: String
        get() = prefs.getString(localPairingCodePreference, null) ?: AndroidPairingCode.generate().also {
            prefs.edit().putString(localPairingCodePreference, it).apply()
        }

    override val trustedMacs: List<MacService>
        get() = readTrustedMacs()

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
        discoveryLifecycle.start()
    }

    override fun stopDiscovery() {
        discoveryLifecycle.stop()
    }

    override fun refreshDiscovery() {
        refreshDiscoveryPrecondition()
        discoveryLifecycle.refresh()
    }

    override fun hasSavedTrustToken(service: MacService): Boolean =
        savedTrustToken(service) != null

    override fun forgetTrustedMac(service: MacService) {
        val keysToRemove = linkedSetOf(
            AndroidTrustTokenKeys.endpointKey(service),
            AndroidTrustTokenKeys.endpointKey(service.host, service.port),
        )
        service.macID?.takeIf { it.isNotBlank() }?.let { keysToRemove.add(AndroidTrustTokenKeys.endpointKey(it)) }

        val trustedKeys = prefs.getStringSet(trustedMacKeysPreference, emptySet()).orEmpty().toMutableSet()
        trustedKeys.removeAll(keysToRemove)

        val editor = prefs.edit().putStringSet(trustedMacKeysPreference, trustedKeys)
        keysToRemove.forEach { key ->
            editor
                .remove("trusted_mac.$key.name")
                .remove("trusted_mac.$key.host")
                .remove("trusted_mac.$key.port")
                .remove("trusted_mac.$key.mac_id")
                .remove("trust_token.$key")
        }
        editor.remove(AndroidTrustTokenKeys.legacyTokenKey(service))
        editor.apply()
    }

    override suspend fun connect(service: MacService, pairingCode: String?): AndroidBridgeResponse {
        val nextClient = AndroidCarrierClient(service)
        val savedTrustToken = savedTrustToken(service)
        val code = pairingCode?.takeIf(AndroidPairingCode::isValid)
        val response = nextClient.pair(
            deviceID = deviceID,
            deviceName = displayName,
            pairingCode = code,
            trustToken = savedTrustToken.takeIf { code == null },
        )
        if (response.status == AndroidBridgeResponseStatus.Accepted) {
            client?.close()
            client = nextClient
            val trustedService = service.withMacIdentity(response.macID, response.macName)
            response.trustToken?.let {
                prefs.edit()
                    .putString(AndroidTrustTokenKeys.tokenKey(trustedService), it)
                    .putString(AndroidTrustTokenKeys.tokenKey(service), it)
                    .apply()
            }
            if (response.trustToken != null || savedTrustToken != null) {
                rememberTrustedMac(trustedService)
            }
        } else {
            nextClient.close()
        }
        return response
    }

    override suspend fun sendText(
        text: String,
        senderDisplayName: String,
        postPasteAction: CarrierPostPasteAction?,
    ): CarrierDeliveryReceipt? =
        client?.sendText(text, senderDisplayName.ifBlank { displayName }, postPasteAction) ?: error("尚未连接 Mac")

    override fun closeConnection() {
        client?.close()
        client = null
    }

    override fun close() {
        discoveryLifecycle.close()
        closeConnection()
    }

    private val displayName: String
        get() = senderDisplayName.ifBlank { deviceName }

    private fun refreshDiscoveryPrecondition() {
        _discoveryPrecondition.value = AndroidNetworkDiscoveryPreconditions.current(appContext)
    }

    private fun savedTrustToken(service: MacService): String? {
        val endpointToken = prefs.getString(AndroidTrustTokenKeys.tokenKey(service), null)
        if (endpointToken != null) {
            return endpointToken
        }

        val macIDToken = service.macID?.takeIf { it.isNotBlank() }
            ?.let { prefs.getString(AndroidTrustTokenKeys.tokenKey(it), null) }
        if (macIDToken != null) {
            prefs.edit().putString(AndroidTrustTokenKeys.tokenKey(service), macIDToken).apply()
            return macIDToken
        }

        val legacyMacIDToken = AndroidTrustTokenKeys.legacyMacIdentityTokenKey(service)
            ?.let { prefs.getString(it, null) }
        if (legacyMacIDToken != null) {
            prefs.edit().putString(AndroidTrustTokenKeys.tokenKey(service), legacyMacIDToken).apply()
            return legacyMacIDToken
        }

        val legacyToken = prefs.getString(AndroidTrustTokenKeys.legacyTokenKey(service), null)
        if (legacyToken != null) {
            prefs.edit().putString(AndroidTrustTokenKeys.tokenKey(service), legacyToken).apply()
        }
        return legacyToken
    }

    private fun rememberTrustedMac(service: MacService) {
        val key = AndroidTrustTokenKeys.endpointKey(service)
        val existingKeys = prefs.getStringSet(trustedMacKeysPreference, emptySet()).orEmpty().toMutableSet()
        existingKeys.add(key)
        prefs.edit()
            .putStringSet(trustedMacKeysPreference, existingKeys)
            .putString("trusted_mac.$key.name", service.name)
            .putString("trusted_mac.$key.host", service.host)
            .putInt("trusted_mac.$key.port", service.port)
            .putString("trusted_mac.$key.mac_id", service.macID)
            .putString("trusted_mac.$key.app_bundle_id", service.appBundleID)
            .putString("trusted_mac.$key.app_variant", service.appVariant)
            .apply()
    }

    private fun readTrustedMacs(): List<MacService> =
        prefs.getStringSet(trustedMacKeysPreference, emptySet()).orEmpty()
            .mapNotNull { key ->
                val host = prefs.getString("trusted_mac.$key.host", null) ?: return@mapNotNull null
                val port = prefs.getInt("trusted_mac.$key.port", -1).takeIf { it in 1..65_535 } ?: return@mapNotNull null
                val name = prefs.getString("trusted_mac.$key.name", null)?.takeIf { it.isNotBlank() } ?: "已配对 Mac"
                val macID = prefs.getString("trusted_mac.$key.mac_id", null)?.takeIf { it.isNotBlank() }
                val appBundleID = prefs.getString("trusted_mac.$key.app_bundle_id", null)?.takeIf { it.isNotBlank() }
                val appVariant = prefs.getString("trusted_mac.$key.app_variant", null)?.takeIf { it.isNotBlank() }
                MacService(
                    name = name,
                    host = host,
                    port = port,
                    macID = macID,
                    appBundleID = appBundleID,
                    appVariant = appVariant,
                )
            }
            .sortedBy { it.name }

    private companion object {
        const val trustedMacKeysPreference = "trusted_mac_keys"
        const val localPairingCodePreference = "local_pairing_code"
    }
}

internal object AndroidTrustTokenKeys {
    fun endpointKey(service: MacService): String =
        service.macID?.takeIf { it.isNotBlank() }?.let { macID ->
            buildList {
                add("mac.${macID.trim()}")
                service.appBundleID?.trim()?.takeIf { it.isNotEmpty() }?.let { add("bundle.$it") }
                service.appVariant?.trim()?.takeIf { it.isNotEmpty() }?.let { add("variant.$it") }
            }.joinToString("|")
        }
            ?: endpointKey(service.host, service.port)

    fun endpointKey(host: String, port: Int): String = "endpoint.${host.trim().lowercase(Locale.ROOT)}:$port"

    fun endpointKey(macID: String): String = "mac.${macID.trim()}"

    fun tokenKey(service: MacService): String = "trust_token.${endpointKey(service)}"

    fun legacyTokenKey(service: MacService): String = "trust_token.${service.name}"

    fun legacyMacIdentityTokenKey(service: MacService): String? =
        service.macID?.takeIf { it.isNotBlank() }?.let { tokenKey(it) }

    fun tokenKey(macID: String): String = "trust_token.mac.${macID.trim()}"
}

private fun MacService.withMacIdentity(macID: String?, macName: String?): MacService =
    copy(
        name = macName?.takeIf { it.isNotBlank() } ?: name,
        macID = macID?.takeIf { it.isNotBlank() } ?: this.macID,
    )

fun manualService(host: String, port: String): MacService? {
    val cleanHost = host.trim()
    val cleanPort = port.toIntOrNull()
    if (cleanHost.isBlank() || cleanPort == null || cleanPort !in 1..65_535) {
        return null
    }
    return MacService(name = "手动 Mac", host = cleanHost, port = cleanPort)
}

private const val defaultAndroidBridgePort = 17641

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
