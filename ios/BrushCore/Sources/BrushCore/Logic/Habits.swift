import Foundation

/// Recurring bad habits with a targeted tip (habits.py).
public struct Habit: Equatable, Identifiable {
    public let id: String
    public let message: String
}

public func detectHabits(_ records: [BrushRecord], goals: Goals, today: Date, calendar: Calendar = .current) -> [Habit] {
    let day0 = calendar.startOfDay(for: today)
    func window(_ days: Int, offset: Int = 0) -> [BrushRecord] {
        let start = calendar.date(byAdding: .day, value: -(days - 1 + offset), to: day0)!
        let endDay = calendar.date(byAdding: .day, value: -offset + 1, to: day0)!
        return records.filter { $0.start >= start && $0.start < endDay }
    }
    func avg(_ rs: [BrushRecord]) -> Double? { rs.isEmpty ? nil : rs.map(\.durationS).reduce(0, +) / Double(rs.count) }
    func clock(_ d: Date) -> ClockTime {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return ClockTime(c.hour ?? 0, c.minute ?? 0)
    }
    func daysMissing(_ w: (ClockTime, ClockTime)) -> Int {
        let have = Set(records.filter { let t = clock($0.start); return t >= w.0 && t <= w.1 }
            .map { calendar.startOfDay(for: $0.start) })
        return (1...7).filter { !have.contains(calendar.date(byAdding: .day, value: -$0, to: day0)!) }.count
    }

    var out: [Habit] = []
    let last14 = window(14), last7 = window(7)
    if last14.count >= 4 {
        if Double(last14.filter { $0.durationS < 30 }.count) / Double(last14.count) >= 0.5 {
            out.append(Habit(id: "rushing", message: "Az utóbbi két hétben a fogmosások fele 30 másodpercnél rövidebb volt. Kövesd a negyedenkénti rezgést: minden jelzésnél válts a következő fogsornegyedre."))
        }
        if Double(last14.filter { $0.durationS > 240 }.count) / Double(last14.count) >= 0.5 {
            out.append(Habit(id: "overbrushing", message: "Gyakran 4 percnél is tovább mosol fogat. A 2–3 perc elég; a túl hosszú, erős súrolás az ínyt és a zománcot koptathatja. Puha sörtéjű fogkefe ajánlott."))
        }
    }
    if !records.isEmpty && goals.perDay >= 2 {
        if daysMissing(ReminderPlanner.eveningWindow) >= 3 {
            out.append(Habit(id: "evening_skipped", message: "Az elmúlt héten legalább 3 este kimaradt a fogmosás. Az esti a legfontosabb: éjszaka kevesebb nyál termelődik, ezért a lepedék könnyebben károsít. Kapcsold be a lefekvés előtti emlékeztetőt!"))
        }
        if daysMissing(ReminderPlanner.morningWindow) >= 3 {
            out.append(Habit(id: "morning_skipped", message: "Az elmúlt héten legalább 3 reggel kimaradt a fogmosás. Próbáld egy meglévő szokáshoz kötni (pl. reggeli után, öltözködés előtt)."))
        }
    }
    if last7.filter({ !$0.tapOff }).count >= 3 {
        out.append(Habit(id: "tap_running", message: "Az elmúlt héten többször folyt a csap fogmosás közben. Nedvesítés után zárd el, és csak öblítéskor nyisd meg újra."))
    }
    let weekday = last14.filter { let w = calendar.component(.weekday, from: $0.start); return w != 1 && w != 7 }
    let weekend = last14.filter { let w = calendar.component(.weekday, from: $0.start); return w == 1 || w == 7 }
    if weekday.count >= 2, weekend.count >= 2, let a = avg(weekday), let b = avg(weekend), b < a - 20 {
        out.append(Habit(id: "weekend_dip", message: "Hétvégén átlagosan \(Int((a - b).rounded())) másodperccel rövidebben mosol fogat, mint hétköznap. A fogaidnak nincs hétvégéjük. 😉"))
    }
    let prev7 = window(7, offset: 7)
    if last7.count >= 3, prev7.count >= 3, let a = avg(last7), let b = avg(prev7), a < b - 15 {
        out.append(Habit(id: "declining", message: "Az utóbbi héten \(Int((b - a).rounded())) másodperccel rövidebbek a fogmosásaid, mint előtte. Tűzz ki egy rövid célt: holnap legalább egyszer a teljes kör!"))
    }
    return out
}
