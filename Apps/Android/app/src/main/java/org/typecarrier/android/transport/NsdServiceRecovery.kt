package org.typecarrier.android.transport

class NsdServiceRecovery(
    private val retryDelayMillis: Long = 2_000,
) {
    private var pendingRetry = false

    fun failed(): Long {
        pendingRetry = true
        return retryDelayMillis
    }

    fun started() {
        pendingRetry = false
    }

    fun userRestarted() {
        pendingRetry = false
    }

    fun shouldRunScheduledRetry(): Boolean = pendingRetry
}
