package hu.fogmosas.core

import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object Formatting {
    fun grouped(n: Int): String {
        val s = abs(n).toString().reversed().chunked(3).joinToString(if (I18n.lang == "hu") " " else ",").reversed()
        return if (n < 0) "-$s" else s
    }

    /** Hungarian decimal: 1234.56 -> "1 234,6". */
    fun hu(x: Double, digits: Int = 1): String {
        val s = String.format(Locale.US, "%.${digits}f", x)
        val parts = s.split(".")
        val g = grouped(parts[0].toIntOrNull() ?: 0)
        return if (parts.size > 1) g + (if (I18n.lang == "hu") "," else ".") + parts[1] else g
    }

    fun clock(seconds: Double): String {
        val s = max(seconds.roundToInt(), 0)
        return "%d:%02d".format(s / 60, s % 60)
    }
}

// ---------------------------------------------------------------- goals & records

object Recommendation {
    const val PER_DAY = 2
    const val TARGET_S = 120.0
    const val POPULATION_AVG_S = 45.0
    const val QUADRANT_S = 30.0
}

@Serializable
data class Goals(val perDay: Int = Recommendation.PER_DAY, val targetS: Double = Recommendation.TARGET_S) {
    fun clamped() = Goals(perDay.coerceIn(1, 4), targetS.coerceIn(30.0, 300.0))

    val warnings: List<String>
        get() = buildList {
            if (targetS < Recommendation.TARGET_S) add(tr("A fogorvosok legalább 120 másodpercet javasolnak, a célod ({0} s) ennél rövidebb.", targetS.toInt()))
            if (perDay < Recommendation.PER_DAY) add(tr("A fogorvosok naponta kétszeri fogmosást javasolnak (reggel és lefekvés előtt)."))
        }
}

@Serializable
data class BrushRecord(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    val startMs: Long,
    val durationS: Double,
    val waterRunningS: Double = 0.0,
    val source: String = "phone",
    val brushF0: Double? = null,
    /** Loudness of the scrubbing (dBFS, median while brushing); for the "too hard" note. */
    val brushDb: Double? = null,
    /** Electric brush: how long the motor hummed before it stopped, and brushing by hand after it. */
    val motorS: Double? = null,
    val afterMotorS: Double? = null,
) {
    val tapOff get() = waterRunningS < 5.0
    fun start(zone: ZoneId): LocalDateTime = LocalDateTime.ofInstant(Instant.ofEpochMilli(startMs), zone)
}

data class Achievement(val id: String, val title: String, val description: String)

object Achievements {
    val all get() = listOf(
        Achievement("first_brush", tr("Első lépés"), tr("Az első mért fogmosás.")),
        Achievement("above_average", tr("Átlag felett"), tr("Tovább mostál fogat, mint az átlagember (45 s).")),
        Achievement("goal_reached", tr("Célba értél"), tr("Először érted el a kitűzött fogmosási időt.")),
        Achievement("perfect_day", tr("Tökéletes nap"), tr("Egy napon belül minden fogmosás elérte a célidőt.")),
        Achievement("streak_3", tr("Három nap sorban"), tr("3 tökéletes nap egymás után.")),
        Achievement("streak_7", tr("Egy hét fegyelem"), tr("7 tökéletes nap egymás után.")),
        Achievement("streak_30", tr("Egy hónap bajnok"), tr("30 tökéletes nap egymás után.")),
        Achievement("water_saver_10", tr("Víztakarékos"), tr("10 fogmosás elzárt csappal.")),
        Achievement("water_saver_50", tr("Vízőr"), tr("50 fogmosás elzárt csappal.")),
        Achievement("improver", tr("Fejlődés"), tr("A heti átlagod legalább 15 másodperccel jobb, mint az előző héten.")),
    )

    fun byId(id: String) = all.firstOrNull { it.id == id }
}

class Coach(val zone: ZoneId = ZoneId.systemDefault()) {
    fun day(r: BrushRecord): LocalDate = r.start(zone).toLocalDate()

    fun sessionFeedback(d: Double, goals: Goals): String {
        val t = goals.targetS
        if (d >= t) {
            var msg = tr("Szuper! {0} másodperc, elérted a {1} másodperces célt.", d.roundToInt(), t.toInt())
            if (d > 2 * t) msg += tr(" Nem kell ennél sokkal tovább: a túl hosszú, erős súrolás az ínyt is koptathatja.")
            return msg
        }
        var msg = tr("{0} másodperc, még {1} másodperc hiányzott a célhoz.", d.roundToInt(), (t - d).roundToInt())
        msg += if (d >= Recommendation.POPULATION_AVG_S) tr(" Ez már több az átlagos 45 másodpercnél, így tovább!")
        else tr(" Az átlagember kb. 45 másodpercig mos fogat. A 2 perces fogmosás kb. 26%-kal több lepedéket távolít el.")
        msg += tr(" Tipp: mind a 4 fogsornegyedre jusson 30 másodperc (most kb. {0} negyed jutott rá teljesen).", (d / Recommendation.QUADRANT_S).toInt())
        return msg
    }

    fun isPerfectDay(rs: List<BrushRecord>, goals: Goals) = rs.count { it.durationS >= goals.targetS } >= goals.perDay

    fun perfectStreak(rs: List<BrushRecord>, goals: Goals, today: LocalDate): Int {
        val days = rs.groupBy { day(it) }
        var d = if (isPerfectDay(days[today].orEmpty(), goals)) today else today.minusDays(1)
        var n = 0
        while (isPerfectDay(days[d].orEmpty(), goals)) { n++; d = d.minusDays(1) }
        return n
    }

    private fun weekAvg(rs: List<BrushRecord>, start: LocalDate): Double? {
        val xs = rs.filter { val d = day(it); !d.isBefore(start) && d.isBefore(start.plusDays(7)) }.map { it.durationS }
        return if (xs.isEmpty()) null else xs.average()
    }

    fun earnedAchievements(rs: List<BrushRecord>, goals: Goals, today: LocalDate): Set<String> {
        if (rs.isEmpty()) return emptySet()
        val out = mutableSetOf("first_brush")
        if (rs.any { it.durationS >= Recommendation.POPULATION_AVG_S }) out += "above_average"
        if (rs.any { it.durationS >= goals.targetS }) out += "goal_reached"
        val perfect = rs.groupBy { day(it) }.filter { isPerfectDay(it.value, goals) }.keys.sorted()
        if (perfect.isNotEmpty()) out += "perfect_day"
        var best = 0
        var run = 0
        var prev: LocalDate? = null
        for (d in perfect) {
            run = if (prev != null && prev.plusDays(1) == d) run + 1 else 1
            best = max(best, run)
            prev = d
        }
        for (n in listOf(3, 7, 30)) if (best >= n) out += "streak_$n"
        val saved = rs.count { it.tapOff }
        if (saved >= 10) out += "water_saver_10"
        if (saved >= 50) out += "water_saver_50"
        val thisWeek = today.minusDays(6)
        val a = weekAvg(rs, thisWeek)
        val b = weekAvg(rs, thisWeek.minusDays(7))
        if (a != null && b != null && a - b >= 15) out += "improver"
        return out
    }

    fun todayCount(rs: List<BrushRecord>, today: LocalDate) = rs.count { day(it) == today }

    fun dailySummary(rs: List<BrushRecord>, goals: Goals, today: LocalDate): String {
        val todays = rs.filter { day(it) == today }
        val good = todays.count { it.durationS >= goals.targetS }
        val left = max(goals.perDay - todays.size, 0)
        val streak = perfectStreak(rs, goals, today)
        val parts = mutableListOf(tr("Ma: {0}/{1} fogmosás, ebből {2} érte el a {3} s-ot.", todays.size, goals.perDay, good, goals.targetS.toInt()))
        if (left > 0) parts += tr("Még {0} fogmosás van hátra mára.", left) else if (good >= goals.perDay) parts += tr("Tökéletes nap! 🎉")
        if (streak >= 2) parts += tr("{0} tökéletes nap sorozatban.", streak)
        return parts.joinToString(" ")
    }

    fun weeklyProgress(rs: List<BrushRecord>, goals: Goals, today: LocalDate): String {
        val thisWeek = today.minusDays(6)
        val a = weekAvg(rs, thisWeek) ?: return tr("Ezen a héten még nincs mért fogmosás.")
        var msg = tr("Heti átlag: {0} s (cél: {1} s).", a.roundToInt(), goals.targetS.toInt())
        val b = weekAvg(rs, thisWeek.minusDays(7))
        if (b != null) {
            val diff = a - b
            msg += when {
                diff >= 5 -> tr(" {0} másodperccel jobb, mint a múlt héten, szép fejlődés!", diff.roundToInt())
                diff <= -5 -> tr(" {0} másodperccel kevesebb, mint a múlt héten. Próbáld meg a negyedenkénti jelzést követni!", (-diff).roundToInt())
                else -> tr(" Nagyjából ugyanannyi, mint a múlt héten.")
            }
        }
        if (a < goals.targetS) msg += tr(" Átlagban még {0} másodperc hiányzik a célhoz.", (goals.targetS - a).roundToInt())
        return msg
    }
}

// ---------------------------------------------------------------- cues

object Quadrants { val names get() = listOf(tr("jobb felső"), tr("bal felső"), tr("bal alsó"), tr("jobb alsó")) }

data class Cue(val atS: Double, val kind: String, val quadrant: Int, val haptic: String, val text: String)

fun cueSchedule(targetS: Double): List<Cue> {
    val step = targetS / 4
    val out = mutableListOf(Cue(0.0, "start", 1, "tap", tr("Kezdd a {0} negyeddel", Quadrants.names[0])))
    for (k in 1 until 4) out += Cue(step * k, "quadrant", k + 1, "tap", tr("Jöhet a {0} negyed", Quadrants.names[k]))
    out += Cue(targetS, "done", 4, "success", tr("Kész, elérted a célidőt! 🎉"))
    return out
}

data class BrushProgress(val fraction: Double, val quadrant: Int, val quadrantName: String, val remainingS: Double)

fun brushProgress(elapsedS: Double, targetS: Double): BrushProgress {
    val f = (elapsedS / targetS).coerceIn(0.0, 1.0)
    val q = min((f * 4).toInt(), 3)
    return BrushProgress(f, q + 1, Quadrants.names[q], max(targetS - elapsedS, 0.0))
}

class CueTracker(targetS: Double) {
    private val pending = cueSchedule(targetS).toMutableList()
    fun update(elapsedS: Double): List<Cue> {
        val fired = pending.filter { it.atS <= elapsedS }
        pending.removeAll { it.atS <= elapsedS }
        return fired
    }
}

// ---------------------------------------------------------------- water

@Serializable
data class WaterLocale(
    val id: String, val flowLPerMin: Double, val pricePerLitre: Double, val currency: String,
    val dailyUsePerPersonL: Double, val glassL: Double, val glassName: String, val imperial: Boolean,
) {
    companion object {
        const val L_PER_GAL = 3.785411784
        val HU = WaterLocale("hu", 8.0, 0.653, "Ft", 105.0, 0.25, tr("pohár (2,5 dl)"), false)
        val US = WaterLocale("us", 2.2 * L_PER_GAL, 0.0125 / L_PER_GAL, "$", 82 * L_PER_GAL, 0.2366, "8 oz glass", true)
        fun named(id: String) = if (id == "us") US else HU
    }

    fun withFlow(lPerMin: Double?) = if (lPerMin == null) this else copy(flowLPerMin = lPerMin)
}

data class WaterReport(val seconds: Double, val locale: WaterLocale = WaterLocale.HU) {
    val litres = seconds / 60 * locale.flowLPerMin
    val gallons = litres / WaterLocale.L_PER_GAL
    val cost = litres * locale.pricePerLitre
    val glasses = litres / locale.glassL
    val pctDailyUse = 100 * litres / locale.dailyUsePerPersonL
    val pctDrinking = 100 * litres / 2.0
    val litresPerYear = litres * 2 * 365
    val costPerYear = litresPerYear * locale.pricePerLitre
}

data class WaterMessage(val title: String, val lines: List<String>, val wasted: Boolean)

fun waterMessage(brushingS: Double, waterRunningS: Double, locale: WaterLocale): WaterMessage {
    val wasted = waterRunningS >= 5
    if (locale.imperial) {
        if (wasted) {
            val r = WaterReport(waterRunningS, locale)
            return WaterMessage("⚠️ Water waste: the tap ran for ${waterRunningS.toInt()} s", listOf(
                "About %.1f gallons (%.1f L, ~%.0f glasses), about $%.3f.".format(Locale.US, r.gallons, r.litres, r.glasses, r.cost),
                "That's ~%.0f%% of an average American's daily home water use.".format(Locale.US, r.pctDailyUse),
                "Twice a day for a year: ~%.0f gallons (~$%.0f).".format(Locale.US, r.litresPerYear / WaterLocale.L_PER_GAL, r.costPerYear),
                "Tip: turn the tap off after wetting your brush and back on only to rinse.",
            ), true)
        }
        val r = WaterReport(brushingS, locale)
        return WaterMessage("💧 Nice, you kept the tap off!", listOf(
            "A running tap would have wasted ~%.1f gallons (~%.0f gallons a year).".format(Locale.US, r.gallons, r.litresPerYear / WaterLocale.L_PER_GAL),
        ), false)
    }
    if (wasted) {
        val r = WaterReport(waterRunningS, locale)
        return WaterMessage(tr("⚠️ Vízpazarlás: a csap {0} másodpercig folyt", waterRunningS.toInt()), listOf(
            tr("Ez kb. {0} liter víz (~{1} {2}), kb. {3} {4}.", Formatting.hu(r.litres), Formatting.hu(r.glasses, 0), locale.glassName, Formatting.hu(r.cost), locale.currency),
            tr("Egy ember napi vízfogyasztásának kb. {0}%-a, a napi ajánlott ivóvíz {1}%-a.", Formatting.hu(r.pctDailyUse, 0), Formatting.hu(r.pctDrinking, 0)),
            tr("Ha minden reggel és este így mosol fogat: évente kb. {0} m³ (~{1} {2}).", Formatting.hu(r.litresPerYear / 1000), Formatting.hu(r.costPerYear, 0), locale.currency),
            tr("Tipp: a fogkefe benedvesítése után zárd el a csapot, és csak öblítéskor nyisd meg újra."),
        ), true)
    }
    val r = WaterReport(brushingS, locale)
    return WaterMessage(tr("💧 Szép munka, elzártad a csapot!"), listOf(
        tr("Ha folyt volna, kb. {0} liter (~{1} pohár) víz folyt volna el feleslegesen, évente kb. {2} m³.", Formatting.hu(r.litres), Formatting.hu(r.glasses, 0), Formatting.hu(r.litresPerYear / 1000)),
    ), false)
}

// ---------------------------------------------------------------- reminders

@Serializable
data class ClockTime(val hour: Int, val minute: Int) : Comparable<ClockTime> {
    val minutes get() = hour * 60 + minute
    override fun compareTo(other: ClockTime) = minutes.compareTo(other.minutes)
    fun plusMinutes(m: Int): ClockTime { val t = ((minutes + m) % 1440 + 1440) % 1440; return ClockTime(t / 60, t % 60) }
    val text get() = "%d:%02d".format(hour, minute)
    fun toLocalTime(): LocalTime = LocalTime.of(hour, minute)
}

@Serializable
data class ReminderSettings(
    val enabled: Boolean = true,
    val morningEnabled: Boolean = true,
    val wakeTime: ClockTime = ClockTime(7, 0),
    val bedtimeEnabled: Boolean = true,
    val bedtime: ClockTime = ClockTime(22, 30),
    val bedtimeLeadMin: Int = 15,
    val eveningEnabled: Boolean = false,
    val eveningTime: ClockTime = ClockTime(20, 0),
    val followupEnabled: Boolean = true,
    val followupAfterMin: Int = 20,
    val maxFollowups: Int = 1,
)

data class PlannedReminder(val id: String, val key: String, val fireAt: LocalDateTime, val text: String)

object ReminderTexts {
    val MORNING get() = tr("Jó reggelt! Kezdd a napot 2 perc fogmosással. 🪥")
    val BEDTIME get() = tr("Hamarosan lefekvés: még hiányzik az esti fogmosás. Koppints, és indulhat.")
    val EVENING get() = tr("Esti fogmosás: 2 perc, és kész is vagy a mai céllal.")
    val FOLLOWUP get() = tr("Még mindig vár a fogkefe. 😉 Nyisd meg az appot, és kezdheted.")
}

object ReminderPlanner {
    val MORNING = ClockTime(4, 0) to ClockTime(11, 59)
    val EVENING = ClockTime(17, 0) to ClockTime(23, 59)

    fun inWindow(t: LocalTime, w: Pair<ClockTime, ClockTime>): Boolean {
        val c = ClockTime(t.hour, t.minute)
        return c >= w.first && c <= w.second
    }

    fun plan(now: LocalDateTime, records: List<BrushRecord>, goals: Goals, s: ReminderSettings, zone: ZoneId, days: Int = 7): List<PlannedReminder> {
        if (!s.enabled) return emptyList()
        val out = ArrayList<PlannedReminder>()
        for (offset in 0 until days) {
            val day = now.toLocalDate().plusDays(offset.toLong())
            val dayRecs = records.filter { it.start(zone).toLocalDate() == day }
            val morningDone = dayRecs.any { inWindow(it.start(zone).toLocalTime(), MORNING) }
            val eveningDone = dayRecs.any { inWindow(it.start(zone).toLocalTime(), EVENING) }
            val base = ArrayList<Triple<String, LocalDateTime, String>>()
            if (s.morningEnabled && !morningDone) base += Triple("morning", day.atTime(s.wakeTime.toLocalTime()), ReminderTexts.MORNING)
            if (goals.perDay >= 2 && !eveningDone) {
                if (s.eveningEnabled) base += Triple("evening", day.atTime(s.eveningTime.toLocalTime()), ReminderTexts.EVENING)
                if (s.bedtimeEnabled) base += Triple("bedtime", day.atTime(s.bedtime.plusMinutes(-s.bedtimeLeadMin).toLocalTime()), ReminderTexts.BEDTIME)
            }
            for ((k, at, text) in base) {
                val items = mutableListOf(Triple(k, at, text))
                if (s.followupEnabled) for (n in 1..s.maxFollowups) {
                    items += Triple("${k}_followup$n", at.plusMinutes((n * s.followupAfterMin).toLong()), ReminderTexts.FOLLOWUP)
                }
                for ((kk, aa, tt) in items) if (aa.isAfter(now)) out += PlannedReminder("rem.$kk.$day", kk, aa, tt)
            }
        }
        return out.sortedBy { it.fireAt }
    }
}

// ---------------------------------------------------------------- listening policy

/** When does the app listen? (listening.py) */
class ListeningPolicy {
    var flatMaxTiltDeg = 20.0
    var stillMaxStdG = 0.03
    var stillWindowS = 2.0
    var idleTimeoutS = 300.0
    var armedTimeoutS = 600.0
    var afterSessionGraceS = 30.0

    var listening = false; private set
    var foreground = false; private set
    var armed = false; private set
    var placed = false; private set
    var stopReason = ""; private set

    private val motion = ArrayDeque<DoubleArray>()
    private var lastActivity = 0.0
    private var sessionEnd: Double? = null

    fun appOpened(t: Double, fromNotification: Boolean = false) {
        foreground = true; listening = true; armed = armed || fromNotification
        lastActivity = t; sessionEnd = null; stopReason = ""
    }

    fun appBackgrounded(t: Double) {
        foreground = false
        if (listening && !placed) stop(tr("app háttérbe került, a telefon nincs letéve"))
    }

    fun appForegrounded(t: Double) { foreground = true }

    fun motion(t: Double, gx: Double, gy: Double, gz: Double) {
        motion.addLast(doubleArrayOf(t, gx, gy, gz))
        while (motion.isNotEmpty() && motion.first()[0] < t - stillWindowS) motion.removeFirst()
        val span = motion.last()[0] - motion.first()[0]
        val was = placed
        placed = span >= stillWindowS * 0.9 && flatAndStill()
        if (was && !flat(gx, gy, gz) && listening && !foreground) stop(tr("felvették a telefont"))
    }

    fun activity(t: Double) { lastActivity = t }
    fun sessionFinished(t: Double) { sessionEnd = t; armed = false }

    fun tick(t: Double) {
        if (!listening) return
        val end = sessionEnd
        if (end != null && !foreground && t - end >= afterSessionGraceS) { stop(tr("a fogmosás véget ért")); return }
        if (t - lastActivity >= (if (armed) armedTimeoutS else idleTimeoutS)) stop(tr("hosszú ideig nem hallatszott víz vagy fogmosás"))
    }

    fun stopManually() = stop(tr("leállítva"))
    val sessionConfig get() = if (armed) SessionConfig.ARMED else SessionConfig()

    private fun stop(reason: String) { listening = false; armed = false; stopReason = reason }

    private fun flat(gx: Double, gy: Double, gz: Double): Boolean {
        val n = kotlin.math.sqrt(gx * gx + gy * gy + gz * gz).let { if (it > 0) it else 1.0 }
        return abs(gz) / n >= kotlin.math.cos(Math.toRadians(flatMaxTiltDeg))
    }

    private fun flatAndStill(): Boolean {
        if (motion.size < 3) return false
        if (!motion.all { flat(it[1], it[2], it[3]) }) return false
        return (1..3).all { a -> Stats.std(DoubleArray(motion.size) { motion[it][a] }) <= stillMaxStdG }
    }
}

// ---------------------------------------------------------------- brush head, extras, calibration

data class BrushHeadStatus(val ageDays: Int, val uses: Int, val due: Boolean, val soon: Boolean, val message: String)

fun brushHeadStatus(installed: LocalDate, electric: Boolean, records: List<BrushRecord>, today: LocalDate, zone: ZoneId, afterIllness: Boolean = false): BrushHeadStatus {
    val age = ChronoUnit.DAYS.between(installed, today).toInt()
    val uses = records.count { !it.start(zone).toLocalDate().isBefore(installed) }
    val thing = if (electric) tr("fogkefefejet") else tr("fogkefét")
    return when {
        afterIllness -> BrushHeadStatus(age, uses, true, false, tr("Betegség után érdemes új {0} használni, hogy ne maradjanak kórokozók a sörtéken.", thing))
        age >= 90 -> BrushHeadStatus(age, uses, true, false, tr("Ideje új {0} venni: {1} napja ({2} fogmosás) használod. A fogorvosok 3–4 havonta javasolják a cserét.", thing, age, uses))
        age >= 83 -> BrushHeadStatus(age, uses, false, true, tr("Egy héten belül esedékes a csere: {0} napja ({1} fogmosás) használod.", age, uses))
        else -> BrushHeadStatus(age, uses, false, false, tr("{0} napos, {1} fogmosás. Ha a sörték szétállnak vagy elhajlottak, cseréld hamarabb.", age, uses))
    }
}

@Serializable
data class ExtraRecord(val id: String = UUID.randomUUID().toString(), val profileId: String, val dateMs: Long, val kind: String)

fun extrasDoneToday(records: List<ExtraRecord>, kind: String, today: LocalDate, zone: ZoneId) =
    records.any { it.kind == kind && Instant.ofEpochMilli(it.dateMs).atZone(zone).toLocalDate() == today }

@Serializable
data class BrushCalibration(val f0s: List<Double> = emptyList(), val sessionsNeeded: Int = 3) {
    fun add(f0: Double?) = if (f0 != null && f0 > 0) copy(f0s = f0s + f0) else this
    val brushF0: Double?
        get() {
            val recent = f0s.takeLast(sessionsNeeded)
            if (recent.size < sessionsNeeded) return null
            val m = Stats.median(recent)
            return if (recent.all { abs(it - m) <= 5.0 }) m else null
        }
    val remaining get() = max(sessionsNeeded - f0s.size, 0)
    fun sonicConfig() = brushF0?.let { SonicConfig.calibrated(it) } ?: SonicConfig()
    val statusText: String
        get() = brushF0?.let { tr("Kalibrálva: a fogkeféd {0} Hz-en zúg.", it.roundToInt()) }
            ?: if (remaining > 0) tr("Kalibráció: még {0} fogmosás kell a fogkeféd hangjának megtanulásához.", remaining)
            else tr("Kalibráció: a fogkefe hangja még nem egyértelmű, folytatom a tanulást.")
}

fun tapFlowFromMeasurement(litres: Double, seconds: Double): Double {
    require(litres > 0 && seconds > 0) { "invalid" }
    val flow = litres / seconds * 60
    require(flow in 1.0..30.0) { "unrealistic" }
    return flow
}

// ---------------------------------------------------------------- habits & monthly

data class Habit(val id: String, val message: String)

fun detectHabits(rs: List<BrushRecord>, goals: Goals, today: LocalDate, zone: ZoneId): List<Habit> {
    fun day(r: BrushRecord) = r.start(zone).toLocalDate()
    fun window(days: Int, offset: Int = 0): List<BrushRecord> {
        val start = today.minusDays((days - 1 + offset).toLong())
        val end = today.minusDays(offset.toLong())
        return rs.filter { val d = day(it); !d.isBefore(start) && !d.isAfter(end) }
    }
    fun daysMissing(w: Pair<ClockTime, ClockTime>): Int {
        val have = rs.filter { ReminderPlanner.inWindow(it.start(zone).toLocalTime(), w) }.map { day(it) }.toSet()
        return (1..7).count { today.minusDays(it.toLong()) !in have }
    }
    val out = ArrayList<Habit>()
    val last14 = window(14)
    val last7 = window(7)
    if (last14.size >= 4) {
        if (last14.count { it.durationS < 30 }.toDouble() / last14.size >= 0.5) out += Habit("rushing", tr("Az utóbbi két hétben a fogmosások fele 30 másodpercnél rövidebb volt. Kövesd a negyedenkénti rezgést: minden jelzésnél válts a következő fogsornegyedre."))
        if (last14.count { it.durationS > 240 }.toDouble() / last14.size >= 0.5) out += Habit("overbrushing", tr("Gyakran 4 percnél is tovább mosol fogat. A 2–3 perc elég; a túl hosszú, erős súrolás az ínyt és a zománcot koptathatja. Puha sörtéjű fogkefe ajánlott."))
    }
    if (rs.isNotEmpty() && goals.perDay >= 2) {
        if (daysMissing(ReminderPlanner.EVENING) >= 3) out += Habit("evening_skipped", tr("Az elmúlt héten legalább 3 este kimaradt a fogmosás. Az esti a legfontosabb: éjszaka kevesebb nyál termelődik, ezért a lepedék könnyebben károsít. Kapcsold be a lefekvés előtti emlékeztetőt!"))
        if (daysMissing(ReminderPlanner.MORNING) >= 3) out += Habit("morning_skipped", tr("Az elmúlt héten legalább 3 reggel kimaradt a fogmosás. Próbáld egy meglévő szokáshoz kötni (pl. reggeli után, öltözködés előtt)."))
    }
    if (last7.count { !it.tapOff } >= 3) out += Habit("tap_running", tr("Az elmúlt héten többször folyt a csap fogmosás közben. Nedvesítés után zárd el, és csak öblítéskor nyisd meg újra."))
    val weekday = last14.filter { day(it).dayOfWeek !in setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY) }
    val weekend = last14.filter { day(it).dayOfWeek in setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY) }
    if (weekday.size >= 2 && weekend.size >= 2) {
        val a = weekday.map { it.durationS }.average()
        val b = weekend.map { it.durationS }.average()
        if (b < a - 20) out += Habit("weekend_dip", tr("Hétvégén átlagosan {0} másodperccel rövidebben mosol fogat, mint hétköznap. A fogaidnak nincs hétvégéjük. 😉", (a - b).roundToInt()))
    }
    val prev7 = window(7, 7)
    if (last7.size >= 3 && prev7.size >= 3) {
        val a = last7.map { it.durationS }.average()
        val b = prev7.map { it.durationS }.average()
        if (a < b - 15) out += Habit("declining", tr("Az utóbbi héten {0} másodperccel rövidebbek a fogmosásaid, mint előtte. Tűzz ki egy rövid célt: holnap legalább egyszer a teljes kör!", (b - a).roundToInt()))
    }
    return out
}

val MONTHS_HU get() = listOf(tr("január"), tr("február"), tr("március"), tr("április"), tr("május"), tr("június"), tr("július"), tr("augusztus"), tr("szeptember"), tr("október"), tr("november"), tr("december"))

fun monthlyReportText(rs: List<BrushRecord>, goals: Goals, year: Int, month: Int, locale: WaterLocale, zone: ZoneId, name: String = ""): String {
    val coach = Coach(zone)
    val ndays = java.time.YearMonth.of(year, month).lengthOfMonth()
    val m = rs.filter { val d = it.start(zone); d.year == year && d.monthValue == month }
    val days = m.groupBy { coach.day(it) }
    val perfect = days.filter { coach.isPerfectDay(it.value, goals) }.keys.sorted()
    var best = 0; var run = 0; var prev: LocalDate? = null
    for (d in perfect) { run = if (prev != null && prev.plusDays(1) == d) run + 1 else 1; best = max(best, run); prev = d }
    val morning = m.count { ReminderPlanner.inWindow(it.start(zone).toLocalTime(), ReminderPlanner.MORNING) }
    val evening = m.count { ReminderPlanner.inWindow(it.start(zone).toLocalTime(), ReminderPlanner.EVENING) }
    val flowPerS = locale.flowLPerMin / 60
    val tapOff = m.filter { it.tapOff }
    val avg = if (m.isEmpty()) 0.0 else m.map { it.durationS }.average()
    val pct = if (m.isEmpty()) 0.0 else 100.0 * m.count { it.durationS >= goals.targetS } / m.size
    val saved = tapOff.sumOf { it.durationS } * flowPerS
    val wasted = m.sumOf { it.waterRunningS } * flowPerS
    val lines = mutableListOf(
        tr("Havi fogmosás-összefoglaló – {0}. {1}", year, MONTHS_HU[month - 1]) + (if (name.isEmpty()) "" else " – $name"),
        tr("Fogmosások: {0} / {1} tervezett ({2} napon; reggel {3}, este {4})", m.size, ndays * goals.perDay, days.size, morning, evening),
        tr("Átlagos időtartam: {0} s (cél: {1} s), a célidőt elérte: {2}%", avg.roundToInt(), goals.targetS.toInt(), pct.roundToInt()),
        tr("Tökéletes napok: {0}, leghosszabb sorozat: {1} nap", perfect.size, best),
        tr("Elzárt csappal: {0} fogmosás, megtakarított víz kb. {1} l", tapOff.size, saved.roundToInt()),
    )
    if (wasted >= 1) lines += tr("Fogmosás közben elfolyt víz: kb. {0} l", wasted.roundToInt())
    lines += tr("Mérés: a telefon/óra mikrofonja alapján, a készüléken feldolgozva (hangfelvétel nem készül).")
    return lines.joinToString("\n")
}

fun recordsCsv(rs: List<BrushRecord>): String = buildString {
    append("start,duration_s,water_running_s,source\n")
    for (r in rs.sortedBy { it.startMs }) append("${Instant.ofEpochMilli(r.startMs)},${"%.1f".format(Locale.US, r.durationS)},${"%.1f".format(Locale.US, r.waterRunningS)},${r.source}\n")
}
