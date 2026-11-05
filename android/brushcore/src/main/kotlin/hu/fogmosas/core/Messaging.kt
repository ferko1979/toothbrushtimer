package hu.fogmosas.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Base64
import java.util.UUID

// Messenger with the linked clinic and appointments (request -> offer -> confirmed -> calendar and
// reminders). Same as ios/BrushCore/.../Messaging.swift (tests: MessagingTest.kt / MessagingTests.swift).
// Delivery through DentHub needs its server (docs/DENTHUB-API.md); until then app messages wait
// ("queued") and e-mail goes out right away, and every e-mail is also kept as an internal message.

/** An appointment at the clinic. */
@Serializable
data class Appointment(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    /** Local start time, "2026-11-10T10:30". */
    val start: String,
    val durationMin: Int = 30,
    val reason: String = "checkup",
    val clinicName: String? = null,
    val doctor: String? = null,
    val address: String? = null,
    val note: String = "",
    /** requested / offered / confirmed / cancelled */
    val status: String = "confirmed",
    val calendarAdded: Boolean = false,
    /** Reminders, minutes before the start. */
    val remindersMin: List<Int> = listOf(24 * 60, 120),
)

object Recipients {
    val all get() = listOf("doctor" to tr("Orvos"), "admin" to tr("Recepció / asszisztens"))
    fun title(id: String) = all.firstOrNull { it.first == id }?.second ?: id
}

object Messaging {
    private val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
    private val json = Json { ignoreUnknownKeys = true }

    fun startOf(a: Appointment): LocalDateTime? = runCatching { LocalDateTime.parse(a.start, stamp) }.getOrNull()
    fun format(t: LocalDateTime): String = t.format(stamp)

    /** Conversation with the clinic for one profile, oldest first. */
    fun thread(messages: List<ClinicMessage>, profileId: String) = messages.filter { it.profileId == profileId }.sortedBy { it.dateMs }

    fun unread(messages: List<ClinicMessage>, profileId: String) = messages.count { it.profileId == profileId && !it.fromPatient && it.readMs == null }

    /** The message icon shows once there is a conversation. */
    fun hasConversation(messages: List<ClinicMessage>, profileId: String) = messages.any { it.profileId == profileId }

    /**
     * How a message goes out: in the app when the clinic allows it and the patient turned it on (it
     * waits until DentHub delivers it), by e-mail when asked or when the app route is not available.
     */
    fun channels(clinic: ClinicInfo?, appToApp: Boolean, alsoEmail: Boolean): List<String> {
        val app = clinic != null && clinic.messaging && appToApp
        val email = clinic?.email != null && (alsoEmail || !app)
        return listOfNotNull("app".takeIf { app }, "email".takeIf { email })
    }

    fun statusAfterSend(via: List<String>) = when {
        "app" in via -> "queued"
        "email" in via -> "emailed"
        else -> "queued"
    }

    fun statusText(m: ClinicMessage): String = when (m.status) {
        "queued" -> tr("⏳ kézbesítésre vár")
        "emailed" -> tr("✉️ e-mailben elküldve")
        "delivered" -> tr("✓ kézbesítve")
        "read" -> tr("✓✓ elolvasva")
        else -> ""
    }

    /** Upcoming appointments (confirmed or offered), soonest first. */
    fun upcoming(list: List<Appointment>, profileId: String, now: LocalDateTime) = list
        .filter { it.profileId == profileId && it.status in setOf("confirmed", "offered") }
        .mapNotNull { a -> startOf(a)?.takeIf { it.isAfter(now) }?.let { a to it } }
        .sortedBy { it.second }.map { it.first }

    /** Local reminders for confirmed appointments that are still ahead: (time, text). */
    fun reminders(list: List<Appointment>, now: LocalDateTime): List<Pair<LocalDateTime, String>> = list
        .filter { it.status == "confirmed" }
        .flatMap { a ->
            val start = startOf(a) ?: return@flatMap emptyList()
            a.remindersMin.map { m -> start.minusMinutes(m.toLong()) to reminderText(a, m, start) }
        }
        .filter { it.first.isAfter(now) }.sortedBy { it.first }

    fun reminderText(a: Appointment, minutesBefore: Int, start: LocalDateTime): String {
        val time = "%02d:%02d".format(start.hour, start.minute)
        val place = a.clinicName?.let { " – $it" } ?: ""
        return if (minutesBefore >= 12 * 60) tr("📅 Holnap {0}-kor fogorvos{1}.", time, place)
        else tr("📅 {0}-kor fogorvos{1}. Ne felejts el fogat mosni előtte!", time, place)
    }

    fun when_(a: Appointment): String {
        val t = startOf(a) ?: return a.start
        return "%d.%02d.%02d. %02d:%02d".format(t.year, t.monthValue, t.dayOfMonth, t.hour, t.minute)
    }

    fun title(a: Appointment) = tr("Fogorvos: {0}", VisitReasons.title(a.reason))

    /** The patient's appointment request as a message text. */
    fun requestText(reason: String, timing: String, dayParts: List<String>, note: String): String = buildString {
        appendLine(tr("📅 Időpontot kérek: {0}", VisitReasons.title(reason)))
        appendLine(tr("Mikor: {0}", VisitReasons.timings.firstOrNull { it.first == timing }?.second ?: timing))
        if (dayParts.isNotEmpty()) appendLine(tr("Napszak: {0}", dayParts.mapNotNull { d -> VisitReasons.dayParts.firstOrNull { it.first == d }?.second }.joinToString(", ")))
        if (note.isNotBlank()) appendLine(note.trim())
    }.trimEnd()

    fun acceptText(a: Appointment) = tr("✅ Elfogadom az időpontot: {0}", when_(a))
    fun declineText(a: Appointment) = tr("❌ Ez az időpont nem jó nekem: {0}. Kérek másikat.", when_(a))

    /**
     * An appointment offer from the clinic (QR, link, or later the DentHub messenger):
     * `denthub://appt?d=<base64url JSON>` with start ("2026-11-10T10:30"), durationMin, doctor,
     * clinicName, address, reason, note.
     */
    fun parseOffer(text: String, profileId: String): Appointment? {
        val t = text.trim()
        if (!t.startsWith("denthub://appt?d=")) return null
        return runCatching {
            val bytes = Base64.getUrlDecoder().decode(t.removePrefix("denthub://appt?d=").trimEnd('='))
            json.decodeFromString(Appointment.serializer(), String(bytes, Charsets.UTF_8).let { addProfile(it, profileId) })
        }.getOrNull()?.takeIf { startOf(it) != null && it.durationMin in 5..480 }?.copy(profileId = profileId, status = "offered", calendarAdded = false)
    }

    private fun addProfile(js: String, profileId: String): String =
        if ("\"profileId\"" in js) js else js.trimStart().removePrefix("{").let { "{\"profileId\":\"$profileId\"," + it }

    fun offerCode(a: Appointment): String =
        "denthub://appt?d=" + Base64.getUrlEncoder().withoutPadding().encodeToString(json.encodeToString(Appointment.serializer(), a).toByteArray())

    /** Calendar event times in epoch ms. */
    fun epochRange(a: Appointment, zone: ZoneId): Pair<Long, Long>? {
        val s = startOf(a) ?: return null
        val ms = s.atZone(zone).toInstant().toEpochMilli()
        return ms to ms + a.durationMin * 60_000L
    }
}
