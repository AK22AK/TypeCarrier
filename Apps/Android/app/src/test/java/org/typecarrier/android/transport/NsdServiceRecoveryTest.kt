package org.typecarrier.android.transport

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NsdServiceRecoveryTest {
    @Test
    fun failureSchedulesRetry() {
        val recovery = NsdServiceRecovery(retryDelayMillis = 1_500)

        val delay = recovery.failed()

        assertEquals(1_500, delay)
        assertTrue(recovery.shouldRunScheduledRetry())
    }

    @Test
    fun successfulStartClearsPendingRetry() {
        val recovery = NsdServiceRecovery()
        recovery.failed()

        recovery.started()

        assertFalse(recovery.shouldRunScheduledRetry())
    }

    @Test
    fun userRestartClearsPendingRetry() {
        val recovery = NsdServiceRecovery()
        recovery.failed()

        recovery.userRestarted()

        assertFalse(recovery.shouldRunScheduledRetry())
    }
}
