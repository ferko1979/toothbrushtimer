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
        let live = ios ? "a lezárt képernyőn és a Dynamic Islanden" : "az értesítésben és a lezárt képernyőn"
        let watch = ios ? "Apple Watch-on is" : "Wear OS órán is"
        let complication = ios ? "számlapelem" : "csempe"
        let auth = ios ? "Face ID-val vagy Touch ID-val" : "ujjlenyomattal vagy arcfelismeréssel"
        return [
            TourPage(icon: "🪥", title: "Magától méri a fogmosást", text: "Tedd le a telefont a csap mellé, és kezdj fogat mosni. Az app a víz elzárásától az öblítésig méri az időt. Felismeri a kézi súrolást és az elektromos fogkefe zúgását is."),
            TourPage(icon: "🚰", title: "Vigyáz a vízre", text: "Ha fogmosás közben folyik a csap, figyelmeztető ikon jelenik meg, a végén pedig megtudod, hány liter víz folyt el, és mennyibe került."),
            TourPage(icon: "📳", title: "Végigvezet a 2 percen", text: "Félpercenként rezeg, hogy tudd, mikor válts a következő negyedre. A futó idő \(live) is látszik."),
            TourPage(icon: "⏰", title: "Emlékeztet", text: "Lefekvés előtt 15 perccel, reggel ébredés után, és ha elmaradt, újra. Ha az emlékeztetőből nyitod meg, azonnal figyel."),
            TourPage(icon: "📝", title: "Tünetnapló és fogselyem", text: "Fogmosás után egy koppintással jelölheted, ha érzékeny volt a fogad vagy vérzett az ínyed, és ha fogselymeztél. Ha egy tünet tartós, szól, hogy nézz el a fogorvoshoz."),
            TourPage(icon: "🦷", title: "Fogorvos", text: "Félévente emlékeztet a kontrollra, évente a fogkőeltávolításra. A Statisztikában PDF-jelentést készíthetsz, amit megmutathatsz a fogorvosnak."),
            TourPage(icon: "👨‍👩‍👧", title: "Az egész családnak", text: "Gyerekprofilok saját avatarral; a még nem olvasó gyerekek képes felületet kapnak felolvasással. Matricát gyűjthetnek, a szülő jutalmat tűzhet ki."),
            TourPage(icon: "🏅", title: "Célok és kitüntetések", text: "Állítsd be, naponta hányszor és meddig mosol fogat. Sorozatokat és kitüntetéseket gyűjthetsz, és tippeket kapsz a fejlődéshez."),
            TourPage(icon: "⌚", title: "\(watch)", text: "Az órán is elindíthatod a mérést; az eredmény átkerül a telefonra. A \(complication) egy pillantással mutatja a mai haladást."),
            TourPage(icon: "🌐", title: "Weben is", text: "A Statisztikában beolvashatod a Fogmosás weboldal QR-kódját, és a számítógépen nagyobb képernyőn is látod az eredményeidet. Titkosítva, jelszó nélkül."),
            TourPage(icon: "🔒", title: "Adatvédelem", text: "Hangfelvétel nem készül: a hangot csak a telefon dolgozza fel, a memóriában. Az appot \(auth) zárolhatod, a beállításokat szülői zárral védheted."),
        ]
    }
}
