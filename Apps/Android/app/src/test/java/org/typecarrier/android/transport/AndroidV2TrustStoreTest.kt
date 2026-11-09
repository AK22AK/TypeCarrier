package org.typecarrier.android.transport

import android.content.SharedPreferences
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AndroidV2TrustStoreTest {
    private val prefs = MemoryPreferences()

    @Test
    fun identityKeyIsCreatedOnceAndSurvivesReload() {
        var generated = 0
        val generate = { generated += 1; ByteArray(32) { it.toByte() } }
        val first = AndroidV2TrustStore(prefs, PlainSecretSealer(), generate).identityKey()
        val second = AndroidV2TrustStore(prefs, PlainSecretSealer(), generate).identityKey()

        assertArrayEquals(first, second)
        assertEquals(1, generated)
    }

    @Test
    fun repairingReplacesTheOldKeyAndUnpairForgetsTheMac() {
        val store = AndroidV2TrustStore(prefs, PlainSecretSealer()) { ByteArray(32) }
        store.pair(AndroidPairedMac("mac-1", "Mac", AndroidPairedMac.encodeKey(ByteArray(32) { 1 })))
        store.pair(AndroidPairedMac("mac-1", "Mac", AndroidPairedMac.encodeKey(ByteArray(32) { 2 }), host = "10.0.0.2", port = 17642))

        val reloaded = AndroidV2TrustStore(prefs, PlainSecretSealer()) { ByteArray(32) }
        assertEquals(1, reloaded.pairedMacs().size)
        assertArrayEquals(ByteArray(32) { 2 }, reloaded.pairedMac("mac-1")!!.publicKeyBytes)

        reloaded.unpair("mac-1")
        assertNull(AndroidV2TrustStore(prefs, PlainSecretSealer()) { ByteArray(32) }.pairedMac("mac-1"))
    }

    @Test
    fun recordConnectionUpdatesNameAndAddressOnlyWhenTheyChange() {
        val store = AndroidV2TrustStore(prefs, PlainSecretSealer()) { ByteArray(32) }
        store.pair(AndroidPairedMac("mac-1", "Mac", AndroidPairedMac.encodeKey(ByteArray(32)), "10.0.0.2", 17642))
        val writesAfterPairing = prefs.writes

        store.recordConnection("mac-1", "Mac", "10.0.0.2", 17642)
        assertEquals(writesAfterPairing, prefs.writes)

        store.recordConnection("mac-1", "Studio Mac", "10.0.0.9", 17642)
        assertEquals(writesAfterPairing + 1, prefs.writes)
        assertEquals("10.0.0.9", store.pairedMac("mac-1")!!.host)
    }
}

/** Just enough SharedPreferences for the trust store, which only reads and writes strings. */
private class MemoryPreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any?>()
    var writes = 0

    override fun getAll(): MutableMap<String, *> = values
    override fun getString(key: String, defValue: String?): String? = values[key] as? String ?: defValue
    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? = defValues
    override fun getInt(key: String, defValue: Int): Int = defValue
    override fun getLong(key: String, defValue: Long): Long = defValue
    override fun getFloat(key: String, defValue: Float): Float = defValue
    override fun getBoolean(key: String, defValue: Boolean): Boolean = defValue
    override fun contains(key: String): Boolean = key in values
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        override fun putString(key: String, value: String?) = apply { pending[key] = value }
        override fun putStringSet(key: String, values: MutableSet<String>?) = apply { pending[key] = values }
        override fun putInt(key: String, value: Int) = apply { pending[key] = value }
        override fun putLong(key: String, value: Long) = apply { pending[key] = value }
        override fun putFloat(key: String, value: Float) = apply { pending[key] = value }
        override fun putBoolean(key: String, value: Boolean) = apply { pending[key] = value }
        override fun remove(key: String) = apply { pending[key] = null }
        override fun clear() = apply { values.keys.forEach { pending[it] = null } }
        override fun commit(): Boolean {
            apply()
            return true
        }
        override fun apply() {
            writes += 1
            pending.forEach { (key, value) -> if (value == null) values.remove(key) else values[key] = value }
            pending.clear()
        }
    }
}
