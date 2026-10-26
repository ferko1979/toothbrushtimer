import BrushCore
import SwiftUI

private let brand = Color(red: 0.341, green: 0.773, blue: 0.714)

struct WatchHomeView: View {
    @EnvironmentObject var model: WatchModel
    @State private var brushing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("🪥").font(.system(size: 40))
                let count = model.coach.todayCount(model.records, today: Date())
                let streak = model.coach.perfectStreak(model.records, goals: model.goals, today: Date())
                Text("Ma \(count)/\(model.goals.perDay) · 🔥 \(streak)").font(.footnote).foregroundStyle(.secondary)
                Button("Indítás") { brushing = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.118, green: 0.608, blue: 0.722))
            }
            .navigationTitle("Fogmosás")
            .fullScreenCover(isPresented: $brushing) {
                WatchBrushingView().environmentObject(model)
            }
        }
    }
}

struct WatchBrushingView: View {
    @EnvironmentObject var model: WatchModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = BrushingController()
    @State private var runtime = ExtendedSession()

    var body: some View {
        Group {
            if let r = controller.result {
                result(r)
            } else {
                live
            }
        }
        .onAppear(perform: begin)
        .onDisappear {
            if controller.isListening { controller.stop() }
            runtime.stop()
        }
    }

    private var live: some View {
        VStack(spacing: 6) {
            switch controller.phase {
            case .brushing, .rinsing:
                let p = brushProgress(elapsedS: controller.elapsedS, targetS: model.goals.targetS)
                Text(p.quadrantName).font(.caption2).foregroundStyle(.secondary)
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.3), lineWidth: 10)
                    Circle().trim(from: 0, to: max(0.001, p.fraction))
                        .stroke(controller.wasteIcon ? Color.orange : brand, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(formatClock(controller.elapsedS)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .frame(width: 120, height: 120)
                if controller.wasteIcon { Text("🚰 Folyik a csap!").font(.caption2).foregroundStyle(.orange) }
            case .failed(let msg):
                Text(msg).font(.footnote).multilineTextAlignment(.center)
                Button("Időzítő") { controller.startManual() }
            default:
                Text(controller.phase == .water ? "🚰" : "🚰 → 🪥").font(.title)
                Text("Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Időzítő") { controller.startManual() }.font(.footnote)
            }
            Button("Kész") { controller.stop() }.font(.footnote)
        }
    }

    private func result(_ r: BrushingController.Result) -> some View {
        VStack(spacing: 6) {
            Text(r.durationS >= model.goals.targetS ? "🎉" : "💪").font(.system(size: 34))
            Text(formatClock(r.durationS)).font(.title3.bold())
            Text(r.durationS >= model.goals.targetS ? "Cél elérve" : "Még \(Int(model.goals.targetS - r.durationS)) s hiányzott")
                .font(.caption2).foregroundStyle(.secondary)
            Text(r.waterRunningS >= 5 ? "🚰 folyt a csap" : "💧 elzárt csap").font(.caption2)
            Button("Kész") { dismiss() }
        }
    }

    private func begin() {
        runtime.start()
        controller.targetS = model.goals.targetS
        controller.onCue = { cue in Haptics.play(cue.haptic) }
        controller.onFinished = { r in
            if r.durationS >= 5 { model.add(r) }
            Haptics.play(.success)
            runtime.stop()
        }
        if let heads = model.heads {
            // The watch does not know the brush type: listen for both scrubbing and sonic hum.
            controller.start(heads: heads, sessionConfig: SessionConfig(), sonicConfig: SonicConfig(),
                             useSonic: true, batterySaver: true)
        } else {
            controller.startManual()
        }
    }
}
