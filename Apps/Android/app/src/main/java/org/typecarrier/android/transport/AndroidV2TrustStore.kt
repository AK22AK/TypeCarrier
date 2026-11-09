package org.typecarrier.android.transport

import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import uniffi.carrier_core.generateStaticPrivateKey

/** A Mac this phone paired with over protocol v2. The public key is what later reconnects verify. */
@Serializable
data class AndroidPairedMac(
    val macID: String,
    val name: String,
    val publicKey: String,
    val host: String? = null,
    val port: Int? = null,
) {
    val publicKeyBytes: ByteArray get() = Base64.getDecoder().decode(publicKey)

    companion object {
        fun encodeKey(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
    }
}

/** Encrypts small secrets at rest. The app uses the Android Keystore; tests use [PlainSecretSealer]. */
interface SecretSealer {
    fun seal(plain: ByteArray): ByteArray
    fun open(sealed: ByteArray): ByteArray
}

/** AES-GCM with a non-exportable key held by the Android Keystore. */
class KeystoreSecretSealer(private val alias: String = "typecarrier.v2.secrets") : SecretSealer {
    private val key: SecretKey by lazy {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
            generateKey()
        }
    }

    override fun seal(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }
        return cipher.iv + cipher.doFinal(plain)
    }

    override fun open(sealed: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, IV_SIZE))
        }
        return cipher.doFinal(sealed, IV_SIZE, sealed.size - IV_SIZE)
    }

    private companion object {
        const val IV_SIZE = 12
    }
}

class PlainSecretSealer : SecretSealer {
    override fun seal(plain: ByteArray): ByteArray = plain
    override fun open(sealed: ByteArray): ByteArray = sealed
}

/**
 * This phone's long-term protocol key and the Macs it paired with, sealed before they reach
 * SharedPreferences. Losing the identity key unpairs every Mac.
 */
class AndroidV2TrustStore(
    private val prefs: SharedPreferences,
    private val sealer: SecretSealer,
    private val generateKey: () -> ByteArray = { generateStaticPrivateKey() },
) {
    private val json = Json { ignoreUnknownKeys = true }
    @Volatile private var cachedIdentity: ByteArray? = null
    @Volatile private var cachedMacs: List<AndroidPairedMac>? = null

    @Synchronized
    fun identityKey(): ByteArray {
        cachedIdentity?.let { return it }
        val stored = readSealed(IDENTITY_KEY)
        val key = if (stored != null && stored.size == 32) stored else generateKey().also { writeSealed(IDENTITY_KEY, it) }
        cachedIdentity = key
        return key
    }

    @Synchronized
    fun pairedMacs(): List<AndroidPairedMac> {
        cachedMacs?.let { return it }
        val macs = readSealed(PAIRED_MACS_KEY)
            ?.let { runCatching { json.decodeFromString<List<AndroidPairedMac>>(it.decodeToString()) }.getOrNull() }
            .orEmpty()
        cachedMacs = macs
        return macs
    }

    fun pairedMac(macID: String?): AndroidPairedMac? = macID?.let { id -> pairedMacs().firstOrNull { it.macID == id } }

    /** Adds or replaces the pairing for this Mac; a re-pair carries a new key, so the old one stops working. */
    @Synchronized
    fun pair(mac: AndroidPairedMac) {
        save(pairedMacs().filter { it.macID != mac.macID } + mac)
    }

    @Synchronized
    fun unpair(macID: String) {
        save(pairedMacs().filter { it.macID != macID })
    }

    /** Remembers where a paired Mac answered last, and its current name. Writes only on change. */
    @Synchronized
    fun recordConnection(macID: String, name: String, host: String, port: Int) {
        val macs = pairedMacs()
        val existing = macs.firstOrNull { it.macID == macID } ?: return
        val updated = existing.copy(name = name, host = host, port = port)
        if (updated != existing) save(macs.map { if (it.macID == macID) updated else it })
    }

    private fun save(macs: List<AndroidPairedMac>) {
        writeSealed(PAIRED_MACS_KEY, json.encodeToString(macs).encodeToByteArray())
        cachedMacs = macs
    }

    private fun readSealed(key: String): ByteArray? {
        val encoded = prefs.getString(key, null) ?: return null
        return runCatching { sealer.open(Base64.getDecoder().decode(encoded)) }.getOrNull()
    }

    private fun writeSealed(key: String, value: ByteArray) {
        // commit(): a pairing must be on disk before the app tells the person it succeeded.
        check(prefs.edit().putString(key, Base64.getEncoder().encodeToString(sealer.seal(value))).commit()) {
            "无法保存配对信息"
        }
    }

    private companion object {
        const val IDENTITY_KEY = "v2.identity_key"
        const val PAIRED_MACS_KEY = "v2.paired_macs"
    }
}
