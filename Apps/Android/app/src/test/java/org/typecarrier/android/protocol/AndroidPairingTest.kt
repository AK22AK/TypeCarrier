package org.typecarrier.android.protocol

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidPairingTest {
    @Test
    fun pairingCodeAllowsExactlySixDigits() {
        assertTrue(AndroidPairingCode.isValid("123456"))

        assertFalse(AndroidPairingCode.isValid("12345"))
        assertFalse(AndroidPairingCode.isValid("1234567"))
        assertFalse(AndroidPairingCode.isValid("12345a"))
        assertFalse(AndroidPairingCode.isValid(" 123456"))
    }

    @Test
    fun trustTokenProofVerifiesChallenge() {
        val token = AndroidTrustToken("secret-token")
        val proof = token.proof("challenge-a")

        assertTrue(token.verify("challenge-a", proof))
        assertFalse(token.verify("challenge-b", proof))
    }

    @Test
    fun generatedTrustTokensAreUrlSafeAndUnique() {
        val first = AndroidTrustToken.generate()
        val second = AndroidTrustToken.generate()

        assertNotEquals(first.rawValue, second.rawValue)
        assertTrue(first.rawValue.matches(Regex("[A-Za-z0-9_-]+")))
        assertFalse(first.rawValue.contains("="))
    }
}
