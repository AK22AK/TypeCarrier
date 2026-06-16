package org.typecarrier.android.transport

internal class NsdResolveRetryPolicy(
    private val maxAttempts: Int = 3,
    private val retryDelayMillis: Long = 500,
) {
    private val attempts = linkedMapOf<String, Int>()

    fun failed(serviceName: String): Long? {
        val nextAttempt = (attempts[serviceName] ?: 0) + 1
        attempts[serviceName] = nextAttempt
        return retryDelayMillis.takeIf { nextAttempt < maxAttempts }
    }

    fun clear(serviceName: String) {
        attempts.remove(serviceName)
    }

    fun clearAll() {
        attempts.clear()
    }
}
