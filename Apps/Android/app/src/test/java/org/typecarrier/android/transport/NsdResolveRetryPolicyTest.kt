package org.typecarrier.android.transport

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NsdResolveRetryPolicyTest {
    @Test
    fun failedResolveSchedulesBoundedRetries() {
        val policy = NsdResolveRetryPolicy(maxAttempts = 3, retryDelayMillis = 250)

        assertEquals(250L, policy.failed("Mac"))
        assertEquals(250L, policy.failed("Mac"))
        assertNull(policy.failed("Mac"))
    }

    @Test
    fun resolvedOrLostServiceClearsRetryBudget() {
        val policy = NsdResolveRetryPolicy(maxAttempts = 2, retryDelayMillis = 250)

        assertEquals(250L, policy.failed("Mac"))
        assertNull(policy.failed("Mac"))

        policy.clear("Mac")

        assertEquals(250L, policy.failed("Mac"))
    }
}
