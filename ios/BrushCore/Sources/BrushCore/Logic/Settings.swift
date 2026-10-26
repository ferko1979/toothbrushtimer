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

    public static let all: [Feature] = [
        Feature("auto_detect", "Automatikus felismerés", "A víz, a súrolás és a szónikus zúgás alapján indul és áll le a mérés.", true, "Mérés"),
        Feature("keep_listening_when_placed", "Figyelés letett telefonnal", "Ha a telefon vízszintesen, nyugalomban fekszik, a képernyő lezárása után is figyel.", true, "Mérés", [.ios, .android]),
        Feature("calibration", "Kalibráció", "Az első 3 fogmosásból megtanulja a fogkeféd hangját.", true, "Mérés"),
        Feature("battery_saver", "Akkumulátorkímélő mód", "Csak akkor futtatja a felismerő modellt, ha egyáltalán hallatszik valami.", true, "Mérés"),
        Feature("quadrant_cues", "Rezgés a negyedeknél", "Indításkor, 30/60/90 másodpercnél és a célidőnél jelez.", true, "Fogmosás közben"),
        Feature("spoken_feedback", "Felolvasott visszajelzés", "Gyerekeknél felolvassa az üzeneteket.", true, "Fogmosás közben"),
        Feature("live_activity", "Élő kijelzés a lezárt képernyőn", "Élő tevékenység a lezárt képernyőn és a Dynamic Islanden.", true, "Fogmosás közben", [.ios, .android], available: false),
        Feature("water_warnings", "Vízpazarlás-figyelmeztetés", "Ikon, ha folyik a csap fogmosás közben, és összesítés a végén.", true, "Víz"),
        Feature("notifications", "Emlékeztetők", "Reggel, lefekvés előtt és ismétlés.", true, "Értesítések"),
        Feature("brush_head_reminder", "Fogkefecsere-emlékeztető", "3 havonta, illetve betegség után.", true, "Értesítések"),
        Feature("achievements", "Kitüntetések és sorozatok", "", true, "Motiváció"),
        Feature("habit_tips", "Szokás-tippek", "Figyelmeztet, ha visszatérő rossz szokást lát.", true, "Motiváció"),
        Feature("watch_complication", "Számlapelem az órán", "A sorozat és a mai haladás a számlapon.", true, "Motiváció", [.watchos, .wearos], available: false),
        Feature("floss_tracking", "Fogselyem követése", "Egy koppintással jelölheted fogmosás után (az ADA naponta egyszer javasolja).", false, "Kiegészítők"),
        Feature("mouthwash_tracking", "Szájvíz követése", "", false, "Kiegészítők"),
        Feature("voice_shortcuts", "Hangvezérlés", "„Hé Siri, fogmosás indul”.", true, "Kiegészítők"),
        Feature("health_sync", "Mentés az Egészség appba", "Apple Health: Fogmosás.", false, "Adatok", [.ios, .watchos]),
        Feature("monthly_report", "Havi összefoglaló", "Kinyomtatható, a fogorvosnak is megmutatható.", true, "Adatok"),
        Feature("family_sync", "Családi szinkron", "A gyerekek órája és a szülő telefonja között (iCloud, titkosítva).", false, "Adatok", available: false),
        Feature("data_donation", "Adatfelajánlás a fejlesztéshez", "Névtelen hangjellemzők (hangfelvétel nélkül) a felismerés javításához.", false, "Adatok", available: false),
    ]

    public static func byId(_ id: String) -> Feature? { all.first { $0.id == id } }
}

public struct AppSettings: Codable, Equatable {
    public var language = "hu"
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
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "hu"
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? "hu"
        tapFlowLPerMin = try c.decodeIfPresent(Double.self, forKey: .tapFlowLPerMin)
        reminders = try c.decodeIfPresent(ReminderSettings.self, forKey: .reminders) ?? ReminderSettings()
        let stored = try c.decodeIfPresent([String: Bool].self, forKey: .enabled) ?? [:]
        var e = Dictionary(uniqueKeysWithValues: Feature.all.map { ($0.id, $0.defaultOn) })
        for (k, v) in stored where e[k] != nil { e[k] = v }
        enabled = e
    }
}
