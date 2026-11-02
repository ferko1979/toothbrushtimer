import Foundation

/// Family profiles, avatars and kid-friendly feedback (profiles.py, avatars.py).
public struct Avatar: Identifiable, Equatable {
    public let id: String
    public let emoji: String   // placeholder for the illustrated artwork
    public let label: String

    public static var all: [Avatar] { [
        Avatar(id: "lion", emoji: "🦁", label: tr("Oroszlán")), Avatar(id: "bear", emoji: "🐻", label: tr("Maci")),
        Avatar(id: "bunny", emoji: "🐰", label: tr("Nyuszi")), Avatar(id: "unicorn", emoji: "🦄", label: tr("Unikornis")),
        Avatar(id: "dog", emoji: "🐶", label: tr("Kutyus")), Avatar(id: "cat", emoji: "🐱", label: tr("Cica")),
        Avatar(id: "fox", emoji: "🦊", label: tr("Róka")), Avatar(id: "panda", emoji: "🐼", label: "Panda"),
        Avatar(id: "frog", emoji: "🐸", label: tr("Béka")), Avatar(id: "penguin", emoji: "🐧", label: tr("Pingvin")),
        Avatar(id: "dino", emoji: "🦖", label: tr("Dínó")), Avatar(id: "octopus", emoji: "🐙", label: tr("Polip")),
    ] }

    public static func emoji(for id: String?) -> String {
        guard let id = id, let a = all.first(where: { $0.id == id }) else { return "🧑" }
        return a.emoji
    }
}

public enum BrushType: String, Codable, CaseIterable { case manual, electric }

public struct Profile: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var child: Bool = false
    public var goals = Goals()
    public var brushType: BrushType = .manual
    public var age: Int? = nil
    public var canRead: Bool = true
    public var avatar: String? = nil
    public var brushHeadInstalled: Date = Date()
    public var calibration = BrushCalibration()
    public var orthodontic = false
    public var toothpaste: String? = nil
    public var lastCheckup: Date? = nil
    public var lastCleaning: Date? = nil
    public var reward: String? = nil          // parent-set reward for a child, e.g. "Mozi"
    public var rewardStickers = 14
    public var rewardSince: Date? = nil

    public init(id: String, name: String, child: Bool = false, age: Int? = nil, canRead: Bool = true,
                avatar: String? = nil, brushType: BrushType = .manual) {
        self.id = id; self.name = name; self.child = child; self.age = age
        self.canRead = canRead; self.avatar = avatar; self.brushType = brushType
    }

    public var avatarEmoji: String { Avatar.emoji(for: avatar) }

    // Older files: missing keys fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        child = try c.decodeIfPresent(Bool.self, forKey: .child) ?? false
        goals = try c.decodeIfPresent(Goals.self, forKey: .goals) ?? Goals()
        brushType = try c.decodeIfPresent(BrushType.self, forKey: .brushType) ?? .manual
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        canRead = try c.decodeIfPresent(Bool.self, forKey: .canRead) ?? true
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        brushHeadInstalled = try c.decodeIfPresent(Date.self, forKey: .brushHeadInstalled) ?? Date()
        calibration = try c.decodeIfPresent(BrushCalibration.self, forKey: .calibration) ?? BrushCalibration()
        orthodontic = try c.decodeIfPresent(Bool.self, forKey: .orthodontic) ?? false
        toothpaste = try c.decodeIfPresent(String.self, forKey: .toothpaste)
        lastCheckup = try c.decodeIfPresent(Date.self, forKey: .lastCheckup)
        lastCleaning = try c.decodeIfPresent(Date.self, forKey: .lastCleaning)
        reward = try c.decodeIfPresent(String.self, forKey: .reward)
        rewardStickers = try c.decodeIfPresent(Int.self, forKey: .rewardStickers) ?? 14
        rewardSince = try c.decodeIfPresent(Date.self, forKey: .rewardSince)
    }
}

public enum KidTitles {
    public static var map: [String: String] { [
        "first_brush": tr("Fogvédő tanonc"), "above_average": tr("Gyorsabb a cukorkaszörnynél"),
        "goal_reached": tr("Két perc hős"), "perfect_day": tr("Csillogó mosoly"),
        "streak_3": tr("Fogtündér barátja"), "streak_7": tr("Fogtündér kedvence"),
        "streak_30": tr("Fogkirály / Fogkirálynő"), "water_saver_10": tr("Vízcsepp-mentő"),
        "water_saver_50": tr("Óceán őrzője"), "improver": tr("Szintlépés"),
    ] }
}

public func achievementTitle(_ id: String, for profile: Profile) -> String {
    if profile.child, let t = KidTitles.map[id] { return t }
    return Achievements.byId(id)?.title ?? id
}

public struct Feedback: Equatable {
    public let text: String
    public let icons: String
    public let speak: Bool
}

public func childFeedbackText(durationS d: Double, goals: Goals) -> String {
    if d >= goals.targetS { return tr("Hurrá! Végig kitartottál, a fogaid ragyognak! ⭐ Kaptál egy matricát.") }
    if d >= goals.targetS / 2 { return tr("Ügyes vagy, már több mint félúton jártál! Legközelebb a végéig, és jár a matrica!") }
    return tr("Jó kezdés! A cukorkaszörnyek még bújkálnak. Holnap mosd tovább, amíg a kör be nem telik!")
}

public func feedback(for profile: Profile, durationS d: Double, coach: Coach = Coach()) -> Feedback {
    let g = profile.goals
    if !profile.child { return Feedback(text: coach.sessionFeedback(durationS: d, goals: g), icons: "", speak: false) }
    let stars = d >= g.targetS ? 3 : (d >= g.targetS / 2 ? 2 : 1)
    let icons = String(repeating: "⭐", count: stars) + (stars == 3 ? "🏅" : "")
    return Feedback(text: childFeedbackText(durationS: d, goals: g), icons: icons, speak: !profile.canRead)
}

/// One sticker per perfect day, a collectible figure per 7 stickers.
public func stickers(_ records: [BrushRecord], goals: Goals, coach: Coach = Coach()) -> (stickers: Int, figures: Int) {
    let days = Dictionary(grouping: records, by: { coach.calendar.startOfDay(for: $0.start) })
    let n = days.values.filter { coach.isPerfectDay($0, goals: goals) }.count
    return (n, n / 7)
}
