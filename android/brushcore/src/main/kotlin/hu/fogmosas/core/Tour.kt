package hu.fogmosas.core

/** "Mit tud az app?" tour pages. Same text as ios/BrushCore/.../Tour.swift. */
data class TourPage(val icon: String, val title: String, val text: String)

object Tour {
    /** platform: "ios" or "android". */
    fun pages(platform: String): List<TourPage> {
        val ios = platform == "ios"
        val live = if (ios) tr("a lezárt képernyőn és a Dynamic Islanden") else tr("az értesítésben és a lezárt képernyőn")
        val watch = if (ios) tr("Apple Watch-on is") else tr("Wear OS órán is")
        val complication = if (ios) tr("számlapelem") else "csempe"
        val auth = if (ios) tr("Face ID-val vagy Touch ID-val") else tr("ujjlenyomattal vagy arcfelismeréssel")
        return listOf(
            TourPage("🪥", tr("Magától méri a fogmosást"), tr("Tedd le a telefont a csap mellé, és kezdj fogat mosni. Az app a víz elzárásától az öblítésig méri az időt. Felismeri a kézi súrolást és az elektromos fogkefe zúgását is.")),
            TourPage("🚰", tr("Vigyáz a vízre"), tr("Ha fogmosás közben folyik a csap, figyelmeztető ikon jelenik meg, a végén pedig megtudod, hány liter víz folyt el, és mennyibe került.")),
            TourPage("📳", tr("Végigvezet a 2 percen"), tr("Félpercenként rezeg, hogy tudd, mikor válts a következő negyedre. A futó idő {0} is látszik.", live)),
            TourPage("⏰", tr("Emlékeztet"), tr("Lefekvés előtt 15 perccel, reggel ébredés után, és ha elmaradt, újra. Ha az emlékeztetőből nyitod meg, azonnal figyel.")),
            TourPage("📝", tr("Tünetnapló és fogselyem"), tr("Fogmosás után egy koppintással jelölheted, ha érzékeny volt a fogad vagy vérzett az ínyed, és ha fogselymeztél. Ha egy tünet tartós, szól, hogy nézz el a fogorvoshoz.")),
            TourPage("🦷", tr("Fogorvos"), tr("Félévente emlékeztet a kontrollra, évente a fogkőeltávolításra. A Statisztikában PDF-jelentést készíthetsz, amit megmutathatsz a fogorvosnak.")),
            TourPage("👨‍👩‍👧", tr("Az egész családnak"), tr("Gyerekprofilok saját avatarral; a még nem olvasó gyerekek képes felületet kapnak felolvasással. Matricát gyűjthetnek, a szülő jutalmat tűzhet ki.")),
            TourPage("🏅", tr("Célok és kitüntetések"), tr("Állítsd be, naponta hányszor és meddig mosol fogat. Sorozatokat és kitüntetéseket gyűjthetsz, és tippeket kapsz a fejlődéshez.")),
            TourPage("⌚", "$watch", tr("Az órán is elindíthatod a mérést; az eredmény átkerül a telefonra. A {0} egy pillantással mutatja a mai haladást.", complication)),
            TourPage("🌐", tr("Weben is"), tr("A Statisztikában beolvashatod a DentHub-Brush weboldal QR-kódját, és a számítógépen nagyobb képernyőn is látod az eredményeidet. Titkosítva, jelszó nélkül.")),
            TourPage("🔒", tr("Adatvédelem"), tr("Hangfelvétel nem készül: a hangot csak a telefon dolgozza fel, a memóriában. Az appot {0} zárolhatod, a beállításokat szülői zárral védheted.", auth)),
        )
    }
}
