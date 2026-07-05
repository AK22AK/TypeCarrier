package org.typecarrier.android.transport

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MacDiscoveryServiceTypeTest {
    @Test
    fun matchesTypecarrierServiceWithOrWithoutTrailingDot() {
        assertTrue(MacDiscoveryServiceType.matches("_typecarrier._tcp."))
        assertTrue(MacDiscoveryServiceType.matches("_typecarrier._tcp"))
        assertTrue(MacDiscoveryServiceType.matches("_TYPECARRIER._TCP."))
        assertFalse(MacDiscoveryServiceType.matches("_tcpair._tcp."))
    }

    @Test
    fun macServiceIdentityDistinguishesDebugAndReleaseVariantsForSameMacID() {
        val release = MacService(
            name = "MacBook Pro",
            host = "10.0.0.2",
            port = 17641,
            macID = "mac-1",
            appBundleID = "ak22ak.typecarrier.mac",
            appVariant = "release",
        )
        val debug = MacService(
            name = "MacBook Pro",
            host = "10.0.0.3",
            port = 17641,
            macID = "mac-1",
            appBundleID = "ak22ak.typecarrier.mac.debug",
            appVariant = "debug",
        )

        assertNotEquals(release.id, debug.id)
        assertEquals("macID=mac-1|appBundleID=ak22ak.typecarrier.mac|appVariant=release", release.id)
        assertEquals("macID=mac-1|appBundleID=ak22ak.typecarrier.mac.debug|appVariant=debug", debug.id)
    }
}
