import Foundation

/// Reminder settings and planning (reminders.py).
/// iOS cannot observe the first unlock, so the morning reminder is scheduled at
/// the wake-up time and waits on the lock screen for the first pick-up.
public struct ClockTime: Codable, Equatable, Comparable {
    public var hour: Int
    public var minute: Int
    public init(_ hour: Int, _ minute: Int) { self.hour = hour; self.minute = minute }
    public var minutes: Int { hour * 60 + minute }
    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutes < b.minutes }
    public func adding(minutes m: Int) -> ClockTime {
        let t = ((minutes + m) % 1440 + 1440) % 1440
        return ClockTime(t / 60, t % 60)
    }
    public var text: String { String(format: "%d:%02d", hour, minute) }
}

public struct ReminderSettings: Codable, Equatable {
    public var enabled = true
    public var morningEnabled = true
    public var wakeTime = ClockTime(7, 0)
    public var bedtimeEnabled = true
    public var bedtime = ClockTime(22, 30)
    public var bedtimeLeadMin = 15
    public var eveningEnabled = false
    public var eveningTime = ClockTime(20, 0)
    public var followupEnabled = true
    public var followupAfterMin = 20
    public var maxFollowups = 1
    public init() {}
}

public struct PlannedReminder: Equatable {
    public let id: String       // "rem.<key>.<yyyy-MM-dd>"
    public let key: String      // morning, bedtime, evening, <base>_followup<n>
    public let fireDate: Date
    public let text: String
}

public enum ReminderTexts {
    public static let morning = "Jó reggelt! Kezdd a napot 2 perc fogmosással. 🪥"
    public static let bedtime = "Hamarosan lefekvés: még hiányzik az esti fogmosás. Koppints, és indulhat."
    public static let evening = "Esti fogmosás: 2 perc, és kész is vagy a mai céllal."
    public static let followup = "Még mindig vár a fogkefe. 😉 Nyisd meg az appot, és kezdheted."
}

public struct ReminderPlanner {
    public static let morningWindow = (ClockTime(4, 0), ClockTime(11, 59))
    public static let eveningWindow = (ClockTime(17, 0), ClockTime(23, 59))
    public var calendar: Calendar
    public init(calendar: Calendar = .current) { self.calendar = calendar }

    func clock(_ d: Date) -> ClockTime {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return ClockTime(c.hour ?? 0, c.minute ?? 0)
    }

    func at(_ day: Date, _ t: ClockTime) -> Date {
        calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day)!
    }

    static func dayKey(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Local notifications to schedule for the next `days` days. Today's reminders
    /// are skipped if they are in the past or that brushing already happened.
    public func plan(now: Date, records: [BrushRecord], goals: Goals, settings s: ReminderSettings,
                     days: Int = 7) -> [PlannedReminder] {
        guard s.enabled else { return [] }
        var out: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<days {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let dayRecs = records.filter { calendar.isDate($0.start, inSameDayAs: day) }
            let morningDone = dayRecs.contains { let t = clock($0.start); return t >= Self.morningWindow.0 && t <= Self.morningWindow.1 }
            let eveningDone = dayRecs.contains { let t = clock($0.start); return t >= Self.eveningWindow.0 && t <= Self.eveningWindow.1 }
            var base: [(String, Date, String)] = []
            if s.morningEnabled && !morningDone { base.append(("morning", at(day, s.wakeTime), ReminderTexts.morning)) }
            if goals.perDay >= 2 && !eveningDone {
                if s.eveningEnabled { base.append(("evening", at(day, s.eveningTime), ReminderTexts.evening)) }
                if s.bedtimeEnabled {
                    base.append(("bedtime", at(day, s.bedtime.adding(minutes: -s.bedtimeLeadMin)), ReminderTexts.bedtime))
                }
            }
            let key = Self.dayKey(day, calendar: calendar)
            for (k, date, text) in base {
                var items = [(k, date, text)]
                if s.followupEnabled {
                    for n in 1...Swift.max(s.maxFollowups, 1) where n <= s.maxFollowups {
                        items.append(("\(k)_followup\(n)", date.addingTimeInterval(Double(n * s.followupAfterMin * 60)), ReminderTexts.followup))
                    }
                }
                for (kk, dd, tt) in items where dd > now {
                    out.append(PlannedReminder(id: "rem.\(kk).\(key)", key: kk, fireDate: dd, text: tt))
                }
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }
}
