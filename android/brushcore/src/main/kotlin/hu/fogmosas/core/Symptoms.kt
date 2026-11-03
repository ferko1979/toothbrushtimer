package hu.fogmosas.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Base64
import java.util.UUID

// Complaints, step-by-step questions, triage, the doctor's summary, visit requests and the linked
// clinic. Same as ios/BrushCore/.../Symptoms.swift (tests: SymptomsTest.kt / SymptomsTests.swift).
// The advice is general first aid and guidance, not a diagnosis.

/** One recorded complaint with the answers to its questions. */
@Serializable
data class SymptomReport(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    val dateMs: Long,
    val kind: String,
    /** question id -> chosen option ids */
    val answers: Map<String, List<String>> = emptyMap(),
    val level: String,
    /** File names of the photos in the app's photo folder. */
    val photos: List<String> = emptyList(),
    val note: String = "",
    val sentMs: Long? = null,
    /** "message" (clinic inbox) or "email" */
    val sentVia: String? = null,
)

data class SymptomOption(val id: String, val label: String)
data class SymptomQuestion(val id: String, val title: String, val options: List<SymptomOption>, val multi: Boolean = false)

enum class TriageLevel(val id: String, val rank: Int) {
    SELF_CARE("self_care", 0), MONITOR("monitor", 1), SOON("soon", 2), URGENT("urgent", 3), EMERGENCY("emergency", 4);

    val title get() = when (this) {
        SELF_CARE -> tr("Otthon kezelhető")
        MONITOR -> tr("Figyeld meg")
        SOON -> tr("Pár napon belül nézesse meg a fogorvos")
        URGENT -> tr("Még ma keresd a fogorvosodat")
        EMERGENCY -> tr("Azonnali ellátás kell")
    }
    val emoji get() = when (this) { SELF_CARE -> "🟢"; MONITOR -> "🟡"; SOON -> "🟠"; URGENT -> "🔴"; EMERGENCY -> "🚨" }

    companion object { fun byId(id: String) = entries.firstOrNull { it.id == id } ?: MONITOR }
}

data class TriageResult(
    val level: TriageLevel,
    val advice: List<String>,
    /** What to photograph, or null when a photo does not help. */
    val photo: String?,
    val suggestMessage: Boolean,
    val suggestBooking: Boolean,
)

object Symptoms {
    data class Kind(val id: String, val emoji: String, val title: String)

    val kinds get() = listOf(
        Kind("bleeding", "🩸", tr("Vérzik az ínyem")),
        Kind("pain", "😖", tr("Fáj a fogam")),
        Kind("sensitivity", "🥶", tr("Érzékeny a fogam")),
        Kind("swelling", "😮", tr("Duzzanat (íny, arc)")),
        Kind("stuck", "🦴", tr("Valami beszorult a fogaim közé")),
        Kind("chipped", "🦷", tr("Letört egy darab (fog, tömés, korona)")),
        Kind("knocked", "💥", tr("Kiesett egy fogam (baleset)")),
        Kind("loose", "〰️", tr("Mozog egy fogam")),
        Kind("sore", "⚪", tr("Afta vagy seb a számban")),
        Kind("injury", "🩹", tr("Ráharaptam / megsérült a szám")),
        Kind("jaw", "🫦", tr("Állkapocs, rágás közbeni fájdalom")),
        Kind("breath", "💨", tr("Rossz lehelet vagy rossz íz")),
        Kind("braces", "🔩", tr("Fogszabályzó gond")),
        Kind("other", "📝", tr("Egyéb")),
    )

    fun kind(id: String) = kinds.firstOrNull { it.id == id } ?: kinds.last()

    private fun o(id: String, label: String) = SymptomOption(id, label)
    private val yesNo get() = listOf(o("yes", tr("Igen")), o("no", tr("Nem")))

    /** Every question; [questionsFor] picks the ones a complaint needs. */
    fun question(id: String): SymptomQuestion = when (id) {
        "jaw" -> SymptomQuestion(id, tr("Melyik fogsoron?"), listOf(o("upper", tr("Felső")), o("lower", tr("Alsó")), o("both", tr("Mindkettő")), o("unsure", tr("Nem tudom"))))
        "side" -> SymptomQuestion(id, tr("Melyik oldalon?"), listOf(o("left", tr("Bal")), o("right", tr("Jobb")), o("front", tr("Elöl")), o("several", tr("Több helyen"))))
        "zone" -> SymptomQuestion(id, tr("Melyik fogaknál?"), listOf(o("front", tr("Elülső fogak")), o("middle", tr("Szemfog, kisőrlők")), o("back", tr("Hátsó őrlőfogak")), o("unsure", tr("Nem tudom"))))
        "pain" -> SymptomQuestion(id, tr("Mennyire fáj?"), listOf(o("none", tr("Nem fáj")), o("mild", tr("Enyhén")), o("moderate", tr("Közepesen")), o("severe", tr("Erősen")), o("unbearable", tr("Elviselhetetlenül"))))
        "since" -> SymptomQuestion(id, tr("Mióta tart?"), listOf(o("today", tr("Ma kezdődött")), o("days", tr("Pár napja")), o("week", tr("Egy hete vagy régebben")), o("recurring", tr("Visszatérő"))))
        "trigger" -> SymptomQuestion(id, tr("Mikor érzed? (több is lehet)"), listOf(o("cold", tr("Hidegre")), o("hot", tr("Melegre")), o("sweet", tr("Édesre")), o("chewing", tr("Rágáskor, harapáskor")), o("spontaneous", tr("Magától is")), o("night", tr("Éjjel"))), multi = true)
        "bleed_when" -> SymptomQuestion(id, tr("Mikor vérzik? (több is lehet)"), listOf(o("brushing", tr("Fogmosáskor")), o("flossing", tr("Fogselyemnél")), o("eating", tr("Evéskor")), o("spontaneous", tr("Magától"))), multi = true)
        "bleed_amount" -> SymptomQuestion(id, tr("Mennyire vérzik?"), listOf(o("drops", tr("Pár csepp")), o("lot", tr("Sokat")), o("nonstop", tr("Nem áll el"))))
        "swelling_also" -> SymptomQuestion(id, tr("Duzzadt is a környéke?"), yesNo)
        "swell_where" -> SymptomQuestion(id, tr("Hol duzzadt? (több is lehet)"), listOf(o("gum", tr("Íny")), o("face", tr("Arc")), o("lip", tr("Ajak")), o("under_jaw", tr("Áll alatt, nyakon"))), multi = true)
        "fever" -> SymptomQuestion(id, tr("Lázas vagy, rossz a közérzeted?"), yesNo)
        "breathing" -> SymptomQuestion(id, tr("Nehezen nyelsz vagy veszel levegőt?"), yesNo)
        "stuck_tried" -> SymptomQuestion(id, tr("Próbáltad már fogselyemmel vagy fogközkefével?"), listOf(o("still", tr("Igen, de még ott van")), o("not_yet", tr("Még nem"))))
        "what_broke" -> SymptomQuestion(id, tr("Mi tört le?"), listOf(o("tooth", tr("Fog")), o("filling", tr("Tömés")), o("crown", tr("Korona, híd")), o("denture", tr("Fogsor"))))
        "sharp" -> SymptomQuestion(id, tr("Éles a széle, sérti a nyelved vagy az arcod?"), yesNo)
        "piece" -> SymptomQuestion(id, tr("Megvan a letört darab?"), yesNo)
        "tooth_type" -> SymptomQuestion(id, tr("Milyen fog esett ki?"), listOf(o("permanent", tr("Maradó fog (felnőtt)")), o("baby", tr("Tejfog (gyerek)"))))
        "minutes" -> SymptomQuestion(id, tr("Mennyi ideje történt?"), listOf(o("lt30", tr("Fél órán belül")), o("lt60", tr("Fél–egy órája")), o("gt60", tr("Több mint egy órája"))))
        "wound_bleed" -> SymptomQuestion(id, tr("Elállt a vérzés (10–15 perc nyomás után)?"), listOf(o("stopped", tr("Igen")), o("slowing", tr("Csillapodik")), o("not_stopping", tr("Nem áll el")), o("none", tr("Nem vérzett"))))
        "wound_deep" -> SymptomQuestion(id, tr("Mély vagy 1 cm-nél hosszabb a seb?"), yesNo)
        "injury_cause" -> SymptomQuestion(id, tr("Mi történt?"), listOf(o("bite", tr("Ráharaptam")), o("hit", tr("Ütés, esés")), o("burn", tr("Megégettem (forró étel)")), o("wire", tr("Fogszabályzó drót sértette"))))
        "sore_where" -> SymptomQuestion(id, tr("Hol van?"), listOf(o("tongue", tr("Nyelv")), o("cheek", tr("Arc belső oldala")), o("gum", tr("Íny")), o("lip", tr("Ajak")), o("palate", tr("Szájpadlás"))))
        "sore_weeks" -> SymptomQuestion(id, tr("Mióta van?"), listOf(o("lt1", tr("Egy hétnél rövidebb ideje")), o("1to2", tr("1–2 hete")), o("gt2", tr("Több mint 2 hete"))))
        "loose_cause" -> SymptomQuestion(id, tr("Mi okozhatta?"), listOf(o("injury", tr("Ütés, baleset")), o("slowly", tr("Lassan kezdett mozogni")), o("changing", tr("Gyerek, fogváltás"))))
        "jaw_sym" -> SymptomQuestion(id, tr("Mit érzel? (több is lehet)"), listOf(o("click", tr("Kattog, ropog")), o("chew_pain", tr("Rágáskor fáj")), o("open", tr("Nem tudom nagyra nyitni")), o("morning", tr("Reggel fáj, fogcsikorgatás"))), multi = true)
        "taste" -> SymptomQuestion(id, tr("Rossz ízt vagy gennyet érzel a szádban?"), yesNo)
        "teeth" -> SymptomQuestion(id, tr("Melyik fog? Koppints rá (több is lehet)"),
            ToothMap.all.map { o(it, it) } + o("unsure", tr("Nem tudom / kihagyom")), multi = true)
        "braces_issue" -> SymptomQuestion(id, tr("Mi a gond?"), listOf(o("wire", tr("Szúr a drót")), o("bracket", tr("Levált egy bracket")), o("adjust", tr("Fáj az utánállítás után")), o("aligner", tr("Eltört a sín, aligner"))))
        else -> throw IllegalArgumentException(id)
    }

    /** The questions of a complaint, in order; later ones may depend on earlier answers. */
    fun questionsFor(kind: String, a: Map<String, List<String>>, child: Boolean = false): List<String> {
        fun yes(q: String) = a[q]?.contains("yes") == true
        val qs = when (kind) {
            "bleeding" -> listOf("jaw", "side", "bleed_when", "bleed_amount", "since")
            "pain" -> listOf("jaw", "side", "zone", "pain", "trigger", "since", "swelling_also") +
                (if (yes("swelling_also")) listOf("fever", "breathing") else emptyList())
            "sensitivity" -> listOf("jaw", "side", "trigger", "since")
            "swelling" -> listOf("swell_where", "jaw", "side", "pain", "fever", "breathing")
            "stuck" -> listOf("jaw", "side", "stuck_tried", "pain")
            "chipped" -> listOf("what_broke", "jaw", "side", "zone", "pain", "sharp", "piece")
            "knocked" -> listOf("tooth_type", "minutes", "wound_bleed")
            "loose" -> listOf("loose_cause", "jaw", "side", "pain")
            "sore" -> listOf("sore_where", "sore_weeks", "pain")
            "injury" -> listOf("injury_cause", "sore_where", "wound_bleed", "wound_deep", "pain")
            "jaw" -> listOf("jaw_sym", "side", "since")
            "breath" -> listOf("since", "taste")
            "braces" -> listOf("braces_issue", "pain")
            else -> listOf("since", "pain")
        }
        // Tooth map after the "where" questions (adult teeth only).
        if (child || kind !in ToothMap.kinds) return qs
        val after = qs.indexOf(if ("zone" in qs) "zone" else "side")
        return qs.take(after + 1) + "teeth" + qs.drop(after + 1)
    }

    /** A short label of a question for the summary ("Fogsor: Felső"). */
    fun shortLabel(q: String) = when (q) {
        "jaw" -> tr("Fogsor"); "side" -> tr("Oldal"); "zone" -> tr("Fogak"); "pain" -> tr("Fájdalom")
        "since" -> tr("Mióta"); "trigger" -> tr("Kiváltó ok"); "bleed_when" -> tr("Mikor vérzik")
        "bleed_amount" -> tr("Vérzés mértéke"); "swelling_also" -> tr("Duzzanat"); "swell_where" -> tr("Duzzanat helye")
        "fever" -> tr("Láz, rossz közérzet"); "breathing" -> tr("Nyelési/légzési nehézség"); "stuck_tried" -> tr("Fogselyem")
        "what_broke" -> tr("Mi tört le"); "sharp" -> tr("Éles szél"); "piece" -> tr("Megvan a darab")
        "tooth_type" -> tr("Fog"); "minutes" -> tr("Ideje"); "wound_bleed" -> tr("Vérzés")
        "wound_deep" -> tr("Mély seb"); "injury_cause" -> tr("Ok"); "sore_where" -> tr("Hely")
        "sore_weeks" -> tr("Mióta"); "loose_cause" -> tr("Ok"); "jaw_sym" -> tr("Tünetek")
        "taste" -> tr("Rossz íz, genny"); "braces_issue" -> tr("Gond"); "teeth" -> tr("Fog (FDI)")
        else -> q
    }
}

/** Step by step: complaint, then its questions; [result] once [next] is null. */
class SymptomFlow(
    /** The same complaint in the last 30 days (before this one). */
    val recentSameKind: (String) -> Int = { 0 },
    val child: Boolean = false,
) {
    var kind: String? = null; private set
    val answers = LinkedHashMap<String, List<String>>()

    fun next(): SymptomQuestion? {
        val k = kind ?: return SymptomQuestion("kind", tr("Mi a gond?"), Symptoms.kinds.map { SymptomOption(it.id, "${it.emoji} ${it.title}") })
        val id = Symptoms.questionsFor(k, answers, child).firstOrNull { it !in answers } ?: return null
        return Symptoms.question(id)
    }

    fun answer(ids: List<String>) {
        val q = next() ?: throw IllegalStateException("finished")
        require(ids.isNotEmpty() && ids.all { id -> q.options.any { it.id == id } }) { "invalid answer" }
        if (q.id == "kind") { kind = ids.first(); answers.clear() } else answers[q.id] = if (q.multi) ids else ids.take(1)
    }

    /** One step back; false when already at the first question. */
    fun back(): Boolean {
        if (answers.isNotEmpty()) { answers.remove(answers.keys.last()); return true }
        if (kind != null) { kind = null; return true }
        return false
    }

    /** 0…1 for a progress bar. */
    val progress: Double get() {
        val k = kind ?: return 0.0
        val total = Symptoms.questionsFor(k, answers, child).size + 1
        return (answers.size + 1).toDouble() / total
    }

    fun result(): TriageResult = triage(kind ?: "other", answers, kind?.let(recentSameKind) ?: 0, child)

    fun report(profileId: String, nowMs: Long, photos: List<String> = emptyList(), note: String = "") =
        SymptomReport(profileId = profileId, dateMs = nowMs, kind = kind ?: "other", answers = LinkedHashMap(answers),
            level = result().level.id, photos = photos, note = note)
}

/** Rules behind the advice. Order: emergencies first, then the complaint, then pain and recurrence. */
fun triage(kind: String, a: Map<String, List<String>>, recentSameKind: Int = 0, child: Boolean = false): TriageResult {
    fun has(q: String, v: String) = a[q]?.contains(v) == true
    var level = TriageLevel.SELF_CARE
    val advice = ArrayList<String>()
    var photo: String? = null
    fun atLeast(l: TriageLevel) { if (l.rank > level.rank) level = l }
    val closePhoto = tr("Fotózd le közelről, jó fényben (pl. a telefon lámpájával).")

    if (has("breathing", "yes")) {
        atLeast(TriageLevel.EMERGENCY)
        advice += tr("Duzzanat mellett nehezített nyelés vagy légzés: azonnal hívd a 112-t, vagy menj sürgősségi ügyeletre!")
    }
    if (has("fever", "yes")) {
        atLeast(TriageLevel.URGENT)
        advice += tr("Láz és duzzanat együtt fertőzésre utalhat: még ma beszélj a fogorvosoddal vagy az ügyelettel.")
    }

    when (kind) {
        "bleeding" -> {
            when {
                has("bleed_amount", "nonstop") -> { atLeast(TriageLevel.URGENT); advice += tr("Nyomd tiszta gézzel 10–15 percig. Ha így sem áll el, keresd még ma a fogorvost vagy az ügyeletet.") }
                has("bleed_amount", "lot") || has("bleed_when", "spontaneous") -> atLeast(TriageLevel.SOON)
                has("since", "week") || has("since", "recurring") -> atLeast(TriageLevel.SOON)
            }
            advice += tr("Ínyvérzésnél is moss fogat: puha fogkefével, gyengéden, az ínyszélnél is, és használj naponta fogselymet.")
            advice += tr("A gyulladt íny 1–2 hét rendszeres tisztítással általában megnyugszik. Ha nem, nézesse meg a fogorvos.")
        }
        "pain" -> {
            if (has("trigger", "spontaneous") || has("trigger", "night")) {
                atLeast(TriageLevel.URGENT)
                advice += tr("A magától vagy éjjel jelentkező fogfájás gyulladásra utalhat: még ma keresd a fogorvosodat.")
            } else if (a["trigger"].orEmpty().all { it == "cold" || it == "sweet" } && (has("pain", "mild") || has("pain", "none"))) {
                advice += tr("Rövid, hidegre vagy édesre jelentkező fájdalom gyakran érzékenység: próbálj érzékeny fogakra való fogkrémet.")
            }
            if (has("swelling_also", "yes")) { atLeast(TriageLevel.URGENT); photo = tr("Fotózd le a duzzadt részt és az arcod szemből.") }
            if (has("trigger", "chewing")) advice += tr("Ha harapáskor fáj, rágj a másik oldalon, és kerüld a kemény ételt.")
            advice += tr("Fájdalomcsillapítót csak a betegtájékoztató szerint szedj. Ne melegítsd az arcod, és ne tegyél gyógyszert közvetlenül az ínyre.")
        }
        "sensitivity" -> {
            if (has("since", "week") || has("since", "recurring") || has("trigger", "spontaneous")) atLeast(TriageLevel.SOON)
            advice += tr("Használj érzékeny fogakra való fogkrémet, és moss puha fogkefével, erős nyomás nélkül.")
            advice += tr("Savas étel vagy ital után várj fél órát a fogmosással.")
        }
        "swelling" -> {
            if (has("swell_where", "face") || has("swell_where", "under_jaw")) {
                atLeast(TriageLevel.URGENT)
                photo = tr("Fotózd le az arcod szemből és oldalról.")
            } else {
                atLeast(TriageLevel.SOON)
                photo = closePhoto
            }
            advice += tr("Kívülről hideg borogatást tehetsz rá (10 perc, aztán szünet). Ne melegítsd!")
        }
        "stuck" -> {
            if (has("stuck_tried", "still")) atLeast(TriageLevel.MONITOR)
            advice += tr("Óvatosan próbáld fogselyemmel vagy fogközkefével, és öblíts langyos sós vízzel.")
            advice += tr("Ne piszkáld hegyes tárggyal (fogpiszkáló, tű), mert megsértheted az ínyt.")
            advice += tr("Ha 1–2 nap múlva is ott van vagy fáj, nézesse meg a fogorvos.")
        }
        "chipped" -> {
            atLeast(TriageLevel.SOON)
            photo = closePhoto
            if (has("sharp", "yes")) advice += tr("Az éles szélre ideiglenesen tehetsz fogszabályzó-viaszt vagy cukormentes rágót, hogy ne sértse a nyelved.")
            if (has("piece", "yes")) advice += tr("A letört darabot tedd el tisztán, tejben vagy nedves tasakban, és vidd magaddal.")
            advice += tr("Rágj a másik oldalon, és kerüld a nagyon hideg, meleg vagy kemény ételt.")
        }
        "knocked" -> {
            if (has("tooth_type", "baby")) {
                atLeast(TriageLevel.SOON)
                advice += tr("Tejfogat ne próbálj visszahelyezni. Nyomd a sebet tiszta gézzel, és nézesse meg a fogorvos.")
            } else {
                atLeast(TriageLevel.EMERGENCY)
                advice += tr("A fogat a koronájánál fogd, ne a gyökerénél. Ha szennyezett, 10 másodpercig öblítsd tejjel vagy sós vízzel.")
                advice += tr("Ha tudod, óvatosan tedd vissza a helyére, és harapj rá egy gézre. Ha nem, tartsd tejben.")
                advice += tr("Azonnal indulj fogorvoshoz vagy ügyeletre: az első 30–60 perc a legfontosabb.")
            }
        }
        "loose" -> {
            when {
                has("loose_cause", "injury") -> { atLeast(TriageLevel.URGENT); advice += tr("Ütés után mozgó fogat még ma nézessen meg a fogorvos.") }
                has("loose_cause", "changing") || child -> advice += tr("Fogváltáskor a tejfog mozgása természetes. Hagyd, hogy magától kiessen.")
                else -> { atLeast(TriageLevel.SOON); advice += tr("Felnőttkorban a lassan meglazuló fog fogágybetegség jele lehet: kérj időpontot.") }
            }
        }
        "sore" -> {
            if (has("sore_weeks", "gt2")) {
                atLeast(TriageLevel.SOON)
                photo = closePhoto
                advice += tr("A 2 hétnél tovább tartó sebet mindenképp nézesse meg orvos.")
            } else {
                advice += tr("Az afta általában 7–14 nap alatt magától gyógyul. Öblíts sós vízzel, kerüld a fűszeres és savas ételt.")
                photo = closePhoto
            }
        }
        "injury" -> {
            photo = closePhoto
            if (has("wound_bleed", "not_stopping") || has("wound_deep", "yes")) {
                atLeast(TriageLevel.URGENT)
                advice += tr("Ha a vérzés 15 perc nyomás után sem áll el, vagy mély a seb, még ma keress orvost; varrni kellhet.")
            }
            when {
                has("injury_cause", "burn") -> advice += tr("Égésnél öblíts hideg vízzel, és egy-két napig egyél langyos, puha ételt.")
                has("injury_cause", "wire") -> { atLeast(TriageLevel.SOON); advice += tr("A szúró drótra tegyél fogszabályzó-viaszt, és szólj a fogszabályzó orvosodnak.") }
                has("injury_cause", "hit") -> { atLeast(TriageLevel.SOON); advice += tr("Ütés után nézd meg, nem mozog-e vagy tört-e le fog. Ha igen, menj fogorvoshoz még ma.") }
                else -> Unit
            }
            advice += tr("Öblíts langyos sós vízzel, nyomd tiszta gézzel 10–15 percig, kívülről tegyél rá hideg borogatást.")
            advice += tr("A kisebb harapásos seb pár nap alatt begyógyul. Ha nő, gennyes vagy nem javul, szólj az orvosodnak.")
        }
        "jaw" -> {
            atLeast(if (has("jaw_sym", "open")) TriageLevel.SOON else TriageLevel.MONITOR)
            advice += tr("Egyél puhább ételt, kerüld a rágógumit, és tegyél meleg borogatást a rágóizmokra.")
            if (has("jaw_sym", "morning")) advice += tr("A reggeli fájdalom éjszakai fogcsikorgatásra utalhat: kérdezd a fogorvosod a harapásemelő sínről.")
        }
        "breath" -> {
            if (has("taste", "yes")) { atLeast(TriageLevel.SOON); advice += tr("A rossz íz vagy genny fertőzésre utalhat: kérj időpontot.") }
            else if (has("since", "recurring") || has("since", "week")) atLeast(TriageLevel.SOON)
            advice += tr("Tisztítsd a nyelved is, használj fogselymet, és igyál elég vizet.")
        }
        "braces" -> {
            when {
                has("braces_issue", "adjust") -> advice += tr("Utánállítás után 2–3 napig normális a feszülő fájdalom. Egyél puha ételt.")
                has("braces_issue", "wire") -> { atLeast(TriageLevel.SOON); advice += tr("A szúró drótra tegyél fogszabályzó-viaszt, és szólj a fogszabályzó orvosodnak.") }
                else -> { atLeast(TriageLevel.SOON); advice += tr("Szólj a fogszabályzó orvosodnak; a levált darabot vagy a sínt tedd el.") }
            }
            photo = closePhoto
        }
        else -> atLeast(TriageLevel.MONITOR)
    }

    when {
        has("pain", "severe") || has("pain", "unbearable") -> atLeast(TriageLevel.URGENT)
        has("pain", "moderate") -> atLeast(TriageLevel.SOON)
    }
    if (recentSameKind >= 2) {
        atLeast(TriageLevel.SOON)
        advice += tr("30 napon belül már {0}. alkalommal jelzed ezt a panaszt: érdemes megnézetni.", recentSameKind + 1)
    }
    val serious = level.rank >= TriageLevel.SOON.rank
    return TriageResult(level, advice.distinct(), photo, suggestMessage = serious || kind == "other", suggestBooking = serious)
}

fun recentSymptomCount(reports: List<SymptomReport>, profileId: String, kind: String, nowMs: Long, days: Int = 30): Int =
    reports.count { it.profileId == profileId && it.kind == kind && nowMs - it.dateMs in 0..days * 86_400_000L }

/** Readable lines for the doctor (message, e-mail, report). */
fun symptomSummary(r: SymptomReport, zone: ZoneId = ZoneId.systemDefault()): List<String> {
    val k = Symptoms.kind(r.kind)
    val date = Instant.ofEpochMilli(r.dateMs).atZone(zone)
    val out = arrayListOf("${I18n.date(date.toLocalDate())} ${"%02d:%02d".format(date.hour, date.minute)} – ${k.emoji} ${k.title}")
    for ((q, ids) in r.answers) {
        val question = runCatching { Symptoms.question(q) }.getOrNull() ?: continue
        val labels = if (q == "teeth") ids.map { if (it == "unsure") tr("Nem tudom / kihagyom") else ToothMap.name(it) }
            else ids.mapNotNull { id -> question.options.firstOrNull { it.id == id }?.label }
        out += "${Symptoms.shortLabel(q)}: ${labels.joinToString(", ")}"
    }
    out += tr("Besorolás: {0}", TriageLevel.byId(r.level).title)
    if (r.note.isNotBlank()) out += tr("Megjegyzés: {0}", r.note.trim())
    if (r.photos.isNotEmpty()) out += tr("Fotók: {0} db", r.photos.size)
    return out
}

/** After a brushing: a reason to ask "Minden rendben?" (much shorter/longer than usual, or unusually often). */
fun brushingAnomaly(durationS: Double, recentDurations: List<Double>, todayCount: Int, perDay: Int): String? {
    if (recentDurations.size >= 5) {
        val m = Stats.median(recentDurations)
        if (durationS < 0.6 * m) return tr("Rövidebb volt a fogmosás a szokásosnál. Minden rendben?")
        if (durationS > 1.6 * m) return tr("Hosszabb volt a fogmosás a szokásosnál. Minden rendben?")
    }
    if (todayCount >= perDay + 2) return tr("Ma a szokásosnál többször mostál fogat. Minden rendben?")
    return null
}

// ------------------------------------------------------------------ dentist visit

object VisitReasons {
    val all get() = listOf(
        "checkup" to tr("Csak kontroll"),
        "cleaning" to tr("Fogkő-eltávolítás, tisztítás"),
        "pain" to tr("Fájdalom"),
        "bleeding" to tr("Ínyvérzés"),
        "broken" to tr("Letört fog vagy tömés"),
        "cosmetic" to tr("Esztétika, fehérítés"),
        "braces" to tr("Fogszabályozás"),
        "other" to tr("Egyéb ok"),
    )
    fun title(id: String) = all.firstOrNull { it.first == id }?.second ?: id
    val timings get() = listOf("asap" to tr("Amint lehet"), "week" to tr("A héten"), "month" to tr("Egy hónapon belül"), "any" to tr("Mindegy"))
    val dayParts get() = listOf("morning" to tr("Délelőtt"), "afternoon" to tr("Délután"), "evening" to tr("Este"))
}

@Serializable
data class VisitRequest(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    val createdMs: Long,
    val reason: String,
    val note: String = "",
    val timing: String = "any",
    val dayParts: List<String> = emptyList(),
    val symptomId: String? = null,
    val sentMs: Long? = null,
    val sentVia: String? = null,
)

fun visitText(v: VisitRequest, patientName: String, symptom: SymptomReport? = null): String = buildString {
    appendLine(tr("Időpontkérés – {0}", patientName))
    appendLine(tr("Ok: {0}", VisitReasons.title(v.reason)))
    appendLine(tr("Mikor: {0}", VisitReasons.timings.firstOrNull { it.first == v.timing }?.second ?: v.timing))
    if (v.dayParts.isNotEmpty()) appendLine(tr("Napszak: {0}", v.dayParts.mapNotNull { d -> VisitReasons.dayParts.firstOrNull { it.first == d }?.second }.joinToString(", ")))
    if (v.note.isNotBlank()) appendLine(tr("Megjegyzés: {0}", v.note.trim()))
    if (symptom != null) { appendLine(); symptomSummary(symptom).forEach { appendLine(it) } }
}.trimEnd()

/** Onboarding: "Mikor voltál utoljára fogorvosnál?" -> an approximate date. */
object DentistIntake {
    val options get() = listOf("lt6m" to tr("Fél éven belül"), "6to12" to tr("Fél–egy éve"), "gt1y" to tr("Több mint egy éve"), "unknown" to tr("Nem emlékszem"))
    fun date(option: String, today: LocalDate): LocalDate? = when (option) {
        "lt6m" -> today.minusMonths(3)
        "6to12" -> today.minusMonths(9)
        "gt1y" -> today.minusMonths(18)
        else -> null
    }
}

// ------------------------------------------------------------------ linked clinic

/** The clinic the patient linked in DentHub: shown next to the DentHub logo, gets messages and bookings. */
@Serializable
data class ClinicInfo(
    val id: String,
    val name: String,
    val logoUrl: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val bookingUrl: String? = null,
    val address: String? = null,
)

/** A message to the clinic. Delivered by DentHub once the account is linked; until then it waits ("queued"). */
@Serializable
data class ClinicMessage(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    val dateMs: Long,
    val text: String,
    val photos: List<String> = emptyList(),
    val symptomId: String? = null,
    val visitId: String? = null,
    val fromPatient: Boolean = true,
    val status: String = "queued",
)

private val linkJson = Json { ignoreUnknownKeys = true }

/**
 * The link code from the clinic (QR or text): `denthub://link?d=<base64url JSON of ClinicInfo>` or
 * `https://…/link#<same>`. Returns null when it is not a valid code.
 */
fun parseClinicLink(text: String): ClinicInfo? {
    val t = text.trim()
    val payload = when {
        t.startsWith("denthub://link?d=") -> t.removePrefix("denthub://link?d=")
        "/link#" in t -> t.substringAfter("/link#")
        else -> return null
    }
    return runCatching {
        val bytes = Base64.getUrlDecoder().decode(payload.trimEnd('='))
        linkJson.decodeFromString(ClinicInfo.serializer(), String(bytes, Charsets.UTF_8))
    }.getOrNull()?.takeIf { it.id.isNotBlank() && it.name.isNotBlank() }
}

fun clinicLinkCode(c: ClinicInfo): String =
    "denthub://link?d=" + Base64.getUrlEncoder().withoutPadding().encodeToString(linkJson.encodeToString(ClinicInfo.serializer(), c).toByteArray())

/** Booking link with the reason and timing, when the clinic has online booking. */
fun bookingLink(c: ClinicInfo, v: VisitRequest?): String? {
    val base = c.bookingUrl ?: return null
    if (v == null) return base
    val sep = if ('?' in base) '&' else '?'
    return "$base${sep}reason=${v.reason}&timing=${v.timing}"
}

/** E-mail to the clinic: subject and body. */
fun clinicEmail(patientName: String, symptom: SymptomReport?, visit: VisitRequest?): Pair<String, String> {
    val subject = when {
        symptom != null -> tr("DentHub-Brush: {0} – {1}", Symptoms.kind(symptom.kind).title, patientName)
        visit != null -> tr("DentHub-Brush: időpontkérés – {0}", patientName)
        else -> tr("DentHub-Brush: üzenet – {0}", patientName)
    }
    val body = buildString {
        appendLine(tr("Tisztelt Doktor Úr/Nő!"))
        appendLine()
        if (visit != null) { appendLine(visitText(visit, patientName, null)); appendLine() }
        symptom?.let { symptomSummary(it).forEach { line -> appendLine(line) } }
        appendLine()
        appendLine(tr("Üdvözlettel: {0}", patientName))
        appendLine(tr("(A DentHub-Brush appból küldve.)"))
    }.trimEnd()
    return subject to body
}
