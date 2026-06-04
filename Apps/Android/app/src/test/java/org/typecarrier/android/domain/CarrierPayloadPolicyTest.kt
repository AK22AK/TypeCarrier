package org.typecarrier.android.domain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CarrierPayloadPolicyTest {
    @Test
    fun blankTextCannotSend() {
        assertFalse(CarrierPayloadPolicy.canSend(""))
        assertFalse(CarrierPayloadPolicy.canSend("   \n\t  "))
    }

    @Test
    fun visibleTextCanSend() {
        assertTrue(CarrierPayloadPolicy.canSend("hello"))
        assertTrue(CarrierPayloadPolicy.canSend("中文"))
        assertTrue(CarrierPayloadPolicy.canSend("first line\nsecond line"))
        assertTrue(CarrierPayloadPolicy.canSend("🙂"))
    }
}
