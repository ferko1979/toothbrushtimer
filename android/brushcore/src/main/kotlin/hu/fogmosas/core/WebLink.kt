package hu.fogmosas.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.math.BigInteger
import java.net.URI
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// "View on the web" link: the web page shows a QR code with a one-time session id
// and its ECDH P-256 public key; the phone encrypts a statistics snapshot to that
// key and posts it to the relay, which only ever sees ciphertext. Spec: web/PROTOCOL.md.

@Serializable data class WebGoals(val perDay: Int, val targetS: Double)

@Serializable data class WebDay(
    val d: String, val n: Int, val avgS: Double, val goalHits: Int, val tapOff: Int,
    val floss: Boolean, val mouthwash: Boolean, val interdental: Boolean, val tongue: Boolean,
    val sens: Int, val bleed: Boolean,
)

@Serializable data class WebSection(val title: String, val lines: List<String>)
@Serializable data class WebInsight(val text: String, val alert: Boolean)
@Serializable data class WebReport(val title: String, val subtitle: String, val sections: List<WebSection>)

@Serializable data class WebProfile(
    val name: String, val child: Boolean, val avatar: String, val goals: WebGoals, val streak: Int, val stickers: Int,
    val orthodontic: Boolean, val days: List<WebDay>, val insights: List<WebInsight>, val report: WebReport,
)

@Serializable data class WebSnapshot(val v: Int = 1, val generated: String, val locale: String, val profiles: List<WebProfile>)

object WebLink {
    const val INFO = "fogmosas-web-v1"
    const val SNAPSHOT_DAYS = 90
    private val SID = Regex("^[A-Za-z0-9_-]{22}$")
    private val b64 = Base64.getUrlEncoder().withoutPadding()
    private val unb64 = Base64.getUrlDecoder()
    private val json = Json { encodeDefaults = true }

    fun b64(bytes: ByteArray): String = b64.encodeToString(bytes)
    fun unb64(s: String): ByteArray = unb64.decode(s)

    data class Pairing(val base: String, val host: String, val sid: String, val webPublicKey: ByteArray) {
        val uploadUrl get() = "$base/api/relay/$sid"
    }

    /** Parses the QR text https://host[:port][/prefix]/l#<sid>.<publicKey>; null if it is not ours. */
    fun parse(qr: String): Pairing? {
        val uri = try { URI(qr.trim()) } catch (e: Exception) { return null }
        val host = uri.host ?: return null
        val local = host == "localhost" || host == "127.0.0.1" || host == "10.0.2.2"
        if (uri.scheme != "https" && !(uri.scheme == "http" && local)) return null
        val path = uri.rawPath ?: return null
        if (!path.endsWith("/l")) return null
        val frag = uri.rawFragment ?: return null
        val parts = frag.split('.')
        if (parts.size != 2 || !SID.matches(parts[0])) return null
        val key = try { unb64(parts[1]) } catch (e: Exception) { return null }
        if (key.size != 65 || key[0] != 4.toByte()) return null
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return Pairing("${uri.scheme}://$host$port${path.removeSuffix("/l")}", host, parts[0], key)
    }

    private val params: ECParameterSpec by lazy {
        AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }.getParameterSpec(ECParameterSpec::class.java)
    }

    private fun publicKey(raw: ByteArray): ECPublicKey {
        require(raw.size == 65 && raw[0] == 4.toByte()) { "uncompressed P-256 point expected" }
        val x = BigInteger(1, raw.copyOfRange(1, 33))
        val y = BigInteger(1, raw.copyOfRange(33, 65))
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(x, y), params)) as ECPublicKey
    }

    fun rawPublicKey(k: ECPublicKey): ByteArray {
        fun fixed(b: BigInteger): ByteArray {
            val a = b.toByteArray()
            return when {
                a.size == 32 -> a
                a.size > 32 -> a.copyOfRange(a.size - 32, a.size)
                else -> ByteArray(32 - a.size) + a
            }
        }
        return byteArrayOf(4) + fixed(k.w.affineX) + fixed(k.w.affineY)
    }

    /** For test vectors: a key pair from its raw private scalar and raw public point. */
    fun keyPair(privateRaw: ByteArray, publicRaw: ByteArray): KeyPair {
        val priv = KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, privateRaw), params))
        return KeyPair(publicKey(publicRaw), priv)
    }

    fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, len: Int = 32): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(salt, "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        var t = ByteArray(0)
        val out = java.io.ByteArrayOutputStream()
        var i = 1
        while (out.size() < len) {
            mac.update(t); mac.update(info); mac.update(i.toByte())
            t = mac.doFinal()
            out.write(t)
            i++
        }
        return out.toByteArray().copyOf(len)
    }

    /** Envelope: phone public key (65) || nonce (12) || AES-256-GCM ciphertext with tag. AAD = session id. */
    fun seal(webPublicKey: ByteArray, sid: String, plaintext: ByteArray, ephemeral: KeyPair? = null, nonce: ByteArray? = null): ByteArray {
        val kp = ephemeral ?: KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(kp.private)
        ka.doPhase(publicKey(webPublicKey), true)
        val key = hkdf(ka.generateSecret(), sid.toByteArray(), INFO.toByteArray())
        val iv = nonce ?: ByteArray(12).also { SecureRandom().nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        c.updateAAD(sid.toByteArray())
        return rawPublicKey(kp.public as ECPublicKey) + iv + c.doFinal(plaintext)
    }

    fun snapshotJson(s: WebSnapshot): String = json.encodeToString(WebSnapshot.serializer(), s)

    fun profileSnapshot(p: Profile, records: List<BrushRecord>, care: List<CareEntry>, today: LocalDate, zone: ZoneId,
                        flossTracked: Boolean = true): WebProfile {
        val coach = Coach(zone)
        val start = today.minusDays(SNAPSHOT_DAYS - 1L)
        val byDay = records.groupBy { coach.day(it) }
        val careByDay = careDays(care, zone)
        val days = (byDay.keys + careByDay.keys).filter { !it.isBefore(start) && !it.isAfter(today) }.toSortedSet().map { d ->
            val rs = byDay[d].orEmpty()
            val c = careByDay[d]
            WebDay(d.toString(), rs.size, if (rs.isEmpty()) 0.0 else Math.round(rs.map { it.durationS }.average() * 10) / 10.0,
                rs.count { it.durationS >= p.goals.targetS }, rs.count { it.tapOff },
                c?.floss ?: false, c?.mouthwash ?: false, c?.interdental ?: false, c?.tongue ?: false, c?.sensitivity ?: 0, c?.bleeding ?: false)
        }
        val rep = dentistReport(p, records, care, today, 30, zone)
        return WebProfile(p.name, p.child, p.avatarEmoji, WebGoals(p.goals.perDay, p.goals.targetS), coach.perfectStreak(records, p.goals, today),
            stickers(records, p.goals, zone).first, p.orthodontic, days, careInsights(care, today, zone, flossTracked).map { WebInsight(it.text, it.alert) },
            WebReport(rep.title, rep.subtitle, rep.sections.map { WebSection(it.title, it.lines) }))
    }

    fun snapshot(profiles: List<WebProfile>, now: Instant, locale: String) = WebSnapshot(generated = now.toString(), locale = locale, profiles = profiles)
}
