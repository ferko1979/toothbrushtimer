import Foundation

// Oral-care journal: symptoms (sensitivity, bleeding gums) and extras (floss,
// mouthwash, interdental brush, tongue cleaning, toothpaste). 1:1 port of
// android/brushcore/src/main/kotlin/hu/fogmosas/core/Care.kt — keep the two in sync.

public enum Toothpastes {
    public struct Kind: Identifiable, Equatable { public let id: String; public let title: String }
    public static let all: [Kind] = [
        Kind(id: "fluoride", title: "Normál fluoridos"),
        Kind(id: "sensitive", title: "Érzékeny fogra"),
        Kind(id: "whitening", title: "Fehérítő"),
        Kind(id: "gum", title: "Ínyvédő"),
        Kind(id: "kids", title: "Gyerek fogkrém"),
        Kind(id: "herbal", title: "Gyógynövényes / fluoridmentes"),
    ]
    public static func title(_ id: String?) -> String { all.first { $0.id == id }?.title ?? "—" }
}

/// One check-in, usually right after a brushing. sensitivity: 0 none, 1 mild, 2 strong.
public struct CareEntry: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var profileId: String
    public var date: Date
    public var sensitivity: Int = 0
    public var bleeding = false
    public var floss = false
    public var mouthwash = false
    public var interdental = false
    public var tongue = false
    public var toothpaste: String? = nil

    public init(profileId: String, date: Date, sensitivity: Int = 0, bleeding: Bool = false, floss: Bool = false,
                mouthwash: Bool = false, interdental: Bool = false, tongue: Bool = false, toothpaste: String? = nil) {
        self.profileId = profileId; self.date = date; self.sensitivity = sensitivity; self.bleeding = bleeding
        self.floss = floss; self.mouthwash = mouthwash; self.interdental = interdental; self.tongue = tongue
        self.toothpaste = toothpaste
    }
}

public extension ExtraRecord {
    /// Old floss / mouthwash ticks as journal entries.
    var asCare: CareEntry {
        var e = CareEntry(profileId: profileId, date: date, floss: kind == .floss, mouthwash: kind == .mouthwash)
        e.id = id
        return e
    }
}

public enum CareKind: String, CaseIterable {
    case floss, mouthwash, interdental, tongue, sensitivity, bleeding

    public var label: String {
        switch self {
        case .floss: return "Fogselyem"
        case .mouthwash: return "Szájvíz"
        case .interdental: return "Fogköztisztító"
        case .tongue: return "Nyelvtisztítás"
        case .sensitivity: return "Érzékenység"
        case .bleeding: return "Ínyvérzés"
        }
    }

    public func matches(_ e: CareEntry) -> Bool {
        switch self {
        case .floss: return e.floss
        case .mouthwash: return e.mouthwash
        case .interdental: return e.interdental
        case .tongue: return e.tongue
        case .sensitivity: return e.sensitivity > 0
        case .bleeding: return e.bleeding
        }
    }
}

/// Per-day merge of all check-ins of that day.
public struct CareDay: Equatable {
    public let day: Date
    public let floss, mouthwash, interdental, tongue: Bool
    public let sensitivity: Int
    public let bleeding: Bool
    public let toothpaste: String?
}

public func careDays(_ entries: [CareEntry], calendar: Calendar = .current) -> [Date: CareDay] {
    let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
    return groups.mapValues { es in
        let d = calendar.startOfDay(for: es[0].date)
        return CareDay(day: d, floss: es.contains { $0.floss }, mouthwash: es.contains { $0.mouthwash },
                       interdental: es.contains { $0.interdental }, tongue: es.contains { $0.tongue },
                       sensitivity: es.map(\.sensitivity).max() ?? 0, bleeding: es.contains { $0.bleeding },
                       toothpaste: es.sorted { $0.date < $1.date }.last { $0.toothpaste != nil }?.toothpaste)
    }
}

private func addDays(_ d: Date, _ n: Int, _ cal: Calendar) -> Date { cal.date(byAdding: .day, value: n, to: d)! }

/// Number of days in [today - days + 1, today] (shifted back by offsetDays) with the kind present.
public func careCount(_ entries: [CareEntry], _ kind: CareKind, today: Date, days: Int, offsetDays: Int = 0,
                      calendar: Calendar = .current) -> Int {
    let end = addDays(calendar.startOfDay(for: today), -offsetDays, calendar)
    let start = addDays(end, -(days - 1), calendar)
    let set = Set(entries.filter { kind.matches($0) }.map { calendar.startOfDay(for: $0.date) })
    return set.filter { $0 >= start && $0 <= end }.count
}

/// Consecutive days with the kind, ending today (or yesterday if today is not ticked yet).
public func careStreak(_ entries: [CareEntry], _ kind: CareKind, today: Date, calendar: Calendar = .current) -> Int {
    let days = Set(entries.filter { kind.matches($0) }.map { calendar.startOfDay(for: $0.date) })
    var d = calendar.startOfDay(for: today)
    if !days.contains(d) { d = addDays(d, -1, calendar) }
    var n = 0
    while days.contains(d) { n += 1; d = addDays(d, -1, calendar) }
    return n
}

public func careDoneToday(_ entries: [CareEntry], _ kind: CareKind, today: Date, calendar: Calendar = .current) -> Bool {
    entries.contains { kind.matches($0) && calendar.isDate($0.date, inSameDayAs: today) }
}

public struct CareInsight: Equatable, Identifiable {
    public let id: String
    public let text: String
    public var alert = false
}

public enum CareRules {
    public static let window = 14
    public static let bleedingAlertDays = 4
    public static let sensitivityAlertDays = 5
    public static let disclaimer = "Ez nem orvosi diagnózis."
}

/// Observations over the last two weeks compared with the two weeks before. Alerts come first.
public func careInsights(_ entries: [CareEntry], today: Date, flossTracked: Bool = true, calendar: Calendar = .current) -> [CareInsight] {
    let w = CareRules.window
    func now(_ k: CareKind) -> Int { careCount(entries, k, today: today, days: w, calendar: calendar) }
    func before(_ k: CareKind) -> Int { careCount(entries, k, today: today, days: w, offsetDays: w, calendar: calendar) }
    func recent(_ k: CareKind) -> Int { careCount(entries, k, today: today, days: 3, calendar: calendar) }
    let t0 = calendar.startOfDay(for: today)
    let wStart = addDays(t0, -(w - 1), calendar)
    var out: [CareInsight] = []

    let bleed = now(.bleeding)
    if bleed >= CareRules.bleedingAlertDays && recent(.bleeding) > 0 {
        out.append(CareInsight(id: "bleeding_persistent",
            text: "Az ínyed az utóbbi 2 hétben \(bleed) napon vérzett. Ha a vérzés 2 hétnél tovább tart, keresd fel a fogorvosodat. \(CareRules.disclaimer)", alert: true))
    }
    let days = careDays(entries, calendar: calendar)
    let inWindow = days.values.filter { $0.day >= wStart && $0.day <= t0 }
    let strong = inWindow.filter { $0.sensitivity >= 2 }.count
    let sens = now(.sensitivity)
    if sens >= CareRules.sensitivityAlertDays && recent(.sensitivity) > 0 {
        out.append(CareInsight(id: "sensitivity_persistent",
            text: "Az utóbbi 2 hétben \(sens) napon jeleztél fogérzékenységet" + (strong > 0 ? " (\(strong) napon erőset)" : "") +
                ". A tartós érzékenységet érdemes megmutatni a fogorvosnak. \(CareRules.disclaimer)", alert: true))
    }

    let flossNow = now(.floss), flossBefore = before(.floss), bleedBefore = before(.bleeding)
    if flossNow > flossBefore && bleed < bleedBefore {
        out.append(CareInsight(id: "floss_helps",
            text: "Amióta gyakrabban fogselymezel (\(flossBefore) → \(flossNow) nap / 2 hét), ritkábban vérzik az ínyed (\(bleedBefore) → \(bleed) nap)."))
    }

    let pasteNow = inWindow.compactMap(\.toothpaste)
    let sensBefore = before(.sensitivity)
    if !pasteNow.isEmpty && pasteNow.filter({ $0 == "sensitive" }).count * 2 >= pasteNow.count && sens < sensBefore {
        out.append(CareInsight(id: "toothpaste_helps",
            text: "Amióta érzékeny fogra való fogkrémet használsz, ritkábban jelzel érzékenységet (\(sensBefore) → \(sens) nap / 2 hét)."))
    } else if sens >= 3 && !pasteNow.isEmpty && !pasteNow.contains("sensitive") {
        out.append(CareInsight(id: "toothpaste_try",
            text: "Gyakran jelzel érzékenységet. Kérdezd meg a fogorvosodat, hogy segíthet-e egy érzékeny fogra való fogkrém."))
    }

    let floss7 = careCount(entries, .floss, today: today, days: 7, calendar: calendar)
    if flossTracked && floss7 < 3 && !entries.isEmpty {
        out.append(CareInsight(id: "floss_rare",
            text: "A fogorvosok naponta egyszer javasolják a fogközök tisztítását (fogselyem vagy fogköztisztító kefe). Az utóbbi héten \(floss7) napon volt."))
    }
    return out
}

// MARK: - Dentist visits

public struct DentistStatus: Equatable {
    public let checkupDue: Date?
    public let cleaningDue: Date?
    public let checkupOverdue: Bool
    public let cleaningOverdue: Bool

    public var message: String? {
        if checkupOverdue && cleaningOverdue { return "Esedékes a fogorvosi kontroll és a fogkőeltávolítás." }
        if checkupOverdue { return "Esedékes a félévenkénti fogorvosi kontroll." }
        if cleaningOverdue { return "Esedékes az éves fogkőeltávolítás." }
        return nil
    }
}

public enum DentistRules {
    public static let checkupMonths = 6
    public static let cleaningMonths = 12
}

public func dentistStatus(lastCheckup: Date?, lastCleaning: Date?, today: Date, calendar: Calendar = .current) -> DentistStatus {
    let t = calendar.startOfDay(for: today)
    let c = lastCheckup.map { calendar.date(byAdding: .month, value: DentistRules.checkupMonths, to: calendar.startOfDay(for: $0))! }
    let k = lastCleaning.map { calendar.date(byAdding: .month, value: DentistRules.cleaningMonths, to: calendar.startOfDay(for: $0))! }
    return DentistStatus(checkupDue: c, cleaningDue: k, checkupOverdue: c.map { t >= $0 } ?? false, cleaningOverdue: k.map { t >= $0 } ?? false)
}

/// Day of the next dentist reminder (the scheduler fires at 10:00), or nil.
public func nextDentistReminder(lastCheckup: Date?, lastCleaning: Date?, today: Date, calendar: Calendar = .current) -> Date? {
    let s = dentistStatus(lastCheckup: lastCheckup, lastCleaning: lastCleaning, today: today, calendar: calendar)
    guard let first = [s.checkupDue, s.cleaningDue].compactMap({ $0 }).min() else { return nil }
    let t = calendar.startOfDay(for: today)
    return first > t ? first : addDays(t, 7, calendar)
}

// MARK: - Orthodontic mode, rewards

public enum Orthodontic {
    public static let targetS = 180.0
    public static let note = "Fogszabályzóval a fogorvosok hosszabb, alaposabb fogmosást és a fogközök naponta többszöri tisztítását javasolják."
}

public struct RewardProgress: Equatable {
    public let have: Int
    public let need: Int
    public let text: String
    public var done: Bool { have >= need }
    public var fraction: Double { need <= 0 ? 1 : min(Double(have) / Double(need), 1) }
}

/// Parent-set reward (e.g. "Mozi") for N stickers collected since the reward was set.
public func rewardProgress(_ records: [BrushRecord], goals: Goals, reward: String?, need: Int, since: Date?,
                           coach: Coach = Coach()) -> RewardProgress? {
    guard let reward = reward, !reward.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    let rs = records.filter { since == nil || $0.start >= since! }
    let days = Dictionary(grouping: rs) { coach.calendar.startOfDay(for: $0.start) }
    let have = days.values.filter { coach.isPerfectDay($0, goals: goals) }.count
    return RewardProgress(have: min(have, need), need: need, text: reward)
}

// MARK: - Dentist report

public struct ReportSection: Equatable, Codable {
    public let title: String
    public let lines: [String]
}

public struct DentistReport: Equatable {
    public let title: String
    public let subtitle: String
    public let sections: [ReportSection]

    public var text: String {
        var s = "\(title)\n\(subtitle)\n"
        for sec in sections {
            s += "\n\(sec.title)\n"
            for l in sec.lines { s += "• \(l)\n" }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public func huDate(_ d: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d.%02d.%02d.", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

public func dentistReport(profile: Profile, records: [BrushRecord], entries: [CareEntry], today: Date, days: Int,
                          coach: Coach = Coach()) -> DentistReport {
    let cal = coach.calendar
    let t0 = cal.startOfDay(for: today)
    let start = addDays(t0, -(days - 1), cal)
    let end = addDays(t0, 1, cal)
    let rs = records.filter { $0.start >= start && $0.start < end }
    let es = entries.filter { $0.date >= start && $0.date < end }
    let g = profile.goals
    let brushDays = Dictionary(grouping: rs) { cal.startOfDay(for: $0.start) }
    let avg = rs.isEmpty ? 0 : rs.map(\.durationS).reduce(0, +) / Double(rs.count)
    let pct = rs.isEmpty ? 0 : Int((100.0 * Double(rs.filter { $0.durationS >= g.targetS }.count) / Double(rs.count)).rounded())
    func hour(_ r: BrushRecord) -> Int { cal.component(.hour, from: r.start) }
    let morning = rs.filter { (4..<12).contains(hour($0)) }.count
    let evening = rs.filter { hour($0) >= 17 }.count
    let perfect = brushDays.values.filter { coach.isPerfectDay($0, goals: g) }.count
    var brushing = [
        "Fogmosások: \(rs.count) (\(brushDays.count) napon a \(days) napból; reggel \(morning), este \(evening))",
        "Átlagos időtartam: \(formatClock(avg)) (cél: \(formatClock(g.targetS))), célidőt elérte: \(pct)%",
        "Napi cél (\(g.perDay)× \(formatClock(g.targetS))) teljesítve: \(perfect) napon",
        "Elzárt csappal: \(rs.filter { $0.tapOff }.count) fogmosás",
    ]
    if let mx = rs.map(\.durationS).max(), let mn = rs.map(\.durationS).min() {
        brushing.append("Leghosszabb: \(formatClock(mx)), legrövidebb: \(formatClock(mn))")
    }

    func c(_ k: CareKind) -> Int { careCount(es, k, today: today, days: days, calendar: cal) }
    let cd = careDays(es, calendar: cal)
    let strong = cd.values.filter { $0.sensitivity >= 2 }.count
    let care = [
        "Fogselyem: \(c(.floss)) napon",
        "Fogköztisztító kefe / szájzuhany: \(c(.interdental)) napon",
        "Szájvíz: \(c(.mouthwash)) napon",
        "Nyelvtisztítás: \(c(.tongue)) napon",
    ]
    var symptoms = [
        "Fogérzékenység: \(c(.sensitivity)) napon" + (strong > 0 ? " (ebből erős: \(strong))" : ""),
        "Ínyvérzés: \(c(.bleeding)) napon",
    ]
    if let lastBleed = es.filter(\.bleeding).max(by: { $0.date < $1.date }) {
        symptoms.append("Utolsó ínyvérzés: \(huDate(lastBleed.date, calendar: cal))")
    }
    var counts: [String: Int] = [:]
    for d in cd.values { if let p = d.toothpaste { counts[p, default: 0] += 1 } }
    if !counts.isEmpty {
        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        symptoms.append("Fogkrém: " + sorted.map { "\(Toothpastes.title($0.key)) (\($0.value) nap)" }.joined(separator: ", "))
    }

    var other = ["Fogkefe: " + (profile.brushType == .electric ? "elektromos" : "kézi")]
    if profile.orthodontic { other.append("Fogszabályzó: igen") }
    if let d = profile.lastCheckup { other.append("Utolsó fogorvosi kontroll: \(huDate(d, calendar: cal))") }
    if let d = profile.lastCleaning { other.append("Utolsó fogkőeltávolítás: \(huDate(d, calendar: cal))") }
    other.append("Mérés: a telefon/óra mikrofonja alapján, a készüléken feldolgozva (hangfelvétel nem készül). A tüneteket a felhasználó jelölte.")

    return DentistReport(
        title: "Fogápolási jelentés – \(profile.name)",
        subtitle: "\(huDate(start, calendar: cal)) – \(huDate(t0, calendar: cal)) (\(days) nap)",
        sections: [ReportSection(title: "Fogmosás", lines: brushing),
                   ReportSection(title: "Fogköztisztítás és kiegészítők", lines: care),
                   ReportSection(title: "Tünetek", lines: symptoms),
                   ReportSection(title: "Egyéb", lines: other)])
}
