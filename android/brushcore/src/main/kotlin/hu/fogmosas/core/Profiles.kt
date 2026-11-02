package hu.fogmosas.core

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.ZoneId

data class Avatar(val id: String, val emoji: String, val label: String) {
    companion object {
        val all get() = listOf(
            Avatar("lion", "🦁", tr("Oroszlán")), Avatar("bear", "🐻", tr("Maci")), Avatar("bunny", "🐰", tr("Nyuszi")),
            Avatar("unicorn", "🦄", tr("Unikornis")), Avatar("dog", "🐶", tr("Kutyus")), Avatar("cat", "🐱", tr("Cica")),
            Avatar("fox", "🦊", tr("Róka")), Avatar("panda", "🐼", "Panda"), Avatar("frog", "🐸", tr("Béka")),
            Avatar("penguin", "🐧", tr("Pingvin")), Avatar("dino", "🦖", tr("Dínó")), Avatar("octopus", "🐙", tr("Polip")),
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
    val map get() = mapOf(
        "first_brush" to tr("Fogvédő tanonc"), "above_average" to tr("Gyorsabb a cukorkaszörnynél"),
        "goal_reached" to tr("Két perc hős"), "perfect_day" to tr("Csillogó mosoly"),
        "streak_3" to tr("Fogtündér barátja"), "streak_7" to tr("Fogtündér kedvence"),
        "streak_30" to tr("Fogkirály / Fogkirálynő"), "water_saver_10" to tr("Vízcsepp-mentő"),
        "water_saver_50" to tr("Óceán őrzője"), "improver" to tr("Szintlépés"),
    )
}

fun achievementTitle(id: String, p: Profile) =
    (if (p.child) KidTitles.map[id] else null) ?: Achievements.byId(id)?.title ?: id

data class Feedback(val text: String, val icons: String, val speak: Boolean)

fun childFeedbackText(d: Double, g: Goals) = when {
    d >= g.targetS -> tr("Hurrá! Végig kitartottál, a fogaid ragyognak! ⭐ Kaptál egy matricát.")
    d >= g.targetS / 2 -> tr("Ügyes vagy, már több mint félúton jártál! Legközelebb a végéig, és jár a matrica!")
    else -> tr("Jó kezdés! A cukorkaszörnyek még bújkálnak. Holnap mosd tovább, amíg a kör be nem telik!")
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

class OnboardingFlow(var adultName: String = tr("Én")) {
    private class Child(var name: String = "", var age: Int? = null, var canRead: Boolean? = null, var avatar: String? = null)

    private var mode: String? = null
    private val children = ArrayList<Child>()
    private var askMore = false
    private var done = false

    fun nextQuestion(): OnboardingQuestion? {
        val m = mode ?: return OnboardingQuestion("mode", tr("Egyedül használod az appot, vagy a gyerekeid fogmosását is mérnéd?"),
            "choice", listOf("alone" to tr("Csak magamnak"), "family" to tr("A gyerekeimnek is")))
        if (m == "alone" || done) return null
        if (askMore) return OnboardingQuestion("more", tr("Szeretnél még egy gyereket hozzáadni?"), "choice", listOf("yes" to tr("Igen"), "no" to tr("Nem, kész")))
        val c = children.last()
        if (c.name.isEmpty()) return OnboardingQuestion("child_name", tr("Hogy hívják a gyermeked?"), "text")
        val age = c.age ?: return OnboardingQuestion("child_age", tr("Hány éves {0}?", c.name), "number")
        val reads = c.canRead ?: return OnboardingQuestion("child_reads", tr("Tud már {0} önállóan olvasni?", c.name), "choice",
            listOf("yes" to tr("Igen"), "no" to tr("Még nem")), if (age < 6) "no" else null)
        val taken = children.dropLast(1).mapNotNull { it.avatar }.toSet()
        return OnboardingQuestion("child_avatar", if (reads) tr("{0}, válaszd ki a képedet! Erről fogod megismerni magad.", c.name) else "",
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
        val all get() = listOf(
            Feature("auto_detect", tr("Automatikus felismerés"), tr("A víz, a súrolás és a szónikus zúgás alapján indul és áll le a mérés."), true, tr("Mérés")),
            Feature("keep_listening_when_placed", tr("Figyelés letett telefonnal"), tr("Ha a telefon vízszintesen, nyugalomban fekszik, a képernyő lezárása után is figyel."), true, tr("Mérés"), setOf("ios", "android")),
            Feature("calibration", tr("Kalibráció"), tr("Az első 3 fogmosásból megtanulja a fogkeféd hangját."), true, tr("Mérés")),
            Feature("battery_saver", tr("Akkumulátorkímélő mód"), tr("Csak akkor futtatja a felismerő modellt, ha egyáltalán hallatszik valami."), true, tr("Mérés")),
            Feature("quadrant_cues", tr("Rezgés a negyedeknél"), tr("Indításkor, 30/60/90 másodpercnél és a célidőnél jelez."), true, tr("Fogmosás közben")),
            Feature("spoken_feedback", tr("Felolvasott visszajelzés"), tr("Gyerekeknél felolvassa az üzeneteket."), true, tr("Fogmosás közben")),
            Feature("live_activity", tr("Élő kijelzés a lezárt képernyőn"), tr("Futó idő és haladás az értesítésben és a lezárt képernyőn."), true, tr("Fogmosás közben"), setOf("ios", "android")),
            Feature("water_warnings", tr("Vízpazarlás-figyelmeztetés"), tr("Ikon, ha folyik a csap fogmosás közben, és összesítés a végén."), true, tr("Víz")),
            Feature("notifications", tr("Emlékeztetők"), tr("Reggel, lefekvés előtt és ismétlés."), true, tr("Értesítések")),
            Feature("brush_head_reminder", tr("Fogkefecsere-emlékeztető"), tr("3 havonta, illetve betegség után."), true, tr("Értesítések")),
            Feature("dentist_reminders", tr("Fogorvosi kontroll emlékeztető"), tr("Félévente kontroll, évente fogkőeltávolítás."), true, tr("Értesítések")),
            Feature("achievements", tr("Kitüntetések és sorozatok"), "", true, tr("Motiváció")),
            Feature("kid_rewards", tr("Matricák és jutalmak gyerekeknek"), tr("A szülő jutalmat tűzhet ki adott számú matricáért."), true, tr("Motiváció")),
            Feature("family_overview", tr("Családi áttekintés"), tr("A szülő egy helyen látja a gyerekek eredményeit."), true, tr("Motiváció")),
            Feature("habit_tips", tr("Szokás-tippek"), tr("Figyelmeztet, ha visszatérő rossz szokást lát."), true, tr("Motiváció")),
            Feature("watch_complication", tr("Számlapelem az órán"), tr("A sorozat és a mai haladás a számlapon."), true, tr("Motiváció"), setOf("watchos", "wearos")),
            Feature("floss_tracking", tr("Fogselyem követése"), tr("Egy koppintással jelölheted fogmosás után (az ADA naponta egyszer javasolja)."), false, tr("Kiegészítők")),
            Feature("mouthwash_tracking", tr("Szájvíz követése"), "", false, tr("Kiegészítők")),
            Feature("interdental_tracking", tr("Fogköztisztító kefe / szájzuhany"), tr("Fogszabályzóval különösen fontos."), false, tr("Kiegészítők")),
            Feature("tongue_tracking", tr("Nyelvtisztítás"), "", false, tr("Kiegészítők")),
            Feature("voice_shortcuts", tr("Gyorsindítás és hangvezérlés"), tr("Hosszan nyomd meg az app ikonját: „Fogmosás indítása”. Vagy: „Hé Google, nyisd meg a Fogmosást”."), true, tr("Kiegészítők")),
            Feature("health_sync", tr("Mentés az Egészség appba"), tr("Apple Health: Fogmosás."), false, tr("Adatok"), setOf("ios", "watchos")),
            Feature("care_checkin", tr("Tünetnapló"), tr("Fogmosás után: érzékeny volt-e a fog, vérzett-e az íny. Statisztika és figyelmeztetés, ha tartós."), true, tr("Egészség")),
            Feature("toothpaste_tracking", tr("Fogkrém nyilvántartása"), tr("Látszik, segít-e az érzékeny fogra való fogkrém."), false, tr("Egészség")),
            Feature("monthly_report", tr("Havi összefoglaló"), tr("Kinyomtatható, a fogorvosnak is megmutatható."), true, tr("Adatok")),
            Feature("dentist_report", tr("Jelentés a fogorvosnak (PDF)"), tr("Fogmosás, fogselyem, tünetek az utóbbi 30/90 napból."), true, tr("Adatok")),
            Feature("web_link", tr("Webes megtekintés QR-kóddal"), tr("A weboldalon megjelenő QR-kódot beolvasva a statisztikád a böngészőben is látszik. Titkosítva, a szerver nem tárolja."), true, tr("Adatok"), setOf("ios", "android")),
            Feature("app_lock", tr("Zárolás Face ID-val / ujjlenyomattal"), tr("Megnyitáskor azonosítás kell."), false, tr("Adatvédelem"), setOf("ios", "android")),
            Feature("parent_lock", tr("Szülői zár"), tr("A Beállítások és a webes megosztás csak azonosítás után nyílik meg."), false, tr("Adatvédelem"), setOf("ios", "android")),
            Feature("family_sync", tr("Családi szinkron"), tr("A gyerekek órája és a szülő telefonja között."), false, tr("Adatok"), available = false),
            Feature("data_donation", tr("Adatfelajánlás a fejlesztéshez"), tr("Névtelen hangjellemzők (hangfelvétel nélkül)."), false, tr("Adatok"), available = false),
        )
        fun byId(id: String) = all.firstOrNull { it.id == id }
    }
}

@Serializable
data class AppSettings(
    val language: String = "",          // "" = device language, "hu", "en"
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
