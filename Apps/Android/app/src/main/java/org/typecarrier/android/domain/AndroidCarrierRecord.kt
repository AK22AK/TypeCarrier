package org.typecarrier.android.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AndroidCarrierRecord(
    val id: String,
    val payloadID: String? = null,
    val kind: AndroidRecordKind,
    val status: AndroidRecordStatus,
    val text: String,
    val createdAt: String,
    val updatedAt: String,
    val detail: String? = null,
    val sourceDeviceName: String? = null,
)

@Serializable
enum class AndroidRecordKind {
    @SerialName("draft")
    Draft,

    @SerialName("outgoing")
    Outgoing,

    @SerialName("incoming")
    Incoming,
}

@Serializable
enum class AndroidRecordStatus {
    @SerialName("draft")
    Draft,

    @SerialName("queued")
    Queued,

    @SerialName("sent")
    Sent,

    @SerialName("received")
    Received,

    @SerialName("pastePosted")
    PastePosted,

    @SerialName("pasteUnverified")
    PasteUnverified,

    @SerialName("pasteFailed")
    PasteFailed,

    @SerialName("failed")
    Failed,
}
