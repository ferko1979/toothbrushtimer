import Foundation

/// "Mit tud az app?" tour pages. Same text as android/brushcore/.../Tour.kt.
public struct TourPage: Identifiable, Equatable {
    public let icon: String
    public let title: String
    public let text: String
    public var id: String { title }
}

public enum Tour {
    public static func pages(platform: Platform) -> [TourPage] {
        let ios = platform == .ios
        let live = ios ? tr("a lezárt képernyőn és a Dynamic Islanden") : tr("az értesítésben és a lezárt képernyőn")
        let watch = ios ? tr("Apple Watch-on is") : tr("Wear OS órán is")
        let complication = ios ? tr("számlapelem") : "csempe"
        let auth = ios ? tr("Face ID-val vagy Touch ID-val") : tr("ujjlenyomattal vagy arcfelismeréssel")
        return [
            TourPage(icon: "🪥", title: tr("Magától méri a fogmosást"), text: tr("Tedd le a telefont a csap mellé, és kezdj fogat mosni. Az app a víz elzárásától az öblítésig méri az időt. Felismeri a kézi súrolást és az elektromos fogkefe zúgását is.")),
            TourPage(icon: "🚰", title: tr("Vigyáz a vízre"), text: tr("Ha fogmosás közben folyik a csap, figyelmeztető ikon jelenik meg, a végén pedig megtudod, hány liter víz folyt el, és mennyibe került.")),
            TourPage(icon: "📳", title: tr("Végigvezet a 2 percen"), text: tr("Félpercenként rezeg, hogy tudd, mikor válts a következő negyedre. A futó idő {0} is látszik.", live)),
            TourPage(icon: "⏰", title: tr("Emlékeztet"), text: tr("Lefekvés előtt 15 perccel, reggel ébredés után, és ha elmaradt, újra. Ha az emlékeztetőből nyitod meg, azonnal figyel.")),
            TourPage(icon: "📝", title: tr("Tünetnapló és fogselyem"), text: tr("Fogmosás után egy koppintással jelölheted, ha érzékeny volt a fogad vagy vérzett az ínyed, és ha fogselymeztél. Ha egy tünet tartós, szól, hogy nézz el a fogorvoshoz.")),
            TourPage(icon: "🦷", title: tr("Fogorvos"), text: tr("Félévente emlékeztet a kontrollra, évente a fogkőeltávolításra. A Statisztikában PDF-jelentést készíthetsz, amit megmutathatsz a fogorvosnak.")),
            TourPage(icon: "👨‍👩‍👧", title: tr("Az egész családnak"), text: tr("Gyerekprofilok saját avatarral; a még nem olvasó gyerekek képes felületet kapnak felolvasással. Matricát gyűjthetnek, a szülő jutalmat tűzhet ki.")),
            TourPage(icon: "🏅", title: tr("Célok és kitüntetések"), text: tr("Állítsd be, naponta hányszor és meddig mosol fogat. Sorozatokat és kitüntetéseket gyűjthetsz, és tippeket kapsz a fejlődéshez.")),
            TourPage(icon: "⌚", title: "\(watch)", text: tr("Az órán is elindíthatod a mérést; az eredmény átkerül a telefonra. A {0} egy pillantással mutatja a mai haladást.", complication)),
            TourPage(icon: "🌐", title: tr("Weben is"), text: tr("A Statisztikában beolvashatod a DentHub-Brush weboldal QR-kódját, és a számítógépen nagyobb képernyőn is látod az eredményeidet. Titkosítva, jelszó nélkül.")),
            TourPage(icon: "🔒", title: tr("Adatvédelem"), text: tr("Hangfelvétel nem készül: a hangot csak a telefon dolgozza fel, a memóriában. Az appot {0} zárolhatod, a beállításokat szülői zárral védheted.", auth)),
        ]
    }
}
