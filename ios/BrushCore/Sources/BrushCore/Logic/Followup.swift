import Foundation

// Tooth map, follow-up questions after a complaint, photo timeline, care task reminders and the
// electric brush's motor trend. Same as android/brushcore/.../Followup.kt (tests: FollowupTests.swift).

/// Adult teeth in FDI numbering, as seen facing the patient: upper right, upper left, lower right, lower left.
public enum ToothMap {
    public static let upperRight = (11...18).reversed().map { String($0) }
    public static let upperLeft = (21...28).map { String($0) }
    public static let lowerRight = (41...48).reversed().map { String($0) }
    public static let lowerLeft = (31...38).map { String($0) }
    public static var all: [String] { upperRight + upperLeft + lowerRight + lowerLeft }
    /// Complaints about one tooth: these ask for the tooth on the map.
    public static let kinds: Set<String> = ["pain", "sensitivity", "chipped", "loose", "stuck"]

    public static var quadrants: [(String, [String])] {
        [(tr("Felső jobb"), upperRight), (tr("Felső bal"), upperLeft), (tr("Alsó jobb"), lowerRight), (tr("Alsó bal"), lowerLeft)]
    }

    /// "46" -> "46 (jobb alsó első nagyőrlő)", for the summary.
    public static func name(_ fdi: String) -> String {
        guard fdi.count == 2, let q = Int(String(fdi.prefix(1))), let n = Int(String(fdi.suffix(1))) else { return fdi }
        let side: String
        switch q {
        case 1: side = tr("jobb felső")
        case 2: side = tr("bal felső")
        case 3: side = tr("bal alsó")
        case 4: side = tr("jobb alsó")
        default: return fdi
        }
        let tooth: String
        switch n {
        case 1: tooth = tr("középső metszőfog")
        case 2: tooth = tr("oldalsó metszőfog")
        case 3: tooth = tr("szemfog")
        case 4: tooth = tr("első kisőrlő")
        case 5: tooth = tr("második kisőrlő")
        case 6: tooth = tr("első nagyőrlő")
        case 7: tooth = tr("második nagyőrlő")
        case 8: tooth = tr("bölcsességfog")
        default: return fdi
        }
        return "\(fdi) (\(side) \(tooth))"
    }
}

// MARK: - Follow-up

/// Answer to "Hogy van most?" some days after a complaint.
public struct SymptomFollowUp: Codable, Equatable {
    public var reportId: UUID
    public var day: Int
    /// "gone", "better", "same", "worse", "visited"
    public var answer: String
    public var date: Date
    public init(reportId: UUID, day: Int, answer: String, date: Date) {
        self.reportId = reportId; self.day = day; self.answer = answer; self.date = date
    }
}

public enum FollowUps {
    public static let days = [1, 3, 7]
    public static var answers: [(String, String)] {
        [("gone", tr("Elmúlt")), ("better", tr("Javult")), ("same", tr("Ugyanolyan")), ("worse", tr("Rosszabb")), ("visited", tr("Voltam orvosnál"))]
    }
    public static func title(_ id: String) -> String { answers.first { $0.0 == id }?.1 ?? id }
}

private func daysBetween(_ a: Date, _ b: Date, _ cal: Calendar) -> Int {
    cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
}

/// The follow-up day (1, 3 or 7) to ask about now, or nil (not yet, already answered, resolved, or too old).
public func followUpDue(_ r: SymptomReport, _ ups: [SymptomFollowUp], now: Date, calendar: Calendar = .current) -> Int? {
    let mine = ups.filter { $0.reportId == r.id }
    if mine.contains(where: { $0.answer == "gone" || $0.answer == "visited" }) { return nil }
    let age = daysBetween(r.date, now, calendar)
    if age > 14 { return nil }
    let answered = mine.map(\.day).max() ?? 0
    return FollowUps.days.last { $0 <= age && $0 > answered }
}

/// What the app says after a follow-up answer; `contact` = suggest contacting the doctor.
public func followUpAdvice(_ r: SymptomReport, answer: String, day: Int) -> (text: String, contact: Bool) {
    switch answer {
    case "worse": return (tr("Rosszabbodott: keresd az orvosodat, és küldd el neki a panaszt."), true)
    case "same":
        if day >= 7 { return (tr("Egy hét után sem javult: kérj időpontot."), true) }
        if TriageLevel.byId(r.level).rank >= TriageLevel.soon.rank { return (tr("Nem javult: érdemes időpontot kérni."), true) }
        return (tr("Figyeld tovább; pár nap múlva újra rákérdezünk."), false)
    case "better": return (tr("Örülünk, hogy javul! Pár nap múlva még rákérdezünk."), false)
    case "gone": return (tr("Nagyszerű, hogy elmúlt! A panasz lezárva."), false)
    default: return (tr("Köszönjük, rögzítettük."), false)
    }
}

/// Follow-up notifications (18:00 on day 1, 3 and 7) for complaints not resolved yet.
public func plannedFollowUps(_ reports: [SymptomReport], _ ups: [SymptomFollowUp], now: Date, calendar: Calendar = .current) -> [(Date, String)] {
    var out: [(Date, String)] = []
    for r in reports {
        let mine = ups.filter { $0.reportId == r.id }
        if mine.contains(where: { $0.answer == "gone" || $0.answer == "visited" }) { continue }
        let answered = mine.map(\.day).max() ?? 0
        let day0 = calendar.startOfDay(for: r.date)
        for d in FollowUps.days where d > answered {
            guard let day = calendar.date(byAdding: .day, value: d, to: day0),
                  let at = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day), at > now else { continue }
            out.append((at, tr("Hogy van most? ({0}, {1} napja)", Symptoms.kind(r.kind).title.lowercased(), d)))
        }
    }
    return out.sorted { $0.0 < $1.0 }
}

/// Earlier photos of the same complaint, oldest first (photo comparison).
public func photoTimeline(_ reports: [SymptomReport], profileId: String, kind: String) -> [SymptomReport] {
    reports.filter { $0.profileId == profileId && $0.kind == kind && !$0.photos.isEmpty }.sorted { $0.date < $1.date }
}

// MARK: - Care tasks

/// Medicine / care reminder, e.g. mouthwash twice a day for 7 days after an extraction.
public struct CareTask: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var profileId: String
    public var title: String
    /// "HH:mm"
    public var times: [String]
    /// Start of the first day.
    public var start: Date
    public var days: Int
    /// "yyyy-MM-dd HH:mm" slots ticked off
    public var done: [String] = []

    public init(profileId: String, title: String, times: [String], start: Date, days: Int) {
        self.profileId = profileId; self.title = title; self.times = times; self.start = start; self.days = days
    }

    static func dayKey(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func activeOn(_ d: Date, calendar: Calendar = .current) -> Bool {
        let n = daysBetween(start, d, calendar)
        return n >= 0 && n < days
    }
    public func slot(_ d: Date, _ time: String, calendar: Calendar = .current) -> String { CareTask.dayKey(d, calendar) + " " + time }
    public func isDone(_ d: Date, _ time: String, calendar: Calendar = .current) -> Bool { done.contains(slot(d, time, calendar: calendar)) }
    public func toggled(_ d: Date, _ time: String, calendar: Calendar = .current) -> CareTask {
        var t = self
        let s = slot(d, time, calendar: calendar)
        if let i = t.done.firstIndex(of: s) { t.done.remove(at: i) } else { t.done.append(s) }
        return t
    }
    /// Ticked / all slots so far (including today).
    public func progress(today: Date, calendar: Calendar = .current) -> (Int, Int) {
        let elapsed = min(daysBetween(start, today, calendar) + 1, days)
        guard elapsed > 0 else { return (0, 0) }
        let n = elapsed * times.count
        return (min(done.count, n), n)
    }
}

public enum CareTaskPresets {
    public struct Preset {
        public let title: String
        public let times: [String]
        public let days: Int
    }
    public static var all: [Preset] {
        [Preset(title: tr("Szájöblítés (pl. klórhexidin)"), times: ["08:00", "20:00"], days: 7),
         Preset(title: tr("Fájdalomcsillapító (a tájékoztató szerint)"), times: ["08:00", "14:00", "20:00"], days: 3),
         Preset(title: tr("Antibiotikum (az orvos utasítása szerint)"), times: ["08:00", "16:00", "00:00"], days: 7),
         Preset(title: tr("Hideg borogatás"), times: ["10:00", "14:00", "18:00"], days: 2),
         Preset(title: tr("Sós vizes öblítés"), times: ["09:00", "21:00"], days: 5)]
    }
    /// Even spread of n reminder times between 08:00 and 20:00.
    public static func times(_ n: Int) -> [String] {
        switch max(1, min(4, n)) {
        case 1: return ["09:00"]
        case 2: return ["08:00", "20:00"]
        case 3: return ["08:00", "14:00", "20:00"]
        default: return ["08:00", "12:00", "16:00", "20:00"]
        }
    }
}

/// Reminder notifications for the next `days` days: (time, text).
public func plannedCareTasks(_ tasks: [CareTask], now: Date, days: Int = 7, calendar: Calendar = .current) -> [(Date, String)] {
    var out: [(Date, String)] = []
    let today = calendar.startOfDay(for: now)
    for t in tasks {
        for i in 0..<days {
            guard let d = calendar.date(byAdding: .day, value: i, to: today), t.activeOn(d, calendar: calendar) else { continue }
            for time in t.times {
                let hm = time.split(separator: ":").compactMap { Int($0) }
                guard hm.count == 2, let at = calendar.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: d),
                      at > now, !t.isDone(d, time, calendar: calendar) else { continue }
                out.append((at, tr("💊 {0}", t.title)))
            }
        }
    }
    return out.sorted { $0.0 < $1.0 }
}

// MARK: - Motor trend

public struct MotorWeek: Equatable {
    public let weekStart: Date
    public let medianHz: Double
    public let sessions: Int
}

public struct MotorTrend {
    public let weeks: [MotorWeek]
    public let changePct: Double?
    public let text: String
}

/// Weekly median motor frequency of the electric brush (from the brushings' f0) and its trend.
public func motorTrend(_ records: [BrushRecord], today: Date, weeks: Int = 8, calendar: Calendar = .current) -> MotorTrend {
    func monday(_ d: Date) -> Date {
        let day = calendar.startOfDay(for: d)
        let wd = (calendar.component(.weekday, from: day) + 5) % 7  // Monday = 0
        return calendar.date(byAdding: .day, value: -wd, to: day) ?? day
    }
    let last = monday(today)
    let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: last) ?? last
    var groups: [Date: [Double]] = [:]
    for r in records {
        guard let f = r.brushF0, f > 0 else { continue }
        let w = monday(r.start)
        if w >= first && w <= last { groups[w, default: []].append(f) }
    }
    let ws = groups.map { MotorWeek(weekStart: $0.key, medianHz: Stats.median($0.value), sessions: $0.value.count) }
        .sorted { $0.weekStart < $1.weekStart }
    guard ws.count >= 2 else { return MotorTrend(weeks: ws, changePct: nil, text: tr("A trendhez legalább két hét elektromos fogmosás kell.")) }
    let base = ws.prefix(2).map(\.medianHz).max() ?? ws[0].medianHz
    let now = ws[ws.count - 1].medianHz
    let pct = (now - base) / base * 100
    let text = pct <= -2
        ? tr("A motor {0}%-kal lassabban zúg, mint néhány hete: gyengül az akkumulátor, vagy töltésre szorul.", String(format: "%.1f", -pct))
        : tr("A motor egyenletesen zúg ({0} Hz), az akkumulátor rendben.", Int(now))
    return MotorTrend(weeks: ws, changePct: pct, text: text)
}
