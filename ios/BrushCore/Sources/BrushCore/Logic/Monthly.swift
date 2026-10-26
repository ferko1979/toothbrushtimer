import Foundation

/// Monthly summary, printable for the dentist (monthly.py).
public struct MonthlyReport: Equatable {
    public let year: Int, month: Int, daysInMonth: Int
    public let sessions: Int, daysBrushed: Int
    public let avgS: Double, pctGoal: Double
    public let perfectDays: Int, bestStreak: Int
    public let morning: Int, evening: Int
    public let tapOffSessions: Int
    public let waterSavedL: Double, waterWastedL: Double
}

public let monthNamesHU = ["január", "február", "március", "április", "május", "június", "július",
                           "augusztus", "szeptember", "október", "november", "december"]

public func monthlyReport(_ records: [BrushRecord], goals: Goals, year: Int, month: Int,
                          locale: WaterLocale = .hu, calendar: Calendar = .current) -> MonthlyReport {
    let comps = DateComponents(year: year, month: month, day: 1)
    let first = calendar.date(from: comps)!
    let ndays = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    let rs = records.filter {
        let c = calendar.dateComponents([.year, .month], from: $0.start)
        return c.year == year && c.month == month
    }
    let coach = Coach(calendar: calendar)
    let days = Dictionary(grouping: rs, by: { calendar.startOfDay(for: $0.start) })
    let perfect = days.filter { coach.isPerfectDay($0.value, goals: goals) }.keys.sorted()
    var best = 0, run = 0
    var prev: Date?
    for d in perfect {
        if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
        best = Swift.max(best, run)
        prev = d
    }
    func clock(_ d: Date) -> ClockTime {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return ClockTime(c.hour ?? 0, c.minute ?? 0)
    }
    let mw = ReminderPlanner.morningWindow, ew = ReminderPlanner.eveningWindow
    let flowPerS = locale.flowLPerMin / 60
    let tapOff = rs.filter(\.tapOff)
    return MonthlyReport(
        year: year, month: month, daysInMonth: ndays,
        sessions: rs.count, daysBrushed: days.count,
        avgS: rs.isEmpty ? 0 : rs.map(\.durationS).reduce(0, +) / Double(rs.count),
        pctGoal: rs.isEmpty ? 0 : 100 * Double(rs.filter { $0.durationS >= goals.targetS }.count) / Double(rs.count),
        perfectDays: perfect.count, bestStreak: best,
        morning: rs.filter { let t = clock($0.start); return t >= mw.0 && t <= mw.1 }.count,
        evening: rs.filter { let t = clock($0.start); return t >= ew.0 && t <= ew.1 }.count,
        tapOffSessions: tapOff.count,
        waterSavedL: tapOff.map(\.durationS).reduce(0, +) * flowPerS,
        waterWastedL: rs.map(\.waterRunningS).reduce(0, +) * flowPerS)
}

public func formatMonthly(_ r: MonthlyReport, goals: Goals, name: String = "") -> String {
    let expected = r.daysInMonth * goals.perDay
    let title = "Havi fogmosás-összefoglaló – \(r.year). \(monthNamesHU[r.month - 1])" + (name.isEmpty ? "" : " – \(name)")
    var lines = [title,
                 "Fogmosások: \(r.sessions) / \(expected) tervezett (\(r.daysBrushed) napon; reggel \(r.morning), este \(r.evening))",
                 "Átlagos időtartam: \(Int(r.avgS.rounded())) s (cél: \(Int(goals.targetS)) s), a célidőt elérte: \(Int(r.pctGoal.rounded()))%",
                 "Tökéletes napok: \(r.perfectDays), leghosszabb sorozat: \(r.bestStreak) nap",
                 "Elzárt csappal: \(r.tapOffSessions) fogmosás, megtakarított víz kb. \(Int(r.waterSavedL.rounded())) l"]
    if r.waterWastedL >= 1 { lines.append("Fogmosás közben elfolyt víz: kb. \(Int(r.waterWastedL.rounded())) l") }
    lines.append("Mérés: a telefon/óra mikrofonja alapján, a készüléken feldolgozva (hangfelvétel nem készül).")
    return lines.joined(separator: "\n")
}

/// CSV export (Android has no Health Connect type for toothbrushing; iOS offers it as a file too).
public func recordsCSV(_ records: [BrushRecord]) -> String {
    let f = ISO8601DateFormatter()
    var s = "start,duration_s,water_running_s,source\n"
    for r in records.sorted(by: { $0.start < $1.start }) {
        s += "\(f.string(from: r.start)),\(String(format: "%.1f", r.durationS)),\(String(format: "%.1f", r.waterRunningS)),\(r.source)\n"
    }
    return s
}
