#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity (lock screen + Dynamic Island) of one brushing. Shared by the app and the widget extension.
struct BrushingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// listening, water, armed, brushing, rinsing, done
        var phase: String
        /// Set while brushing: the timer counts up from here.
        var startedAt: Date?
        var waterRunning: Bool = false
        /// Set when done.
        var durationS: Double?
    }

    var name: String
    var targetS: Double
    var child: Bool
}
#endif
