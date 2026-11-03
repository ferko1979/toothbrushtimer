package hu.fogmosas.core

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlin.math.roundToInt

// Oral-care journal: symptoms (sensitivity, bleeding gums) and extras (floss,
// mouthwash, interdental brush, tongue cleaning, toothpaste). Ported 1:1 in
// ios/BrushCore/Sources/BrushCore/Logic/Care.swift — keep the two in sync.

object Toothpastes {
    data class Kind(val id: String, val title: String)
    val all get() = listOf(
        Kind("fluoride", tr("Normál fluoridos")),
        Kind("sensitive", tr("Érzékeny fogra")),
        Kind("whitening", tr("Fehérítő")),
        Kind("gum", tr("Ínyvédő")),
        Kind("kids", tr("Gyerek fogkrém")),
        Kind("herbal", tr("Gyógynövényes / fluoridmentes")),
    )
    fun title(id: String?) = all.firstOrNull { it.id == id }?.title ?: "—"
}

/** One check-in, usually right after a brushing. sensitivity: 0 none, 1 mild, 2 strong. */
@Serializable
data class CareEntry(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    val dateMs: Long,
    val sensitivity: Int = 0,
    val bleeding: Boolean = false,
    val floss: Boolean = false,
    val mouthwash: Boolean = false,
    val interdental: Boolean = false,
    val tongue: Boolean = false,
    val toothpaste: String? = null,
) {
    fun day(zone: ZoneId): LocalDate = Instant.ofEpochMilli(dateMs).atZone(zone).toLocalDate()
}

/** Old floss / mouthwash ticks (ExtraRecord) as journal entries. */
fun ExtraRecord.toCare() = CareEntry(id = id, profileId = profileId, dateMs = dateMs,
    floss = kind == "floss", mouthwash = kind == "mouthwash")

enum class CareKind(val label: String) {
    FLOSS(tr("Fogselyem")), MOUTHWASH(tr("Szájvíz")), INTERDENTAL(tr("Fogköztisztító")), TONGUE(tr("Nyelvtisztítás")),
    SENSITIVITY(tr("Érzékenység")), BLEEDING(tr("Ínyvérzés"));

    fun matches(e: CareEntry) = when (this) {
        FLOSS -> e.floss
        MOUTHWASH -> e.mouthwash
        INTERDENTAL -> e.interdental
        TONGUE -> e.tongue
        SENSITIVITY -> e.sensitivity > 0
        BLEEDING -> e.bleeding
    }
}

/** Per-day merge of all check-ins of that day. */
data class CareDay(
    val day: LocalDate, val floss: Boolean, val mouthwash: Boolean, val interdental: Boolean, val tongue: Boolean,
    val sensitivity: Int, val bleeding: Boolean, val toothpaste: String?,
)

fun careDays(entries: List<CareEntry>, zone: ZoneId): Map<LocalDate, CareDay> =
    entries.groupBy { it.day(zone) }.mapValues { (d, es) ->
        CareDay(d, es.any { it.floss }, es.any { it.mouthwash }, es.any { it.interdental }, es.any { it.tongue },
            es.maxOf { it.sensitivity }, es.any { it.bleeding }, es.sortedBy { it.dateMs }.lastOrNull { it.toothpaste != null }?.toothpaste)
    }

/** Number of days in [today - days + 1, today] with the kind present. */
fun careCount(entries: List<CareEntry>, kind: CareKind, today: LocalDate, days: Int, zone: ZoneId, offsetDays: Int = 0): Int {
    val end = today.minusDays(offsetDays.toLong())
    val start = end.minusDays(days - 1L)
    return entries.filter { kind.matches(it) }.map { it.day(zone) }.toSet().count { !it.isBefore(start) && !it.isAfter(end) }
}

/** Consecutive days with the kind, ending today (or yesterday if today is not ticked yet). */
fun careStreak(entries: List<CareEntry>, kind: CareKind, today: LocalDate, zone: ZoneId): Int {
    val days = entries.filter { kind.matches(it) }.map { it.day(zone) }.toSet()
    var d = if (today in days) today else today.minusDays(1)
    var n = 0
    while (d in days) { n++; d = d.minusDays(1) }
    return n
}

fun careDoneToday(entries: List<CareEntry>, kind: CareKind, today: LocalDate, zone: ZoneId) =
    entries.any { kind.matches(it) && it.day(zone) == today }

data class CareInsight(val id: String, val text: String, val alert: Boolean = false)

object CareRules {
    const val WINDOW = 14
    const val BLEEDING_ALERT_DAYS = 4
    const val SENSITIVITY_ALERT_DAYS = 5
    val DISCLAIMER get() = tr("Ez nem orvosi diagnózis.")
}

/**
 * Observations over the last two weeks compared with the two weeks before.
 * Alerts (persistent bleeding or sensitivity) come first.
 */
fun careInsights(entries: List<CareEntry>, today: LocalDate, zone: ZoneId, flossTracked: Boolean = true): List<CareInsight> {
    val w = CareRules.WINDOW
    fun now(k: CareKind) = careCount(entries, k, today, w, zone)
    fun before(k: CareKind) = careCount(entries, k, today, w, zone, offsetDays = w)
    fun recent(k: CareKind) = careCount(entries, k, today, 3, zone)
    val out = mutableListOf<CareInsight>()

    val bleed = now(CareKind.BLEEDING)
    if (bleed >= CareRules.BLEEDING_ALERT_DAYS && recent(CareKind.BLEEDING) > 0) out += CareInsight("bleeding_persistent",
        tr("Az ínyed az utóbbi 2 hétben {0} napon vérzett. Ha a vérzés 2 hétnél tovább tart, keresd fel a fogorvosodat. {1}", bleed, CareRules.DISCLAIMER), alert = true)
    val days = careDays(entries, zone)
    val strong = days.values.count { it.sensitivity >= 2 && !it.day.isBefore(today.minusDays(w - 1L)) && !it.day.isAfter(today) }
    val sens = now(CareKind.SENSITIVITY)
    if (sens >= CareRules.SENSITIVITY_ALERT_DAYS && recent(CareKind.SENSITIVITY) > 0) out += CareInsight("sensitivity_persistent",
        tr("Az utóbbi 2 hétben {0} napon jeleztél fogérzékenységet", sens) + (if (strong > 0) tr(" ({0} napon erőset)", strong) else "") +
            tr(". A tartós érzékenységet érdemes megmutatni a fogorvosnak. {0}", CareRules.DISCLAIMER), alert = true)

    val flossNow = now(CareKind.FLOSS)
    val flossBefore = before(CareKind.FLOSS)
    val bleedBefore = before(CareKind.BLEEDING)
    if (flossNow > flossBefore && bleed < bleedBefore) out += CareInsight("floss_helps",
        tr("Amióta gyakrabban fogselymezel ({0} → {1} nap / 2 hét), ritkábban vérzik az ínyed ({2} → {3} nap).", flossBefore, flossNow, bleedBefore, bleed))

    val pasteNow = days.values.filter { !it.day.isBefore(today.minusDays(w - 1L)) && !it.day.isAfter(today) }.mapNotNull { it.toothpaste }
    val sensBefore = before(CareKind.SENSITIVITY)
    if (pasteNow.count { it == "sensitive" } * 2 >= maxOf(pasteNow.size, 1) && pasteNow.isNotEmpty() && sens < sensBefore) out += CareInsight("toothpaste_helps",
        tr("Amióta érzékeny fogra való fogkrémet használsz, ritkábban jelzel érzékenységet ({0} → {1} nap / 2 hét).", sensBefore, sens))
    else if (sens >= 3 && pasteNow.isNotEmpty() && pasteNow.none { it == "sensitive" }) out += CareInsight("toothpaste_try",
        tr("Gyakran jelzel érzékenységet. Kérdezd meg a fogorvosodat, hogy segíthet-e egy érzékeny fogra való fogkrém."))

    if (flossTracked && careCount(entries, CareKind.FLOSS, today, 7, zone) < 3 && entries.isNotEmpty()) out += CareInsight("floss_rare",
        tr("A fogorvosok naponta egyszer javasolják a fogközök tisztítását (fogselyem vagy fogköztisztító kefe). Az utóbbi héten {0} napon volt.", careCount(entries, CareKind.FLOSS, today, 7, zone)))
    return out
}

// ------------------------------------------------------------------ dentist visits

data class DentistStatus(val checkupDue: LocalDate?, val cleaningDue: LocalDate?, val checkupOverdue: Boolean, val cleaningOverdue: Boolean) {
    val message: String? get() = when {
        checkupOverdue && cleaningOverdue -> tr("Esedékes a fogorvosi kontroll és a fogkőeltávolítás.")
        checkupOverdue -> tr("Esedékes a félévenkénti fogorvosi kontroll.")
        cleaningOverdue -> tr("Esedékes az éves fogkőeltávolítás.")
        else -> null
    }
}

object DentistRules {
    const val CHECKUP_MONTHS = 6L
    const val CLEANING_MONTHS = 12L
}

fun dentistStatus(lastCheckup: LocalDate?, lastCleaning: LocalDate?, today: LocalDate): DentistStatus {
    val c = lastCheckup?.plusMonths(DentistRules.CHECKUP_MONTHS)
    val k = lastCleaning?.plusMonths(DentistRules.CLEANING_MONTHS)
    return DentistStatus(c, k, c != null && !today.isBefore(c), k != null && !today.isBefore(k))
}

/** Date of the next dentist reminder (10:00 local time is applied by the scheduler), or null. */
fun nextDentistReminder(lastCheckup: LocalDate?, lastCleaning: LocalDate?, today: LocalDate): LocalDate? {
    val s = dentistStatus(lastCheckup, lastCleaning, today)
    val dates = listOfNotNull(s.checkupDue, s.cleaningDue)
    if (dates.isEmpty()) return null
    val first = dates.min()
    // Overdue: remind again in a week.
    return if (first.isAfter(today)) first else today.plusDays(7)
}

// ------------------------------------------------------------------ orthodontic mode, rewards

object Orthodontic {
    const val TARGET_S = 180.0
    val NOTE get() = tr("Fogszabályzóval a fogorvosok hosszabb, alaposabb fogmosást és a fogközök naponta többszöri tisztítását javasolják.")
}

data class RewardProgress(val have: Int, val need: Int, val text: String) {
    val done get() = have >= need
    val fraction get() = if (need <= 0) 1.0 else minOf(have.toDouble() / need, 1.0)
}

/** Parent-set reward (e.g. "Mozi") for N stickers collected since the reward was set. */
fun rewardProgress(rs: List<BrushRecord>, goals: Goals, reward: String?, need: Int, sinceMs: Long?, zone: ZoneId): RewardProgress? {
    if (reward.isNullOrBlank()) return null
    val coach = Coach(zone)
    val have = rs.filter { sinceMs == null || it.startMs >= sinceMs }.groupBy { coach.day(it) }.values.count { coach.isPerfectDay(it, goals) }
    return RewardProgress(minOf(have, need), need, reward)
}

// ------------------------------------------------------------------ dentist report

data class ReportSection(val title: String, val lines: List<String>)

data class DentistReport(val title: String, val subtitle: String, val sections: List<ReportSection>) {
    fun text() = buildString {
        append(title).append('\n').append(subtitle).append('\n')
        for (s in sections) {
            append('\n').append(s.title).append('\n')
            for (l in s.lines) append("• ").append(l).append('\n')
        }
    }.trimEnd()
}


fun dentistReport(
    profile: Profile, records: List<BrushRecord>, entries: List<CareEntry>, today: LocalDate, days: Int, zone: ZoneId,
    locale: WaterLocale = WaterLocale.HU,
): DentistReport {
    val start = today.minusDays(days - 1L)
    val coach = Coach(zone)
    val rs = records.filter { val d = coach.day(it); !d.isBefore(start) && !d.isAfter(today) }
    val es = entries.filter { val d = it.day(zone); !d.isBefore(start) && !d.isAfter(today) }
    val g = profile.goals
    val brushDays = rs.groupBy { coach.day(it) }
    val avg = if (rs.isEmpty()) 0.0 else rs.map { it.durationS }.average()
    val pct = if (rs.isEmpty()) 0 else (100.0 * rs.count { it.durationS >= g.targetS } / rs.size).roundToInt()
    val morning = rs.count { ReminderPlanner.inWindow(it.start(zone).toLocalTime(), ReminderPlanner.MORNING) }
    val evening = rs.count { ReminderPlanner.inWindow(it.start(zone).toLocalTime(), ReminderPlanner.EVENING) }
    val perfect = brushDays.values.count { coach.isPerfectDay(it, g) }
    val brushing = mutableListOf(
        tr("Fogmosások: {0} ({1} napon a {2} napból; reggel {3}, este {4})", rs.size, brushDays.size, days, morning, evening),
        tr("Átlagos időtartam: {0} (cél: {1}), célidőt elérte: {2}%", Formatting.clock(avg), Formatting.clock(g.targetS), pct),
        tr("Napi cél ({0}× {1}) teljesítve: {2} napon", g.perDay, Formatting.clock(g.targetS), perfect),
        tr("Elzárt csappal: {0} fogmosás", rs.count { it.tapOff }),
    )
    if (rs.isNotEmpty()) brushing += tr("Leghosszabb: {0}, legrövidebb: {1}", Formatting.clock(rs.maxOf { it.durationS }), Formatting.clock(rs.minOf { it.durationS }))

    fun c(k: CareKind) = careCount(es, k, today, days, zone)
    val cd = careDays(es, zone)
    val strong = cd.values.count { it.sensitivity >= 2 }
    val care = listOf(
        tr("Fogselyem: {0} napon", c(CareKind.FLOSS)),
        tr("Fogköztisztító kefe / szájzuhany: {0} napon", c(CareKind.INTERDENTAL)),
        tr("Szájvíz: {0} napon", c(CareKind.MOUTHWASH)),
        tr("Nyelvtisztítás: {0} napon", c(CareKind.TONGUE)),
    )
    val symptoms = mutableListOf(
        tr("Fogérzékenység: {0} napon", c(CareKind.SENSITIVITY)) + (if (strong > 0) tr(" (ebből erős: {0})", strong) else ""),
        tr("Ínyvérzés: {0} napon", c(CareKind.BLEEDING)),
    )
    val lastBleed = es.filter { it.bleeding }.maxByOrNull { it.dateMs }?.day(zone)
    if (lastBleed != null) symptoms += tr("Utolsó ínyvérzés: {0}", I18n.date(lastBleed))
    val pastes = cd.values.mapNotNull { it.toothpaste }.groupingBy { it }.eachCount().entries.sortedByDescending { it.value }
    if (pastes.isNotEmpty()) symptoms += tr("Fogkrém: ") + pastes.joinToString(", ") { tr("{0} ({1} nap)", Toothpastes.title(it.key), it.value) }

    val other = mutableListOf<String>()
    other += tr("Fogkefe: {0}", BrushTypes.title(profile.brushType))
    if (profile.orthodontic) other += tr("Fogszabályzó: igen")
    profile.lastCheckup?.let { other += tr("Utolsó fogorvosi kontroll: {0}", I18n.date(LocalDate.parse(it))) }
    profile.lastCleaning?.let { other += tr("Utolsó fogkőeltávolítás: {0}", I18n.date(LocalDate.parse(it))) }
    other += tr("Mérés: a telefon/óra mikrofonja alapján, a készüléken feldolgozva (hangfelvétel nem készül). A tüneteket a felhasználó jelölte.")

    return DentistReport(
        tr("Fogápolási jelentés – {0}", profile.name),
        tr("{0} – {1} ({2} nap)", I18n.date(start), I18n.date(today), days),
        listOf(ReportSection(tr("Fogmosás"), brushing), ReportSection(tr("Fogköztisztítás és kiegészítők"), care),
            ReportSection(tr("Tünetek"), symptoms), ReportSection(tr("Egyéb"), other)),
    )
}
