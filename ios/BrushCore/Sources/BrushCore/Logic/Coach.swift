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
            w.append(tr("A fogorvosok legalább {0} másodpercet javasolnak, a célod ({1} s) ennél rövidebb.", Int(Recommendation.targetS), Int(targetS)))
        }
        if perDay < Recommendation.perDay {
            w.append(tr("A fogorvosok naponta kétszeri fogmosást javasolnak (reggel és lefekvés előtt)."))
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
    /// Loudness of the scrubbing (dBFS, median while brushing); for the "too hard" note.
    public var brushDb: Double? = nil

    public init(profileId: String, start: Date, durationS: Double, waterRunningS: Double = 0,
                source: String = "phone", brushF0: Double? = nil, brushDb: Double? = nil) {
        self.profileId = profileId
        self.start = start
        self.durationS = durationS
        self.waterRunningS = waterRunningS
        self.source = source
        self.brushF0 = brushF0
        self.brushDb = brushDb
    }

    public var tapOff: Bool { waterRunningS < 5 }
}

public struct Achievement: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
}

public enum Achievements {
    public static var all: [Achievement] { [
        Achievement(id: "first_brush", title: tr("Első lépés"), description: tr("Az első mért fogmosás.")),
        Achievement(id: "above_average", title: tr("Átlag felett"), description: tr("Tovább mostál fogat, mint az átlagember (45 s).")),
        Achievement(id: "goal_reached", title: tr("Célba értél"), description: tr("Először érted el a kitűzött fogmosási időt.")),
        Achievement(id: "perfect_day", title: tr("Tökéletes nap"), description: tr("Egy napon belül minden fogmosás elérte a célidőt.")),
        Achievement(id: "streak_3", title: tr("Három nap sorban"), description: tr("3 tökéletes nap egymás után.")),
        Achievement(id: "streak_7", title: tr("Egy hét fegyelem"), description: tr("7 tökéletes nap egymás után.")),
        Achievement(id: "streak_30", title: tr("Egy hónap bajnok"), description: tr("30 tökéletes nap egymás után.")),
        Achievement(id: "water_saver_10", title: tr("Víztakarékos"), description: tr("10 fogmosás elzárt csappal.")),
        Achievement(id: "water_saver_50", title: tr("Vízőr"), description: tr("50 fogmosás elzárt csappal.")),
        Achievement(id: "improver", title: tr("Fejlődés"), description: tr("A heti átlagod legalább 15 másodperccel jobb, mint az előző héten.")),
    ] }

    public static func byId(_ id: String) -> Achievement? { all.first { $0.id == id } }
}

public struct Coach {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) { self.calendar = calendar }

    public func sessionFeedback(durationS d: Double, goals: Goals) -> String {
        let t = goals.targetS
        if d >= t {
            var msg = tr("Szuper! {0} másodperc, elérted a {1} másodperces célt.", Int(d.rounded()), Int(t))
            if d > 2 * t {
                msg += tr(" Nem kell ennél sokkal tovább: a túl hosszú, erős súrolás az ínyt is koptathatja.")
            }
            return msg
        }
        let missing = t - d
        let quadrantsDone = Int(d / Recommendation.quadrantS)
        var msg = tr("{0} másodperc, még {1} másodperc hiányzott a célhoz.", Int(d.rounded()), Int(missing.rounded()))
        if d >= Recommendation.populationAvgS {
            msg += tr(" Ez már több az átlagos 45 másodpercnél, így tovább!")
        } else {
            msg += tr(" Az átlagember kb. 45 másodpercig mos fogat. A 2 perces fogmosás kb. 26%-kal több lepedéket távolít el.")
        }
        msg += tr(" Tipp: mind a 4 fogsornegyedre jusson 30 másodperc (most kb. {0} negyed jutott rá teljesen).", quadrantsDone)
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
        var parts = [tr("Ma: {0}/{1} fogmosás, ebből {2} érte el a {3} s-ot.", rs.count, goals.perDay, good, Int(goals.targetS))]
        if left > 0 {
            parts.append(tr("Még {0} fogmosás van hátra mára.", left))
        } else if good >= goals.perDay {
            parts.append(tr("Tökéletes nap! 🎉"))
        }
        if streak >= 2 { parts.append(tr("{0} tökéletes nap sorozatban.", streak)) }
        return parts.joined(separator: " ")
    }

    public func weeklyProgress(_ records: [BrushRecord], goals: Goals, today: Date) -> String {
        let thisWeek = calendar.date(byAdding: .day, value: -6, to: day(today))!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek)!
        guard let a = weekAverage(records, start: thisWeek) else { return tr("Ezen a héten még nincs mért fogmosás.") }
        var msg = tr("Heti átlag: {0} s (cél: {1} s).", Int(a.rounded()), Int(goals.targetS))
        if let b = weekAverage(records, start: lastWeek) {
            let diff = a - b
            if diff >= 5 {
                msg += tr(" {0} másodperccel jobb, mint a múlt héten, szép fejlődés!", Int(diff.rounded()))
            } else if diff <= -5 {
                msg += tr(" {0} másodperccel kevesebb, mint a múlt héten. Próbáld meg a negyedenkénti jelzést követni!", Int((-diff).rounded()))
            } else {
                msg += tr(" Nagyjából ugyanannyi, mint a múlt héten.")
            }
        }
        if a < goals.targetS { msg += tr(" Átlagban még {0} másodperc hiányzik a célhoz.", Int((goals.targetS - a).rounded())) }
        return msg
    }

    public func todayCount(_ records: [BrushRecord], today: Date) -> Int {
        (byDay(records)[day(today)] ?? []).count
    }
}
