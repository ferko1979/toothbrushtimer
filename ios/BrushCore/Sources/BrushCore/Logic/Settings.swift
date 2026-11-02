import Foundation

/// Every optional feature as an on/off switch (settings.py). The Settings
/// screen is generated from `Feature.all`.
public enum Platform: String, Codable, CaseIterable { case ios, watchos, android, wearos }

public struct Feature: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let defaultOn: Bool
    public let group: String
    public let platforms: [Platform]
    /// Built in this version of the app (others are shown as "hamarosan").
    public let available: Bool

    init(_ id: String, _ title: String, _ description: String, _ defaultOn: Bool, _ group: String,
         _ platforms: [Platform] = Platform.allCases, available: Bool = true) {
        self.id = id; self.title = title; self.description = description
        self.defaultOn = defaultOn; self.group = group; self.platforms = platforms; self.available = available
    }

    public static var all: [Feature] { [
        Feature("auto_detect", tr("Automatikus felismerés"), tr("A víz, a súrolás és a szónikus zúgás alapján indul és áll le a mérés."), true, tr("Mérés")),
        Feature("keep_listening_when_placed", tr("Figyelés letett telefonnal"), tr("Ha a telefon vízszintesen, nyugalomban fekszik, a képernyő lezárása után is figyel."), true, tr("Mérés"), [.ios, .android]),
        Feature("calibration", tr("Kalibráció"), tr("Az első 3 fogmosásból megtanulja a fogkeféd hangját."), true, tr("Mérés")),
        Feature("battery_saver", tr("Akkumulátorkímélő mód"), tr("Csak akkor futtatja a felismerő modellt, ha egyáltalán hallatszik valami."), true, tr("Mérés")),
        Feature("quadrant_cues", tr("Rezgés a negyedeknél"), tr("Indításkor, 30/60/90 másodpercnél és a célidőnél jelez."), true, tr("Fogmosás közben")),
        Feature("spoken_feedback", tr("Felolvasott visszajelzés"), tr("Gyerekeknél felolvassa az üzeneteket."), true, tr("Fogmosás közben")),
        Feature("live_activity", tr("Élő kijelzés a lezárt képernyőn"), tr("Élő tevékenység a lezárt képernyőn és a Dynamic Islanden."), true, tr("Fogmosás közben"), [.ios, .android]),
        Feature("water_warnings", tr("Vízpazarlás-figyelmeztetés"), tr("Ikon, ha folyik a csap fogmosás közben, és összesítés a végén."), true, tr("Víz")),
        Feature("notifications", tr("Emlékeztetők"), tr("Reggel, lefekvés előtt és ismétlés."), true, tr("Értesítések")),
        Feature("brush_head_reminder", tr("Fogkefecsere-emlékeztető"), tr("3 havonta, illetve betegség után."), true, tr("Értesítések")),
        Feature("dentist_reminders", tr("Fogorvosi kontroll emlékeztető"), tr("Félévente kontroll, évente fogkőeltávolítás."), true, tr("Értesítések")),
        Feature("achievements", tr("Kitüntetések és sorozatok"), "", true, tr("Motiváció")),
        Feature("kid_rewards", tr("Matricák és jutalmak gyerekeknek"), tr("A szülő jutalmat tűzhet ki adott számú matricáért."), true, tr("Motiváció")),
        Feature("family_overview", tr("Családi áttekintés"), tr("A szülő egy helyen látja a gyerekek eredményeit."), true, tr("Motiváció")),
        Feature("habit_tips", tr("Szokás-tippek"), tr("Figyelmeztet, ha visszatérő rossz szokást lát."), true, tr("Motiváció")),
        Feature("watch_complication", tr("Számlapelem az órán"), tr("A sorozat és a mai haladás a számlapon."), true, tr("Motiváció"), [.watchos, .wearos]),
        Feature("floss_tracking", tr("Fogselyem követése"), tr("Egy koppintással jelölheted fogmosás után (az ADA naponta egyszer javasolja)."), false, tr("Kiegészítők")),
        Feature("mouthwash_tracking", tr("Szájvíz követése"), "", false, tr("Kiegészítők")),
        Feature("interdental_tracking", tr("Fogköztisztító kefe / szájzuhany"), tr("Fogszabályzóval különösen fontos."), false, tr("Kiegészítők")),
        Feature("tongue_tracking", tr("Nyelvtisztítás"), "", false, tr("Kiegészítők")),
        Feature("voice_shortcuts", tr("Hangvezérlés"), tr("„Hé Siri, fogmosás indul”."), true, tr("Kiegészítők")),
        Feature("health_sync", tr("Mentés az Egészség appba"), tr("Apple Health: Fogmosás."), false, tr("Adatok"), [.ios, .watchos]),
        Feature("care_checkin", tr("Tünetnapló"), tr("Fogmosás után: érzékeny volt-e a fog, vérzett-e az íny. Statisztika és figyelmeztetés, ha tartós."), true, tr("Egészség")),
        Feature("toothpaste_tracking", tr("Fogkrém nyilvántartása"), tr("Látszik, segít-e az érzékeny fogra való fogkrém."), false, tr("Egészség")),
        Feature("monthly_report", tr("Havi összefoglaló"), tr("Kinyomtatható, a fogorvosnak is megmutatható."), true, tr("Adatok")),
        Feature("dentist_report", tr("Jelentés a fogorvosnak (PDF)"), tr("Fogmosás, fogselyem, tünetek az utóbbi 30/90 napból."), true, tr("Adatok")),
        Feature("web_link", tr("Webes megtekintés QR-kóddal"), tr("A weboldalon megjelenő QR-kódot beolvasva a statisztikád a böngészőben is látszik. Titkosítva, a szerver nem tárolja."), true, tr("Adatok"), [.ios, .android]),
        Feature("app_lock", tr("Zárolás Face ID-val / ujjlenyomattal"), tr("Megnyitáskor azonosítás kell."), false, tr("Adatvédelem"), [.ios, .android]),
        Feature("parent_lock", tr("Szülői zár"), tr("A Beállítások és a webes megosztás csak azonosítás után nyílik meg."), false, tr("Adatvédelem"), [.ios, .android]),
        Feature("family_sync", tr("Családi szinkron"), tr("A gyerekek órája és a szülő telefonja között (iCloud, titkosítva)."), false, tr("Adatok"), available: false),
        Feature("data_donation", tr("Adatfelajánlás a fejlesztéshez"), tr("Névtelen hangjellemzők (hangfelvétel nélkül) a felismerés javításához."), false, tr("Adatok"), available: false),
    ] }

    public static func byId(_ id: String) -> Feature? { all.first { $0.id == id } }
}

public struct AppSettings: Codable, Equatable {
    public var language = ""                 // "" = device language, "hu", "en"
    public var locale = "hu"                 // water units/prices: "hu" or "us"
    public var tapFlowLPerMin: Double? = nil // measured by the user
    public var reminders = ReminderSettings()
    public var enabled: [String: Bool] = Dictionary(uniqueKeysWithValues: Feature.all.map { ($0.id, $0.defaultOn) })

    public init() {}

    public func isOn(_ id: String, platform: Platform? = nil) -> Bool {
        guard let f = Feature.byId(id) else { return false }
        if let p = platform, !f.platforms.contains(p) { return false }
        if !f.available { return false }
        return enabled[id] ?? f.defaultOn
    }

    public mutating func set(_ id: String, _ on: Bool) {
        guard Feature.byId(id) != nil else { return }
        enabled[id] = on
    }

    public func groups(platform: Platform) -> [(String, [Feature])] {
        var order: [String] = []
        var map: [String: [Feature]] = [:]
        for f in Feature.all where f.platforms.contains(platform) {
            if map[f.group] == nil { order.append(f.group); map[f.group] = [] }
            map[f.group]?.append(f)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    public var waterLocale: WaterLocale { WaterLocale.named(locale).withFlow(tapFlowLPerMin) }

    // Older files: missing keys fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? ""
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? "hu"
        tapFlowLPerMin = try c.decodeIfPresent(Double.self, forKey: .tapFlowLPerMin)
        reminders = try c.decodeIfPresent(ReminderSettings.self, forKey: .reminders) ?? ReminderSettings()
        let stored = try c.decodeIfPresent([String: Bool].self, forKey: .enabled) ?? [:]
        var e = Dictionary(uniqueKeysWithValues: Feature.all.map { ($0.id, $0.defaultOn) })
        for (k, v) in stored where e[k] != nil { e[k] = v }
        enabled = e
    }
}
