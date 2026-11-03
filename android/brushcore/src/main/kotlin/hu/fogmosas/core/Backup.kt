package hu.fogmosas.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

// Password-protected backup files, care instructions from the clinic, and the "too hard scrubbing"
// note. Same as ios/BrushCore/.../Backup.swift (tests: BackupTest.kt / BackupTests.swift).

/**
 * Backup file: "DHB1" || salt (16) || PBKDF2 iterations (4, big endian) || nonce (12) ||
 * AES-256-GCM ciphertext with tag. Key = PBKDF2-HMAC-SHA256(password, salt). AAD = "DHB1".
 */
object BackupCrypto {
    private val MAGIC = "DHB1".toByteArray()
    const val ITERATIONS = 120_000

    class WrongPassword : Exception("wrong password or damaged file")

    fun key(password: String, salt: ByteArray, iterations: Int): ByteArray =
        SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(PBEKeySpec(password.toCharArray(), salt, iterations, 256)).encoded

    fun seal(plain: ByteArray, password: String, iterations: Int = ITERATIONS, salt: ByteArray? = null, nonce: ByteArray? = null): ByteArray {
        val rnd = SecureRandom()
        val s = salt ?: ByteArray(16).also { rnd.nextBytes(it) }
        val n = nonce ?: ByteArray(12).also { rnd.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key(password, s, iterations), "AES"), GCMParameterSpec(128, n))
        c.updateAAD(MAGIC)
        return MAGIC + s + ByteBuffer.allocate(4).putInt(iterations).array() + n + c.doFinal(plain)
    }

    fun isBackup(data: ByteArray) = data.size > 36 + 16 && data.copyOfRange(0, 4).contentEquals(MAGIC)

    fun open(data: ByteArray, password: String): ByteArray {
        if (!isBackup(data)) throw WrongPassword()
        val salt = data.copyOfRange(4, 20)
        val iterations = ByteBuffer.wrap(data, 20, 4).int
        if (iterations !in 1_000..5_000_000) throw WrongPassword()
        val nonce = data.copyOfRange(24, 36)
        return try {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key(password, salt, iterations), "AES"), GCMParameterSpec(128, nonce))
            c.updateAAD(MAGIC)
            c.doFinal(data, 36, data.size - 36)
        } catch (e: Exception) {
            throw WrongPassword()
        }
    }

    /** At least 8 characters; null when fine, else what is wrong. */
    fun passwordProblem(p: String): String? = if (p.length < 8) tr("Legalább 8 karakteres jelszót adj meg.") else null
}

/** What a backup file carries: the app's data as JSON plus the complaint photos. */
@Serializable
data class BackupPayload(
    val format: String = "denthub-backup-1",
    /** "full" (everything) or "profile" (one profile for another family member's phone) */
    val kind: String = "full",
    val platform: String,
    val createdMs: Long,
    val data: String,
    /** photo file name -> base64 JPEG */
    val photos: Map<String, String> = emptyMap(),
)

private val backupJson = Json { ignoreUnknownKeys = true }

fun encodeBackup(p: BackupPayload, password: String): ByteArray =
    BackupCrypto.seal(backupJson.encodeToString(BackupPayload.serializer(), p).toByteArray(), password)

fun decodeBackup(file: ByteArray, password: String): BackupPayload =
    backupJson.decodeFromString(BackupPayload.serializer(), String(BackupCrypto.open(file, password), Charsets.UTF_8))

fun photoBase64(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
fun photoBytes(b64: String): ByteArray = Base64.getDecoder().decode(b64)

// ------------------------------------------------------------------ care instructions from the clinic

@Serializable
data class CareInstruction(val title: String, val times: List<String>, val days: Int, val clinic: String? = null)

/** `denthub://care?d=<base64url JSON>` from the clinic (QR / link): a care task to add after the treatment. */
fun parseCareLink(text: String): CareInstruction? {
    val t = text.trim()
    if (!t.startsWith("denthub://care?d=")) return null
    return runCatching {
        val bytes = Base64.getUrlDecoder().decode(t.removePrefix("denthub://care?d=").trimEnd('='))
        backupJson.decodeFromString(CareInstruction.serializer(), String(bytes, Charsets.UTF_8))
    }.getOrNull()?.takeIf { c ->
        c.title.isNotBlank() && c.days in 1..60 && c.times.isNotEmpty() && c.times.size <= 8 &&
            c.times.all { Regex("^([01]\\d|2[0-3]):[0-5]\\d$").matches(it) }
    }
}

fun careLinkCode(c: CareInstruction): String =
    "denthub://care?d=" + Base64.getUrlEncoder().withoutPadding().encodeToString(backupJson.encodeToString(CareInstruction.serializer(), c).toByteArray())

// ------------------------------------------------------------------ scrubbing force

/**
 * Manual brush: the scrubbing was clearly louder than this person's usual (from the same phone, so
 * placement mostly cancels out). Loud scrubbing usually means pressing too hard, which harms the gums.
 */
fun scrubNote(brushDb: Double?, history: List<Double>, manual: Boolean): String? {
    if (!manual || brushDb == null || history.size < 5) return null
    val usual = Stats.median(history.takeLast(15))
    return if (brushDb >= usual + 6.0)
        tr("Ma a szokásosnál jóval erősebben sikáltál. A túl erős súrolás sértheti az ínyt és a fogzománcot: finoman, kis körökkel moss.")
    else null
}
