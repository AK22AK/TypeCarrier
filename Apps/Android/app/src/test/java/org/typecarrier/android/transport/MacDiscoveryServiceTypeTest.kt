package org.typecarrier.android.transport

import org.junit.Assert.assertFalse
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
}
