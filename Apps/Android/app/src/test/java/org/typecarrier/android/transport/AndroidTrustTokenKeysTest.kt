package org.typecarrier.android.transport

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AndroidTrustTokenKeysTest {
    @Test
    fun endpointTokenKeyIgnoresServiceNameChanges() {
        val manual = MacService(name = "手动 Mac", host = "10.0.0.2", port = 17641)
        val discovered = MacService(name = "Jiang MacBook Pro", host = "10.0.0.2", port = 17641)

        assertEquals(
            AndroidTrustTokenKeys.tokenKey(manual),
            AndroidTrustTokenKeys.tokenKey(discovered),
        )
    }

    @Test
    fun endpointTokenKeySeparatesDifferentEndpoints() {
        val first = MacService(name = "Mac", host = "10.0.0.2", port = 17641)
        val second = MacService(name = "Mac", host = "10.0.0.3", port = 17641)

        assertNotEquals(
            AndroidTrustTokenKeys.tokenKey(first),
            AndroidTrustTokenKeys.tokenKey(second),
        )
    }

    @Test
    fun macIdentityTokenKeySurvivesAddressChanges() {
        val first = MacService(name = "Mac", host = "10.0.0.2", port = 17641, macID = "mac-1")
        val second = MacService(name = "Mac", host = "10.0.0.3", port = 17641, macID = "mac-1")

        assertEquals(
            AndroidTrustTokenKeys.tokenKey(first),
            AndroidTrustTokenKeys.tokenKey(second),
        )
    }

    @Test
    fun legacyMacIdentityTokenKeyCanMatchAppSpecificService() {
        val discoveredDebug = MacService(
            name = "Mac",
            host = "10.0.0.2",
            port = 17641,
            macID = "mac-1",
            appBundleID = "ak22ak.typecarrier.mac.debug",
            appVariant = "debug",
        )

        assertEquals(
            "trust_token.mac.mac-1",
            AndroidTrustTokenKeys.legacyMacIdentityTokenKey(discoveredDebug),
        )
    }
}
