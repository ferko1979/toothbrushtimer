import Foundation

/// Goals, feedback, achievements (coach.py).
/// ADA: brush twice a day for two minutes. Average person: ~45 s;
/// 120 s removes ~26% more plaque than 45 s (Creeth et al. 2009).
public enum Recommendation {
    public static let perDay = 2
    public static let targetS = 120.0
    public static let populationAvgS = 45.0
    public static let quadrantS = 30.0
}

public struct Goals: Codable, Equatable {
    public var perDay: Int = Recommendation.perDay
    public var targetS: Double = Recommendation.targetS

    public init(perDay: Int = Recommendation.perDay, targetS: Double = Recommendation.targetS) {
        self.perDay = Swift.min(Swift.max(perDay, 1), 4)
        self.targetS = Swift.min(Swift.max(targetS, 30), 300)
    }

    public var warnings: [String] {
        var w: [String] = []
        if targetS < Recommendation.targetS {
            w.append("A fogorvosok legalább \(Int(Recommendation.targetS)) másodpercet javasolnak, a célod (\(Int(targetS)) s) ennél rövidebb.")
        }
        if perDay < Recommendation.perDay {
            w.append("A fogorvosok naponta kétszeri fogmosást javasolnak (reggel és lefekvés előtt).")
        }
        return w
    }
}

public struct BrushRecord: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var profileId: String
    public var start: Date
    public var durationS: Double
    public var waterRunningS: Double = 0
    public var source: String = "phone"  // "phone", "watch", "manual"
    public var brushF0: Double? = nil

    public init(profileId: String, start: Date, durationS: Double, waterRunningS: Double = 0,
                source: String = "phone", brushF0: Double? = nil) {
        self.profileId = profileId
        self.start = start
        self.durationS = durationS
        self.waterRunningS = waterRunningS
        self.source = source
        self.brushF0 = brushF0
    }

    public var tapOff: Bool { waterRunningS < 5 }
}

public struct Achievement: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
}

public enum Achievements {
    public static let all: [Achievement] = [
        Achievement(id: "first_brush", title: "Első lépés", description: "Az első mért fogmosás."),
        Achievement(id: "above_average", title: "Átlag felett", description: "Tovább mostál fogat, mint az átlagember (45 s)."),
        Achievement(id: "goal_reached", title: "Célba értél", description: "Először érted el a kitűzött fogmosási időt."),
        Achievement(id: "perfect_day", title: "Tökéletes nap", description: "Egy napon belül minden fogmosás elérte a célidőt."),
        Achievement(id: "streak_3", title: "Három nap sorban", description: "3 tökéletes nap egymás után."),
        Achievement(id: "streak_7", title: "Egy hét fegyelem", description: "7 tökéletes nap egymás után."),
        Achievement(id: "streak_30", title: "Egy hónap bajnok", description: "30 tökéletes nap egymás után."),
        Achievement(id: "water_saver_10", title: "Víztakarékos", description: "10 fogmosás elzárt csappal."),
        Achievement(id: "water_saver_50", title: "Vízőr", description: "50 fogmosás elzárt csappal."),
        Achievement(id: "improver", title: "Fejlődés", description: "A heti átlagod legalább 15 másodperccel jobb, mint az előző héten."),
    ]

    public static func byId(_ id: String) -> Achievement? { all.first { $0.id == id } }
}

public struct Coach {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) { self.calendar = calendar }

    public func sessionFeedback(durationS d: Double, goals: Goals) -> String {
        let t = goals.targetS
        if d >= t {
            var msg = "Szuper! \(Int(d.rounded())) másodperc, elérted a \(Int(t)) másodperces célt."
            if d > 2 * t {
                msg += " Nem kell ennél sokkal tovább: a túl hosszú, erős súrolás az ínyt is koptathatja."
            }
            return msg
        }
        let missing = t - d
        let quadrantsDone = Int(d / Recommendation.quadrantS)
        var msg = "\(Int(d.rounded())) másodperc, még \(Int(missing.rounded())) másodperc hiányzott a célhoz."
        if d >= Recommendation.populationAvgS {
            msg += " Ez már több az átlagos 45 másodpercnél, így tovább!"
        } else {
            msg += " Az átlagember kb. 45 másodpercig mos fogat. A 2 perces fogmosás kb. 26%-kal több lepedéket távolít el."
        }
        msg += " Tipp: mind a 4 fogsornegyedre jusson 30 másodperc (most kb. \(quadrantsDone) negyed jutott rá teljesen)."
        return msg
    }

    func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }

    func byDay(_ records: [BrushRecord]) -> [Date: [BrushRecord]] {
        Dictionary(grouping: records, by: { day($0.start) })
    }

    public func isPerfectDay(_ records: [BrushRecord], goals: Goals) -> Bool {
        records.filter { $0.durationS >= goals.targetS }.count >= goals.perDay
    }

    public func perfectStreak(_ records: [BrushRecord], goals: Goals, today: Date) -> Int {
        let days = byDay(records)
        var d = day(today)
        if !isPerfectDay(days[d] ?? [], goals: goals) {
            d = calendar.date(byAdding: .day, value: -1, to: d)!
        }
        var n = 0
        while isPerfectDay(days[d] ?? [], goals: goals) {
            n += 1
            d = calendar.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }

    func weekAverage(_ records: [BrushRecord], start: Date) -> Double? {
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let rs = records.filter { $0.start >= start && $0.start < end }.map(\.durationS)
        return rs.isEmpty ? nil : rs.reduce(0, +) / Double(rs.count)
    }

    public func earnedAchievements(_ records: [BrushRecord], goals: Goals, today: Date) -> Set<String> {
        var out = Set<String>()
        guard !records.isEmpty else { return out }
        out.insert("first_brush")
        if records.contains(where: { $0.durationS >= Recommendation.populationAvgS }) { out.insert("above_average") }
        if records.contains(where: { $0.durationS >= goals.targetS }) { out.insert("goal_reached") }
        let perfect = byDay(records).filter { isPerfectDay($0.value, goals: goals) }.keys.sorted()
        if !perfect.isEmpty { out.insert("perfect_day") }
        var best = 0, run = 0
        var prev: Date?
        for d in perfect {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = Swift.max(best, run)
            prev = d
        }
        for n in [3, 7, 30] where best >= n { out.insert("streak_\(n)") }
        let saved = records.filter(\.tapOff).count
        if saved >= 10 { out.insert("water_saver_10") }
        if saved >= 50 { out.insert("water_saver_50") }
        let thisWeek = calendar.date(byAdding: .day, value: -6, to: day(today))!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek)!
        if let a = weekAverage(records, start: thisWeek), let b = weekAverage(records, start: lastWeek), a - b >= 15 {
            out.insert("improver")
        }
        return out
    }

    public func dailySummary(_ records: [BrushRecord], goals: Goals, today: Date) -> String {
        let rs = byDay(records)[day(today)] ?? []
        let good = rs.filter { $0.durationS >= goals.targetS }.count
        let left = Swift.max(goals.perDay - rs.count, 0)
        let streak = perfectStreak(records, goals: goals, today: today)
        var parts = ["Ma: \(rs.count)/\(goals.perDay) fogmosás, ebből \(good) érte el a \(Int(goals.targetS)) s-ot."]
        if left > 0 {
            parts.append("Még \(left) fogmosás van hátra mára.")
        } else if good >= goals.perDay {
            parts.append("Tökéletes nap! 🎉")
        }
        if streak >= 2 { parts.append("\(streak) tökéletes nap sorozatban.") }
        return parts.joined(separator: " ")
    }

    public func weeklyProgress(_ records: [BrushRecord], goals: Goals, today: Date) -> String {
        let thisWeek = calendar.date(byAdding: .day, value: -6, to: day(today))!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek)!
        guard let a = weekAverage(records, start: thisWeek) else { return "Ezen a héten még nincs mért fogmosás." }
        var msg = "Heti átlag: \(Int(a.rounded())) s (cél: \(Int(goals.targetS)) s)."
        if let b = weekAverage(records, start: lastWeek) {
            let diff = a - b
            if diff >= 5 {
                msg += " \(Int(diff.rounded())) másodperccel jobb, mint a múlt héten, szép fejlődés!"
            } else if diff <= -5 {
                msg += " \(Int((-diff).rounded())) másodperccel kevesebb, mint a múlt héten. Próbáld meg a negyedenkénti jelzést követni!"
            } else {
                msg += " Nagyjából ugyanannyi, mint a múlt héten."
            }
        }
        if a < goals.targetS { msg += " Átlagban még \(Int((goals.targetS - a).rounded())) másodperc hiányzik a célhoz." }
        return msg
    }

    public func todayCount(_ records: [BrushRecord], today: Date) -> Int {
        (byDay(records)[day(today)] ?? []).count
    }
}
