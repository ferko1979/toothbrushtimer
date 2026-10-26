import Foundation

/// Optional floss / mouthwash tracking (extras.py).
public struct ExtraRecord: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case floss, mouthwash }
    public var id = UUID()
    public var profileId: String
    public var date: Date
    public var kind: Kind
    public init(profileId: String, date: Date, kind: Kind) { self.profileId = profileId; self.date = date; self.kind = kind }
}

public func extrasStreak(_ records: [ExtraRecord], kind: ExtraRecord.Kind, today: Date, calendar: Calendar = .current) -> Int {
    let days = Set(records.filter { $0.kind == kind }.map { calendar.startOfDay(for: $0.date) })
    var d = calendar.startOfDay(for: today)
    if !days.contains(d) { d = calendar.date(byAdding: .day, value: -1, to: d)! }
    var n = 0
    while days.contains(d) {
        n += 1
        d = calendar.date(byAdding: .day, value: -1, to: d)!
    }
    return n
}

public func extrasDoneToday(_ records: [ExtraRecord], kind: ExtraRecord.Kind, today: Date, calendar: Calendar = .current) -> Bool {
    records.contains { $0.kind == kind && calendar.isDate($0.date, inSameDayAs: today) }
}
