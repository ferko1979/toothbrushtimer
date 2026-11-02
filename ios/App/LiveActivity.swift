import ActivityKit
import Foundation

/// Starts, updates and ends the brushing Live Activity ("live_activity" setting).
enum LiveActivity {
    private static var current: Activity<BrushingAttributes>?
    private static var last: BrushingAttributes.ContentState?

    static func start(name: String, targetS: Double, child: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(durationS: nil)
        let state = BrushingAttributes.ContentState(phase: "listening")
        current = try? Activity.request(attributes: BrushingAttributes(name: name, targetS: targetS, child: child),
                                        content: .init(state: state, staleDate: nil), pushType: nil)
        last = state
    }

    static func update(phase: String, elapsedS: Double, waterRunning: Bool) {
        guard let a = current else { return }
        let brushing = phase == "brushing" || phase == "rinsing"
        let state = BrushingAttributes.ContentState(phase: phase,
                                                    startedAt: brushing ? (last?.startedAt ?? Date().addingTimeInterval(-elapsedS)) : nil,
                                                    waterRunning: waterRunning)
        guard state != last else { return }
        last = state
        Task { await a.update(.init(state: state, staleDate: nil)) }
    }

    static func end(durationS: Double?) {
        guard let a = current else { return }
        current = nil
        last = nil
        let state = BrushingAttributes.ContentState(phase: "done", durationS: durationS)
        Task { await a.end(.init(state: state, staleDate: nil), dismissalPolicy: durationS == nil ? .immediate : .after(Date().addingTimeInterval(60))) }
    }
}
