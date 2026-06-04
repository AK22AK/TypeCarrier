package org.typecarrier.android.protocol

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object AndroidPairingCode {
    fun isValid(value: String): Boolean = value.matches(Regex("\\d{6}"))

    fun generate(randomNumber: (IntRange) -> Int = { secureRandom.nextInt(1_000_000) }): String =
        randomNumber(0..999_999).toString().padStart(6, '0')

    private val secureRandom = SecureRandom()
}

data class AndroidTrustToken(val rawValue: String) {
    fun proof(challenge: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(rawValue.encodeToByteArray(), "HmacSHA256"))
        return base64Url(mac.doFinal(challenge.encodeToByteArray()))
    }

    fun verify(challenge: String, proof: String): Boolean = proof(challenge) == proof

    companion object {
        private val secureRandom = SecureRandom()

        fun generate(): AndroidTrustToken {
            val bytes = ByteArray(32)
            secureRandom.nextBytes(bytes)
            return AndroidTrustToken(base64Url(bytes))
        }
    }
}

private fun base64Url(bytes: ByteArray): String =
    Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
