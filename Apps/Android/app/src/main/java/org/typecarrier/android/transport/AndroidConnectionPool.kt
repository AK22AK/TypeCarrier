package org.typecarrier.android.transport

import java.io.Closeable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.typecarrier.android.protocol.CarrierDeliveryReceipt
import org.typecarrier.android.protocol.CarrierPostPasteAction

interface CarrierConnection : Closeable {
    val isOpen: Boolean get() = true
    suspend fun sendText(text: String, deviceName: String, postPasteAction: CarrierPostPasteAction? = null): CarrierDeliveryReceipt?
}

/** Each authenticated receiver owns a separate connection. Selection never broadcasts or falls back. */
class AndroidConnectionPool : Closeable {
    private data class Entry(val service: MacService, val connection: CarrierConnection)
    private val entries = linkedMapOf<String, Entry>()
    private val _connectedServices = MutableStateFlow<List<MacService>>(emptyList())
    val connectedServices: StateFlow<List<MacService>> = _connectedServices

    @Synchronized
    fun addAuthenticated(service: MacService, connection: CarrierConnection) {
        check(connection.isOpen) { "Mac 连接已关闭" }
        val old = entries.put(service.id, Entry(service, connection))
        publish()
        old?.connection?.close()
    }

    suspend fun send(service: MacService, text: String, deviceName: String, action: CarrierPostPasteAction?): CarrierDeliveryReceipt? {
        val entry = synchronized(this) { entry(service) } ?: error("所选 Mac 已离线，请重新连接或选择发送目标")
        return try {
            entry.connection.sendText(text, deviceName, action)
        } catch (error: Exception) {
            remove(entry.connection)
            entry.connection.close()
            throw error
        }
    }

    @Synchronized
    fun disconnect(service: MacService) {
        val entry = entry(service) ?: return
        entries.remove(entry.service.id)
        publish()
        entry.connection.close()
    }

    @Synchronized
    fun remove(connection: CarrierConnection) {
        entries.entries.removeAll { it.value.connection === connection }
        publish()
    }

    @Synchronized
    override fun close() {
        val previous = entries.values.toList()
        entries.clear()
        publish()
        previous.forEach { it.connection.close() }
    }

    private fun entry(service: MacService): Entry? = entries[service.id]
        ?: entries.values.firstOrNull { service.macID == null && it.service.host == service.host && it.service.port == service.port }

    private fun publish() {
        _connectedServices.value = entries.values.map { it.service }
    }
}
