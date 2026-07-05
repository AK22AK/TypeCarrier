package org.typecarrier.android.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object CarrierJson {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }

    fun encode(envelope: CarrierEnvelope): String = json.encodeToString(envelope)
    fun encode(handshake: AndroidBridgeHandshake): String = json.encodeToString(handshake)
    fun encode(request: AndroidPairingAssociationRequest): String = json.encodeToString(request)
    fun encode(response: AndroidPairingAssociationResponse): String = json.encodeToString(response)
    fun decodeEnvelope(value: String): CarrierEnvelope = json.decodeFromString(value)
    fun decodeHandshake(value: String): AndroidBridgeHandshake = json.decodeFromString(value)
    fun decodeBridgeResponse(value: String): AndroidBridgeResponse = json.decodeFromString(value)
    fun decodePairingAssociationRequest(value: String): AndroidPairingAssociationRequest = json.decodeFromString(value)
    fun decodePairingAssociationResponse(value: String): AndroidPairingAssociationResponse = json.decodeFromString(value)
}

@Serializable
data class CarrierDeviceIdentity(
    val displayName: String,
)

@Serializable
data class CarrierPayload(
    val id: String,
    val createdAt: String,
    val text: String,
    val postPasteAction: CarrierPostPasteAction? = null,
)

@Serializable
enum class CarrierPostPasteAction {
    @SerialName("pressReturn")
    PressReturn,
}

@Serializable
data class CarrierDeliveryReceipt(
    val payloadID: String,
    val receivedAt: String,
    val pasteStatus: PasteStatus,
    val detail: String? = null,
) {
    @Serializable
    enum class PasteStatus {
        @SerialName("received")
        Received,

        @SerialName("posted")
        Posted,

        @SerialName("unverifiedPosted")
        UnverifiedPosted,

        @SerialName("failed")
        Failed,
    }
}

@Serializable
data class CarrierEnvelope(
    val version: Int = 1,
    val kind: Kind,
    val payload: CarrierPayload? = null,
    val ackID: String? = null,
    val receipt: CarrierDeliveryReceipt? = null,
    val message: String? = null,
    val sender: CarrierDeviceIdentity? = null,
) {
    @Serializable
    enum class Kind {
        @SerialName("text")
        Text,

        @SerialName("ack")
        Ack,

        @SerialName("receipt")
        Receipt,

        @SerialName("error")
        Error,
    }

    companion object {
        fun text(payload: CarrierPayload, sender: CarrierDeviceIdentity? = null): CarrierEnvelope =
            CarrierEnvelope(kind = Kind.Text, payload = payload, sender = sender)
    }
}

@Serializable
data class AndroidBridgeHandshake(
    val version: Int = 1,
    val deviceID: String,
    val deviceName: String,
    val pairingCode: String? = null,
    val tokenProof: String? = null,
    val challenge: String? = null,
)

@Serializable
data class AndroidBridgeResponse(
    val status: AndroidBridgeResponseStatus,
    val message: String? = null,
    val trustToken: String? = null,
    val macID: String? = null,
    val macName: String? = null,
)

@Serializable
data class AndroidPairingAssociationRequest(
    val version: Int = 1,
    val macID: String,
    val macName: String,
    val pairingCode: String,
)

@Serializable
data class AndroidPairingAssociationResponse(
    val status: AndroidBridgeResponseStatus,
    val message: String,
    val deviceID: String? = null,
    val deviceName: String? = null,
    val trustToken: String? = null,
)

@Serializable
enum class AndroidBridgeResponseStatus {
    @SerialName("accepted")
    Accepted,

    @SerialName("busy")
    Busy,

    @SerialName("invalidPairing")
    InvalidPairing,

    @SerialName("rejected")
    Rejected,
}
