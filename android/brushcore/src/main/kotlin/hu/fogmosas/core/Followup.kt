package hu.fogmosas.core

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

// Tooth map, follow-up questions after a complaint, photo timeline, care task reminders and the
// electric brush's motor trend. Same as ios/BrushCore/.../Followup.swift (tests: FollowupTest.kt).

/** Adult teeth in FDI numbering, as seen facing the patient: upper right, upper left, lower right, lower left. */
object ToothMap {
    val upperRight = (18 downTo 11).map { it.toString() }
    val upperLeft = (21..28).map { it.toString() }
    val lowerRight = (48 downTo 41).map { it.toString() }
    val lowerLeft = (31..38).map { it.toString() }
    val all = upperRight + upperLeft + lowerRight + lowerLeft
    /** Complaints about one tooth: these ask for the tooth on the map. */
    val kinds = setOf("pain", "sensitivity", "chipped", "loose", "stuck")

    val quadrants get() = listOf(tr("Felső jobb") to upperRight, tr("Felső bal") to upperLeft, tr("Alsó jobb") to lowerRight, tr("Alsó bal") to lowerLeft)

    /** "46" -> "jobb alsó első nagyőrlő" style name, for the summary. */
    fun name(fdi: String): String {
        val q = fdi.firstOrNull()?.digitToIntOrNull() ?: return fdi
        val n = fdi.drop(1).toIntOrNull() ?: return fdi
        val side = when (q) { 1 -> tr("jobb felső"); 2 -> tr("bal felső"); 3 -> tr("bal alsó"); 4 -> tr("jobb alsó"); else -> return fdi }
        val tooth = when (n) {
            1 -> tr("középső metszőfog"); 2 -> tr("oldalsó metszőfog"); 3 -> tr("szemfog")
            4 -> tr("első kisőrlő"); 5 -> tr("második kisőrlő"); 6 -> tr("első nagyőrlő"); 7 -> tr("második nagyőrlő"); 8 -> tr("bölcsességfog")
            else -> return fdi
        }
        return "$fdi ($side $tooth)"
    }
}

// ------------------------------------------------------------------ follow-up

/** Answer to "Hogy van most?" some days after a complaint. */
@Serializable
data class SymptomFollowUp(
    val reportId: String,
    val day: Int,
    /** "gone", "better", "same", "worse", "visited" */
    val answer: String,
    val dateMs: Long,
)

object FollowUps {
    val days = listOf(1, 3, 7)
    val answers get() = listOf("gone" to tr("Elmúlt"), "better" to tr("Javult"), "same" to tr("Ugyanolyan"), "worse" to tr("Rosszabb"), "visited" to tr("Voltam orvosnál"))
    fun title(id: String) = answers.firstOrNull { it.first == id }?.second ?: id
}

private fun daysBetween(fromMs: Long, toMs: Long, zone: ZoneId) =
    ChronoUnit.DAYS.between(Instant.ofEpochMilli(fromMs).atZone(zone).toLocalDate(), Instant.ofEpochMilli(toMs).atZone(zone).toLocalDate()).toInt()

/** The follow-up day (1, 3 or 7) to ask about now, or null (not yet, already answered, resolved, or too old). */
fun followUpDue(r: SymptomReport, ups: List<SymptomFollowUp>, nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): Int? {
    val mine = ups.filter { it.reportId == r.id }
    if (mine.any { it.answer == "gone" || it.answer == "visited" }) return null
    val age = daysBetween(r.dateMs, nowMs, zone)
    if (age > 14) return null
    val answered = mine.maxOfOrNull { it.day } ?: 0
    return FollowUps.days.lastOrNull { it <= age && it > answered }
}

/** What the app says after a follow-up answer; second = suggest contacting the doctor. */
fun followUpAdvice(r: SymptomReport, answer: String, day: Int): Pair<String, Boolean> = when (answer) {
    "worse" -> tr("Rosszabbodott: keresd az orvosodat, és küldd el neki a panaszt.") to true
    "same" -> when {
        day >= 7 -> tr("Egy hét után sem javult: kérj időpontot.") to true
        TriageLevel.byId(r.level).rank >= TriageLevel.SOON.rank -> tr("Nem javult: érdemes időpontot kérni.") to true
        else -> tr("Figyeld tovább; pár nap múlva újra rákérdezünk.") to false
    }
    "better" -> tr("Örülünk, hogy javul! Pár nap múlva még rákérdezünk.") to false
    "gone" -> tr("Nagyszerű, hogy elmúlt! A panasz lezárva.") to false
    else -> tr("Köszönjük, rögzítettük.") to false
}

/** Follow-up notifications (18:00 on day 1, 3 and 7) for complaints not resolved yet. */
fun plannedFollowUps(reports: List<SymptomReport>, ups: List<SymptomFollowUp>, now: LocalDateTime, zone: ZoneId): List<Pair<LocalDateTime, String>> {
    val out = ArrayList<Pair<LocalDateTime, String>>()
    for (r in reports) {
        val mine = ups.filter { it.reportId == r.id }
        if (mine.any { it.answer == "gone" || it.answer == "visited" }) continue
        val answered = mine.maxOfOrNull { it.day } ?: 0
        val day0 = Instant.ofEpochMilli(r.dateMs).atZone(zone).toLocalDate()
        for (d in FollowUps.days.filter { it > answered }) {
            val at = day0.plusDays(d.toLong()).atTime(18, 0)
            if (at.isAfter(now)) out += at to tr("Hogy van most? ({0}, {1} napja)", Symptoms.kind(r.kind).title.lowercase(), d)
        }
    }
    return out.sortedBy { it.first }
}

/** Earlier photos of the same complaint, oldest first (photo comparison). */
fun photoTimeline(reports: List<SymptomReport>, profileId: String, kind: String): List<SymptomReport> =
    reports.filter { it.profileId == profileId && it.kind == kind && it.photos.isNotEmpty() }.sortedBy { it.dateMs }

// ------------------------------------------------------------------ care tasks

/** Medicine / care reminder, e.g. mouthwash twice a day for 7 days after an extraction. */
@Serializable
data class CareTask(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    val title: String,
    /** "HH:mm" */
    val times: List<String>,
    /** ISO date of the first day */
    val start: String,
    val days: Int,
    /** "yyyy-mm-dd HH:mm" slots ticked off */
    val done: List<String> = emptyList(),
) {
    fun startDate(): LocalDate = LocalDate.parse(start)
    fun lastDate(): LocalDate = startDate().plusDays(days - 1L)
    fun activeOn(d: LocalDate) = !d.isBefore(startDate()) && !d.isAfter(lastDate())
    fun slot(d: LocalDate, time: String) = "$d $time"
    fun isDone(d: LocalDate, time: String) = slot(d, time) in done
    fun toggle(d: LocalDate, time: String) = copy(done = if (isDone(d, time)) done - slot(d, time) else done + slot(d, time))
    /** Ticked / all slots so far (including today). */
    fun progress(today: LocalDate): Pair<Int, Int> {
        val end = minOf(today, lastDate())
        if (end.isBefore(startDate())) return 0 to 0
        val n = (ChronoUnit.DAYS.between(startDate(), end).toInt() + 1) * times.size
        return done.size.coerceAtMost(n) to n
    }
}

object CareTaskPresets {
    data class Preset(val title: String, val times: List<String>, val days: Int)
    val all get() = listOf(
        Preset(tr("Szájöblítés (pl. klórhexidin)"), listOf("08:00", "20:00"), 7),
        Preset(tr("Fájdalomcsillapító (a tájékoztató szerint)"), listOf("08:00", "14:00", "20:00"), 3),
        Preset(tr("Antibiotikum (az orvos utasítása szerint)"), listOf("08:00", "16:00", "00:00"), 7),
        Preset(tr("Hideg borogatás"), listOf("10:00", "14:00", "18:00"), 2),
        Preset(tr("Sós vizes öblítés"), listOf("09:00", "21:00"), 5),
    )
    /** Even spread of n reminder times between 08:00 and 20:00. */
    fun times(n: Int): List<String> = when (n.coerceIn(1, 4)) {
        1 -> listOf("09:00"); 2 -> listOf("08:00", "20:00"); 3 -> listOf("08:00", "14:00", "20:00")
        else -> listOf("08:00", "12:00", "16:00", "20:00")
    }
}

/** Reminder notifications for the next [days] days: (time, text). */
fun plannedCareTasks(tasks: List<CareTask>, now: LocalDateTime, days: Int = 7): List<Pair<LocalDateTime, String>> {
    val out = ArrayList<Pair<LocalDateTime, String>>()
    for (t in tasks) for (i in 0 until days) {
        val d = now.toLocalDate().plusDays(i.toLong())
        if (!t.activeOn(d)) continue
        for (time in t.times) {
            val at = d.atTime(LocalTime.parse(time))
            if (at.isAfter(now) && !t.isDone(d, time)) out += at to tr("💊 {0}", t.title)
        }
    }
    return out.sortedBy { it.first }
}

// ------------------------------------------------------------------ motor trend

data class MotorWeek(val weekStart: LocalDate, val medianHz: Double, val sessions: Int)
data class MotorTrend(val weeks: List<MotorWeek>, val changePct: Double?, val text: String)

/** Weekly median motor frequency of the electric brush (from the brushings' f0) and its trend. */
fun motorTrend(records: List<BrushRecord>, today: LocalDate, zone: ZoneId, weeks: Int = 8): MotorTrend {
    val monday = today.minusDays(today.dayOfWeek.value - 1L)
    val first = monday.minusWeeks(weeks - 1L)
    val ws = records.filter { it.brushF0 != null && it.brushF0 > 0 }
        .groupBy { val d = it.start(zone).toLocalDate(); d.minusDays(d.dayOfWeek.value - 1L) }
        .filterKeys { !it.isBefore(first) && !it.isAfter(monday) }
        .map { (w, rs) -> MotorWeek(w, Stats.median(rs.map { it.brushF0!! }), rs.size) }
        .sortedBy { it.weekStart }
    if (ws.size < 2) return MotorTrend(ws, null, tr("A trendhez legalább két hét elektromos fogmosás kell."))
    val base = ws.take(2).maxOf { it.medianHz }
    val now = ws.last().medianHz
    val pct = (now - base) / base * 100
    val text = when {
        pct <= -2.0 -> tr("A motor {0}%-kal lassabban zúg, mint néhány hete: gyengül az akkumulátor, vagy töltésre szorul.", "%.1f".format(-pct))
        else -> tr("A motor egyenletesen zúg ({0} Hz), az akkumulátor rendben.", now.toInt())
    }
    return MotorTrend(ws, pct, text)
}
