import Foundation

/// Family profiles, avatars and kid-friendly feedback (profiles.py, avatars.py).
public struct Avatar: Identifiable, Equatable {
    public let id: String
    public let emoji: String   // placeholder for the illustrated artwork
    public let label: String

    public static let all: [Avatar] = [
        Avatar(id: "lion", emoji: "🦁", label: "Oroszlán"), Avatar(id: "bear", emoji: "🐻", label: "Maci"),
        Avatar(id: "bunny", emoji: "🐰", label: "Nyuszi"), Avatar(id: "unicorn", emoji: "🦄", label: "Unikornis"),
        Avatar(id: "dog", emoji: "🐶", label: "Kutyus"), Avatar(id: "cat", emoji: "🐱", label: "Cica"),
        Avatar(id: "fox", emoji: "🦊", label: "Róka"), Avatar(id: "panda", emoji: "🐼", label: "Panda"),
        Avatar(id: "frog", emoji: "🐸", label: "Béka"), Avatar(id: "penguin", emoji: "🐧", label: "Pingvin"),
        Avatar(id: "dino", emoji: "🦖", label: "Dínó"), Avatar(id: "octopus", emoji: "🐙", label: "Polip"),
    ]

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

    public init(id: String, name: String, child: Bool = false, age: Int? = nil, canRead: Bool = true,
                avatar: String? = nil, brushType: BrushType = .manual) {
        self.id = id; self.name = name; self.child = child; self.age = age
        self.canRead = canRead; self.avatar = avatar; self.brushType = brushType
    }

    public var avatarEmoji: String { Avatar.emoji(for: avatar) }
}

public enum KidTitles {
    public static let map: [String: String] = [
        "first_brush": "Fogvédő tanonc", "above_average": "Gyorsabb a cukorkaszörnynél",
        "goal_reached": "Két perc hős", "perfect_day": "Csillogó mosoly",
        "streak_3": "Fogtündér barátja", "streak_7": "Fogtündér kedvence",
        "streak_30": "Fogkirály / Fogkirálynő", "water_saver_10": "Vízcsepp-mentő",
        "water_saver_50": "Óceán őrzője", "improver": "Szintlépés",
    ]
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
    if d >= goals.targetS { return "Hurrá! Végig kitartottál, a fogaid ragyognak! ⭐ Kaptál egy matricát." }
    if d >= goals.targetS / 2 { return "Ügyes vagy, már több mint félúton jártál! Legközelebb a végéig, és jár a matrica!" }
    return "Jó kezdés! A cukorkaszörnyek még bújkálnak. Holnap mosd tovább, amíg a kör be nem telik!"
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
