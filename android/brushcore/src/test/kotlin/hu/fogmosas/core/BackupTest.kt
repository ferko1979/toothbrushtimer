package hu.fogmosas.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Mirrored in BackupTests.swift; the vector was made with Node's crypto (PBKDF2 + AES-GCM). */
class BackupTest {
    private val vector = "44484231000102030405060708090a0b0c0d0e0f000003e86465666768696a6b6c6d6e6f8d9c10eec0d74ea3083aa9e843b8cfa94dedff4ea5a6bfe7b6f5c3ac6c10"
    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

    @Test
    fun knownVector() {
        val salt = ByteArray(16) { it.toByte() }
        val nonce = ByteArray(12) { (100 + it).toByte() }
        val sealed = BackupCrypto.seal("hello fogmosas".toByteArray(), "jelszo123", 1000, salt, nonce)
        assertContentEquals(hex(vector), sealed)
        assertEquals("hello fogmosas", String(BackupCrypto.open(hex(vector), "jelszo123")))
        assertFailsWith<BackupCrypto.WrongPassword> { BackupCrypto.open(hex(vector), "rossz-jelszo") }
        val damaged = hex(vector).also { it[40] = (it[40].toInt() xor 1).toByte() }
        assertFailsWith<BackupCrypto.WrongPassword> { BackupCrypto.open(damaged, "jelszo123") }
    }

    @Test
    fun payloadRoundTrip() {
        val p = BackupPayload(platform = "android", createdMs = 1, data = "{\"a\":1}", photos = mapOf("x.jpg" to photoBase64(byteArrayOf(1, 2, 3))))
        val file = encodeBackup(p, "hosszu-jelszo")
        assertTrue(BackupCrypto.isBackup(file))
        val back = decodeBackup(file, "hosszu-jelszo")
        assertEquals(p, back)
        assertContentEquals(byteArrayOf(1, 2, 3), photoBytes(back.photos.getValue("x.jpg")))
        assertNotNull(BackupCrypto.passwordProblem("rovid"))
        assertNull(BackupCrypto.passwordProblem("eleg-hosszu"))
    }

    @Test
    fun careLinkAndScrub() {
        val c = CareInstruction("Szájöblítés klórhexidinnel", listOf("08:00", "20:00"), 7, "Mosoly Fogászat")
        assertEquals(c, parseCareLink(careLinkCode(c)))
        assertNull(parseCareLink(careLinkCode(c.copy(times = listOf("25:00")))))
        assertNull(parseCareLink(careLinkCode(c.copy(days = 0))))
        assertNull(parseCareLink("denthub://link?d=abc"))
        val hist = listOf(-60.0, -61.0, -59.0, -60.5, -60.0)
        assertNotNull(scrubNote(-52.0, hist, manual = true))
        assertNull(scrubNote(-58.0, hist, manual = true))
        assertNull(scrubNote(-52.0, hist, manual = false))
        assertNull(scrubNote(-52.0, hist.take(3), manual = true))
    }
}
