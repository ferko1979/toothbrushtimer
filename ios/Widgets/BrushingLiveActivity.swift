import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FogmosasWidgets: WidgetBundle {
    var body: some Widget {
        BrushingLiveActivity()
    }
}

private let brand = Color(red: 0.118, green: 0.608, blue: 0.722)
private let warn = Color(red: 0.910, green: 0.514, blue: 0.227)

private func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

struct BrushingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrushingAttributes.self) { ctx in
            LockScreenView(attrs: ctx.attributes, state: ctx.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("🪥").font(.title) }
                DynamicIslandExpandedRegion(.trailing) {
                    if let st = ctx.state.startedAt {
                        Text(st, style: .timer).font(.title2.monospacedDigit().bold()).frame(maxWidth: 80)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let st = ctx.state.startedAt {
                        ProgressView(timerInterval: st...st.addingTimeInterval(ctx.attributes.targetS), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(ctx.state.waterRunning ? warn : brand)
                        if ctx.state.waterRunning { Text("🚰 Folyik a csap – zárd el!").font(.caption).foregroundStyle(warn) }
                    } else {
                        Text(PhaseText.text(ctx.state)).font(.caption)
                    }
                }
            } compactLeading: {
                Text(ctx.state.waterRunning ? "🚰" : "🪥")
            } compactTrailing: {
                if let st = ctx.state.startedAt {
                    Text(st, style: .timer).monospacedDigit().frame(maxWidth: 44)
                } else if let d = ctx.state.durationS {
                    Text(clock(d)).monospacedDigit()
                } else {
                    Text("…")
                }
            } minimal: {
                Text("🪥")
            }
        }
    }
}

enum PhaseText {
    static func text(_ s: BrushingAttributes.ContentState) -> String {
        switch s.phase {
        case "water": return "🚰 Folyik a víz… Nedvesítsd a fogkefét, majd zárd el a csapot."
        case "armed": return "Várom a fogmosást…"
        case "done": return s.durationS.map { "Kész: \(clock($0))" } ?? "Kész"
        default: return "Figyelek. Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted."
        }
    }
}

struct LockScreenView: View {
    let attrs: BrushingAttributes
    let state: BrushingAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Text(state.phase == "done" ? "🎉" : "🪥").font(.system(size: 40))
            VStack(alignment: .leading, spacing: 6) {
                Text(attrs.child ? attrs.name : "Fogmosás").font(.headline).foregroundStyle(.white)
                if let st = state.startedAt {
                    HStack {
                        Text(st, style: .timer).font(.title.monospacedDigit().bold()).foregroundStyle(.white)
                        Spacer()
                        Text("cél \(clock(attrs.targetS))").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    ProgressView(timerInterval: st...st.addingTimeInterval(attrs.targetS), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(state.waterRunning ? warn : brand)
                    if state.waterRunning { Text("🚰 Folyik a csap – zárd el!").font(.caption).foregroundStyle(warn) }
                } else {
                    Text(PhaseText.text(state)).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
}
