package org.typecarrier.android.transport

internal object MacDiscoveryServiceType {
    const val value = "_typecarrier._tcp."

    fun matches(serviceType: String): Boolean =
        serviceType.normalizedDnsSdType() == value.normalizedDnsSdType()

    private fun String.normalizedDnsSdType(): String =
        trim().trimEnd('.').lowercase()
}
