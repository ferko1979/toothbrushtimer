package hu.fogmosas.core

import kotlinx.serialization.Serializable
import java.util.UUID

// "Pontos volt a mérés?" feedback after a brushing. Same as ios/BrushCore/.../Feedback.swift.

object FeedbackReasons {
    data class Reason(val id: String, val title: String)
    val all get() = listOf(
        Reason("too_early", tr("Túl korán leállt")),
        Reason("too_late", tr("Túl későn állt le")),
        Reason("no_start", tr("Későn indult / nem indult el")),
        Reason("wrong_time", tr("Rossz időt mért")),
        Reason("other", tr("Egyéb")),
    )
    fun title(id: String) = all.firstOrNull { it.id == id }?.title ?: id
}

/** Why the measurement stopped, for the result screen. */
fun endReasonText(reason: String): String = when (reason) {
    "rinse" -> tr("Leállás oka: öblítést hallottam.")
    "quiet" -> tr("Leállás oka: egy ideig nem hallottam fogmosást.")
    "user" -> tr("Leállás oka: te állítottad le.")
    else -> tr("Leállás oka: a figyelés véget ért.")
}

@Serializable
data class FeedbackEntry(
    val id: String = UUID.randomUUID().toString(),
    val dateMs: Long,
    val profileId: String,
    val ok: Boolean,
    val reason: String? = null,
    val note: String = "",
    val durationS: Double,
    val endReason: String,
    val cue: String,
    val waterRunningS: Double,
    val brushType: String,
    val targetS: Double,
)

/**
 * The app learns from "stopped too early / too late": extra seconds of silence tolerated before the
 * measurement stops (0…45 s).
 */
fun adjustedQuietExtra(current: Double, reason: String?): Double = when (reason) {
    "too_early" -> minOf(current + 10.0, 45.0)
    "too_late" -> maxOf(current - 5.0, 0.0)
    else -> current
}

/** Text the user can send to the developers (no audio, no personal data except what they typed). */
fun feedbackReport(e: FeedbackEntry, platform: String, appVersion: String, quietExtraS: Double): String = buildString {
    append("DentHub-Brush feedback\n")
    append("platform: $platform $appVersion\n")
    append("verdict: ${if (e.ok) "ok" else "wrong"}${e.reason?.let { " / $it" } ?: ""}\n")
    if (e.note.isNotBlank()) append("note: ${e.note}\n")
    append("duration_s: ${"%.1f".format(java.util.Locale.US, e.durationS)}, target_s: ${e.targetS.toInt()}, end: ${e.endReason}, cue: ${e.cue}\n")
    append("water_running_s: ${"%.1f".format(java.util.Locale.US, e.waterRunningS)}, brush: ${e.brushType}, quiet_extra_s: ${quietExtraS.toInt()}\n")
}
