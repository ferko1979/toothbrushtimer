package hu.fogmosas.core

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.ZoneId

data class Avatar(val id: String, val emoji: String, val label: String) {
    companion object {
        val all = listOf(
            Avatar("lion", "🦁", "Oroszlán"), Avatar("bear", "🐻", "Maci"), Avatar("bunny", "🐰", "Nyuszi"),
            Avatar("unicorn", "🦄", "Unikornis"), Avatar("dog", "🐶", "Kutyus"), Avatar("cat", "🐱", "Cica"),
            Avatar("fox", "🦊", "Róka"), Avatar("panda", "🐼", "Panda"), Avatar("frog", "🐸", "Béka"),
            Avatar("penguin", "🐧", "Pingvin"), Avatar("dino", "🦖", "Dínó"), Avatar("octopus", "🐙", "Polip"),
        )
        fun emoji(id: String?) = all.firstOrNull { it.id == id }?.emoji ?: "🧑"
    }
}

@Serializable
data class Profile(
    val id: String,
    val name: String,
    val child: Boolean = false,
    val goals: Goals = Goals(),
    val brushType: String = "manual",   // "manual" or "electric"
    val age: Int? = null,
    val canRead: Boolean = true,
    val avatar: String? = null,
    val brushHeadInstalled: String = LocalDate.now().toString(),
    val calibration: BrushCalibration = BrushCalibration(),
    val orthodontic: Boolean = false,
    val toothpaste: String? = null,
    val lastCheckup: String? = null,      // ISO date
    val lastCleaning: String? = null,     // ISO date
    val reward: String? = null,           // parent-set reward for a child, e.g. "Mozi"
    val rewardStickers: Int = 14,
    val rewardSinceMs: Long? = null,
) {
    val avatarEmoji get() = Avatar.emoji(avatar)
    val electric get() = brushType == "electric"
}

object KidTitles {
    val map = mapOf(
        "first_brush" to "Fogvédő tanonc", "above_average" to "Gyorsabb a cukorkaszörnynél",
        "goal_reached" to "Két perc hős", "perfect_day" to "Csillogó mosoly",
        "streak_3" to "Fogtündér barátja", "streak_7" to "Fogtündér kedvence",
        "streak_30" to "Fogkirály / Fogkirálynő", "water_saver_10" to "Vízcsepp-mentő",
        "water_saver_50" to "Óceán őrzője", "improver" to "Szintlépés",
    )
}

fun achievementTitle(id: String, p: Profile) =
    (if (p.child) KidTitles.map[id] else null) ?: Achievements.byId(id)?.title ?: id

data class Feedback(val text: String, val icons: String, val speak: Boolean)

fun childFeedbackText(d: Double, g: Goals) = when {
    d >= g.targetS -> "Hurrá! Végig kitartottál, a fogaid ragyognak! ⭐ Kaptál egy matricát."
    d >= g.targetS / 2 -> "Ügyes vagy, már több mint félúton jártál! Legközelebb a végéig, és jár a matrica!"
    else -> "Jó kezdés! A cukorkaszörnyek még bújkálnak. Holnap mosd tovább, amíg a kör be nem telik!"
}

fun feedbackFor(p: Profile, d: Double, coach: Coach = Coach()): Feedback {
    if (!p.child) return Feedback(coach.sessionFeedback(d, p.goals), "", false)
    val stars = if (d >= p.goals.targetS) 3 else if (d >= p.goals.targetS / 2) 2 else 1
    return Feedback(childFeedbackText(d, p.goals), "⭐".repeat(stars) + if (stars == 3) "🏅" else "", !p.canRead)
}

fun stickers(rs: List<BrushRecord>, goals: Goals, zone: ZoneId = ZoneId.systemDefault()): Pair<Int, Int> {
    val coach = Coach(zone)
    val n = rs.groupBy { coach.day(it) }.values.count { coach.isPerfectDay(it, goals) }
    return n to n / 7
}

/** First-run questions (onboarding.py). */
data class OnboardingQuestion(
    val id: String, val text: String, val kind: String,   // choice, text, number, avatar
    val options: List<Pair<String, String>> = emptyList(), val defaultValue: String? = null, val pictureOnly: Boolean = false,
)

class OnboardingFlow(var adultName: String = "Én") {
    private class Child(var name: String = "", var age: Int? = null, var canRead: Boolean? = null, var avatar: String? = null)

    private var mode: String? = null
    private val children = ArrayList<Child>()
    private var askMore = false
    private var done = false

    fun nextQuestion(): OnboardingQuestion? {
        val m = mode ?: return OnboardingQuestion("mode", "Egyedül használod az appot, vagy a gyerekeid fogmosását is mérnéd?",
            "choice", listOf("alone" to "Csak magamnak", "family" to "A gyerekeimnek is"))
        if (m == "alone" || done) return null
        if (askMore) return OnboardingQuestion("more", "Szeretnél még egy gyereket hozzáadni?", "choice", listOf("yes" to "Igen", "no" to "Nem, kész"))
        val c = children.last()
        if (c.name.isEmpty()) return OnboardingQuestion("child_name", "Hogy hívják a gyermeked?", "text")
        val age = c.age ?: return OnboardingQuestion("child_age", "Hány éves ${c.name}?", "number")
        val reads = c.canRead ?: return OnboardingQuestion("child_reads", "Tud már ${c.name} önállóan olvasni?", "choice",
            listOf("yes" to "Igen", "no" to "Még nem"), if (age < 6) "no" else null)
        val taken = children.dropLast(1).mapNotNull { it.avatar }.toSet()
        return OnboardingQuestion("child_avatar", if (reads) "${c.name}, válaszd ki a képedet! Erről fogod megismerni magad." else "",
            "avatar", Avatar.all.filter { it.id !in taken }.map { it.id to it.emoji }, null, !reads)
    }

    fun answer(value: String) {
        val q = nextQuestion() ?: throw IllegalStateException("finished")
        when (q.id) {
            "mode" -> {
                require(value == "alone" || value == "family") { "invalid" }
                mode = value
                if (value == "family") children += Child()
            }
            "more" -> if (value == "yes") { children += Child(); askMore = false } else done = true
            "child_name" -> { require(value.isNotBlank()) { "empty" }; children.last().name = value.trim() }
            "child_age" -> {
                val a = value.toIntOrNull()
                require(a != null && a in 1..17) { "age" }
                children.last().age = a
                if (a >= 9) children.last().canRead = true
            }
            "child_reads" -> children.last().canRead = value == "yes"
            "child_avatar" -> {
                require(q.options.any { it.first == value }) { "avatar" }
                children.last().avatar = value
                askMore = true
            }
        }
    }

    fun profiles(): List<Profile> {
        val out = mutableListOf(Profile("me", adultName))
        children.filter { it.avatar != null }.forEachIndexed { i, c ->
            out += Profile("child${i + 1}", c.name, child = true, age = c.age, canRead = c.canRead ?: false, avatar = c.avatar)
        }
        return out
    }
}

/** Every optional feature as a switch (settings.py). */
data class Feature(
    val id: String, val title: String, val description: String, val defaultOn: Boolean, val group: String,
    val platforms: Set<String> = setOf("ios", "watchos", "android", "wearos"), val available: Boolean = true,
) {
    companion object {
        val all = listOf(
            Feature("auto_detect", "Automatikus felismerés", "A víz, a súrolás és a szónikus zúgás alapján indul és áll le a mérés.", true, "Mérés"),
            Feature("keep_listening_when_placed", "Figyelés letett telefonnal", "Ha a telefon vízszintesen, nyugalomban fekszik, a képernyő lezárása után is figyel.", true, "Mérés", setOf("ios", "android")),
            Feature("calibration", "Kalibráció", "Az első 3 fogmosásból megtanulja a fogkeféd hangját.", true, "Mérés"),
            Feature("battery_saver", "Akkumulátorkímélő mód", "Csak akkor futtatja a felismerő modellt, ha egyáltalán hallatszik valami.", true, "Mérés"),
            Feature("quadrant_cues", "Rezgés a negyedeknél", "Indításkor, 30/60/90 másodpercnél és a célidőnél jelez.", true, "Fogmosás közben"),
            Feature("spoken_feedback", "Felolvasott visszajelzés", "Gyerekeknél felolvassa az üzeneteket.", true, "Fogmosás közben"),
            Feature("live_activity", "Élő kijelzés a lezárt képernyőn", "Folyamatos értesítés fogmosás közben.", true, "Fogmosás közben", setOf("ios", "android"), available = false),
            Feature("water_warnings", "Vízpazarlás-figyelmeztetés", "Ikon, ha folyik a csap fogmosás közben, és összesítés a végén.", true, "Víz"),
            Feature("notifications", "Emlékeztetők", "Reggel, lefekvés előtt és ismétlés.", true, "Értesítések"),
            Feature("brush_head_reminder", "Fogkefecsere-emlékeztető", "3 havonta, illetve betegség után.", true, "Értesítések"),
            Feature("dentist_reminders", "Fogorvosi kontroll emlékeztető", "Félévente kontroll, évente fogkőeltávolítás.", true, "Értesítések"),
            Feature("achievements", "Kitüntetések és sorozatok", "", true, "Motiváció"),
            Feature("kid_rewards", "Matricák és jutalmak gyerekeknek", "A szülő jutalmat tűzhet ki adott számú matricáért.", true, "Motiváció"),
            Feature("family_overview", "Családi áttekintés", "A szülő egy helyen látja a gyerekek eredményeit.", true, "Motiváció"),
            Feature("habit_tips", "Szokás-tippek", "Figyelmeztet, ha visszatérő rossz szokást lát.", true, "Motiváció"),
            Feature("watch_complication", "Számlapelem az órán", "A sorozat és a mai haladás a számlapon.", true, "Motiváció", setOf("watchos", "wearos"), available = false),
            Feature("floss_tracking", "Fogselyem követése", "Egy koppintással jelölheted fogmosás után (az ADA naponta egyszer javasolja).", false, "Kiegészítők"),
            Feature("mouthwash_tracking", "Szájvíz követése", "", false, "Kiegészítők"),
            Feature("interdental_tracking", "Fogköztisztító kefe / szájzuhany", "Fogszabályzóval különösen fontos.", false, "Kiegészítők"),
            Feature("tongue_tracking", "Nyelvtisztítás", "", false, "Kiegészítők"),
            Feature("voice_shortcuts", "Hangvezérlés", "„Hé Google, fogmosás indítása”.", true, "Kiegészítők", available = false),
            Feature("health_sync", "Mentés az Egészség appba", "Apple Health: Fogmosás.", false, "Adatok", setOf("ios", "watchos")),
            Feature("care_checkin", "Tünetnapló", "Fogmosás után: érzékeny volt-e a fog, vérzett-e az íny. Statisztika és figyelmeztetés, ha tartós.", true, "Egészség"),
            Feature("toothpaste_tracking", "Fogkrém nyilvántartása", "Látszik, segít-e az érzékeny fogra való fogkrém.", false, "Egészség"),
            Feature("monthly_report", "Havi összefoglaló", "Kinyomtatható, a fogorvosnak is megmutatható.", true, "Adatok"),
            Feature("dentist_report", "Jelentés a fogorvosnak (PDF)", "Fogmosás, fogselyem, tünetek az utóbbi 30/90 napból.", true, "Adatok"),
            Feature("web_link", "Webes megtekintés QR-kóddal", "A weboldalon megjelenő QR-kódot beolvasva a statisztikád a böngészőben is látszik. Titkosítva, a szerver nem tárolja.", true, "Adatok", setOf("ios", "android")),
            Feature("app_lock", "Zárolás Face ID-val / ujjlenyomattal", "Megnyitáskor azonosítás kell.", false, "Adatvédelem", setOf("ios", "android")),
            Feature("parent_lock", "Szülői zár", "A Beállítások és a webes megosztás csak azonosítás után nyílik meg.", false, "Adatvédelem", setOf("ios", "android")),
            Feature("family_sync", "Családi szinkron", "A gyerekek órája és a szülő telefonja között.", false, "Adatok", available = false),
            Feature("data_donation", "Adatfelajánlás a fejlesztéshez", "Névtelen hangjellemzők (hangfelvétel nélkül).", false, "Adatok", available = false),
        )
        fun byId(id: String) = all.firstOrNull { it.id == id }
    }
}

@Serializable
data class AppSettings(
    val locale: String = "hu",
    val tapFlowLPerMin: Double? = null,
    val reminders: ReminderSettings = ReminderSettings(),
    val enabled: Map<String, Boolean> = Feature.all.associate { it.id to it.defaultOn },
) {
    fun isOn(id: String, platform: String? = null): Boolean {
        val f = Feature.byId(id) ?: return false
        if (platform != null && platform !in f.platforms) return false
        if (!f.available) return false
        return enabled[id] ?: f.defaultOn
    }

    fun with(id: String, on: Boolean) = if (Feature.byId(id) == null) this else copy(enabled = enabled + (id to on))

    fun groups(platform: String): List<Pair<String, List<Feature>>> =
        Feature.all.filter { platform in it.platforms }.groupBy { it.group }.toList()

    val waterLocale get() = WaterLocale.named(locale).withFlow(tapFlowLPerMin)
}
