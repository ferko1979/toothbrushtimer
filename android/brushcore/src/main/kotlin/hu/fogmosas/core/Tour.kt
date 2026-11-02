package hu.fogmosas.core

/** "Mit tud az app?" tour pages. Same text as ios/BrushCore/.../Tour.swift. */
data class TourPage(val icon: String, val title: String, val text: String)

object Tour {
    /** platform: "ios" or "android". */
    fun pages(platform: String): List<TourPage> {
        val ios = platform == "ios"
        val live = if (ios) "a lezárt képernyőn és a Dynamic Islanden" else "az értesítésben és a lezárt képernyőn"
        val watch = if (ios) "Apple Watch-on is" else "Wear OS órán is"
        val complication = if (ios) "számlapelem" else "csempe"
        val auth = if (ios) "Face ID-val vagy Touch ID-val" else "ujjlenyomattal vagy arcfelismeréssel"
        return listOf(
            TourPage("🪥", "Magától méri a fogmosást", "Tedd le a telefont a csap mellé, és kezdj fogat mosni. Az app a víz elzárásától az öblítésig méri az időt. Felismeri a kézi súrolást és az elektromos fogkefe zúgását is."),
            TourPage("🚰", "Vigyáz a vízre", "Ha fogmosás közben folyik a csap, figyelmeztető ikon jelenik meg, a végén pedig megtudod, hány liter víz folyt el, és mennyibe került."),
            TourPage("📳", "Végigvezet a 2 percen", "Félpercenként rezeg, hogy tudd, mikor válts a következő negyedre. A futó idő $live is látszik."),
            TourPage("⏰", "Emlékeztet", "Lefekvés előtt 15 perccel, reggel ébredés után, és ha elmaradt, újra. Ha az emlékeztetőből nyitod meg, azonnal figyel."),
            TourPage("📝", "Tünetnapló és fogselyem", "Fogmosás után egy koppintással jelölheted, ha érzékeny volt a fogad vagy vérzett az ínyed, és ha fogselymeztél. Ha egy tünet tartós, szól, hogy nézz el a fogorvoshoz."),
            TourPage("🦷", "Fogorvos", "Félévente emlékeztet a kontrollra, évente a fogkőeltávolításra. A Statisztikában PDF-jelentést készíthetsz, amit megmutathatsz a fogorvosnak."),
            TourPage("👨‍👩‍👧", "Az egész családnak", "Gyerekprofilok saját avatarral; a még nem olvasó gyerekek képes felületet kapnak felolvasással. Matricát gyűjthetnek, a szülő jutalmat tűzhet ki."),
            TourPage("🏅", "Célok és kitüntetések", "Állítsd be, naponta hányszor és meddig mosol fogat. Sorozatokat és kitüntetéseket gyűjthetsz, és tippeket kapsz a fejlődéshez."),
            TourPage("⌚", "$watch", "Az órán is elindíthatod a mérést; az eredmény átkerül a telefonra. A $complication egy pillantással mutatja a mai haladást."),
            TourPage("🌐", "Weben is", "A Statisztikában beolvashatod a Fogmosás weboldal QR-kódját, és a számítógépen nagyobb képernyőn is látod az eredményeidet. Titkosítva, jelszó nélkül."),
            TourPage("🔒", "Adatvédelem", "Hangfelvétel nem készül: a hangot csak a telefon dolgozza fel, a memóriában. Az appot $auth zárolhatod, a beállításokat szülői zárral védheted."),
        )
    }
}
