package org.typecarrier.android.transport

internal class MacDiscoveryResolutionQueue<T>(
    private val keyOf: (T) -> String,
) {
    private val pending = linkedMapOf<String, T>()
    private var active: T? = null

    fun enqueue(service: T): T? {
        if (active == null) {
            active = service
            return service
        }
        pending[keyOf(service)] = service
        return null
    }

    fun finishCurrent(): T? {
        active = null
        val next = pending.entries.firstOrNull() ?: return null
        pending.remove(next.key)
        active = next.value
        return next.value
    }

    fun removePending(key: String) {
        pending.remove(key)
    }

    fun clear() {
        active = null
        pending.clear()
    }
}
