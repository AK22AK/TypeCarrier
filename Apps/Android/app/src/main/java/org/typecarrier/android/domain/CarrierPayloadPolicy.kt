package org.typecarrier.android.domain

object CarrierPayloadPolicy {
    fun canSend(text: String): Boolean = text.trim().isNotEmpty()
}
