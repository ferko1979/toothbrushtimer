import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Today's progress, shared by the watch app and its complication through the App Group.
struct WatchSummaryData: Codable, Equatable {
    var day: Date
    var todayCount: Int
    var perDay: Int
    var streak: Int
    var lastDurationS: Double?

    /// The stored summary as seen today (a summary from an earlier day counts 0 brushings).
    func asOf(_ now: Date, calendar: Calendar = .current) -> WatchSummaryData {
        if calendar.isDate(day, inSameDayAs: now) { return self }
        var s = self
        s.day = now
        s.todayCount = 0
        // Yesterday's goal still holds the streak until today ends.
        if let y = calendar.date(byAdding: .day, value: -1, to: now), !calendar.isDate(day, inSameDayAs: y) { s.streak = 0 }
        return s
    }
}

enum WatchSummaryStore {
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "FogmosasAppGroup") as? String }
    private static let key = "summary"

    static var defaults: UserDefaults? { groupID.flatMap { UserDefaults(suiteName: $0) } }

    static func load() -> WatchSummaryData? {
        guard let d = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSummaryData.self, from: d)
    }

    static func save(_ s: WatchSummaryData) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        defaults?.set(d, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
