import BrushCore
import CoreMotion
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
                Text(tr("Ma {0}/{1} · 🔥 {2}", count, model.goals.perDay, streak)).font(.footnote).foregroundStyle(.secondary)
                Button(tr("Indítás")) { brushing = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.118, green: 0.608, blue: 0.722))
            }
            .navigationTitle("DentHub-Brush")
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
    @State private var motion = CMMotionManager()
    @State private var rhythm = MotionRhythm()
    @State private var side = SideBalance()
    @State private var floss = false
    @State private var bleed = false
    @State private var sens = false

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
            motion.stopDeviceMotionUpdates()
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
                if controller.wasteIcon { Text(tr("🚰 Folyik a csap!")).font(.caption2).foregroundStyle(.orange) }
            case .failed(let msg):
                Text(msg).font(.footnote).multilineTextAlignment(.center)
                Button(tr("Időzítő")) { controller.startManual() }
            default:
                Text(controller.phase == .water ? "🚰" : "🚰 → 🪥").font(.title)
                Text(tr("Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted."))
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(tr("Időzítő")) { controller.startManual() }.font(.footnote)
            }
            Button(tr("Kész")) { controller.stop() }.font(.footnote)
        }
    }

    private func result(_ r: BrushingController.Result) -> some View {
        ScrollView { VStack(spacing: 6) {
            Text(r.durationS >= model.goals.targetS ? "🎉" : "💪").font(.system(size: 34))
            Text(formatClock(r.durationS)).font(.title3.bold())
            Text(r.durationS >= model.goals.targetS ? tr("Cél elérve") : tr("Még {0} s hiányzott", Int(model.goals.targetS - r.durationS)))
                .font(.caption2).foregroundStyle(.secondary)
            Text(r.waterRunningS >= 5 ? tr("🚰 folyt a csap") : tr("💧 elzárt csap")).font(.caption2)
            if model.placement.useMotion, let n = side.note() {
                Text(n).font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            if let n = r.notes.first { Text(n).font(.caption2).multilineTextAlignment(.center).foregroundStyle(.orange) }
            // Quick journal: floss, bleeding gums, sensitivity (saved on the phone).
            HStack(spacing: 4) {
                toggle("🧵", $floss, tr("Fogselyem"))
                toggle("🩸", $bleed, tr("Vérzett az íny"))
                toggle("⚡", $sens, tr("Érzékeny fog"))
            }
            Button(tr("Kész")) {
                model.addCare(floss: floss, bleeding: bleed, sensitive: sens)
                dismiss()
            }
        } }
    }

    private func toggle(_ icon: String, _ on: Binding<Bool>, _ label: String) -> some View {
        Button { on.wrappedValue.toggle() } label: { Text(icon) }
            .tint(on.wrappedValue ? brand : .gray)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(label)
            .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
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
            var sc = SessionConfig()
            sc.holdUntilS = model.goals.targetS
            sc.sonicSuppressesWater = true
            sc.runHysteresis = true
            sc.quietWaterRinseS = 6.0
            sc.wetCue = true
            sc.startAtBrushing = true
            sc.sonicStopWatch = true
            // The watch does not know the brush type: listen from Oral-B's low hum up to sonic brushes.
            var son = SonicConfig()
            son.bandLowHz = 60
            son.lockOn = true
            let place = model.placement
            if place.useMotion && motion.isDeviceMotionAvailable {
                rhythm.reset()
                side.reset()
                var n = 0
                motion.deviceMotionUpdateInterval = 1.0 / 50
                motion.startDeviceMotionUpdates(to: .main) { m, _ in
                    guard let m = m else { return }
                    let a = m.userAcceleration
                    rhythm.add(a.x, a.y, a.z)
                    side.add(gx: m.gravity.x, dt: 1.0 / 50, brushing: controller.phase == .brushing, elapsedS: controller.elapsedS)
                    n += 1
                    if n % 25 == 0 { controller.setMotionBrush(rhythm.score()) }
                }
            }
            controller.start(heads: heads, sessionConfig: sc, sonicConfig: son,
                             useSonic: true, batterySaver: true, nearGateDb: place.nearGateDb)
        } else {
            controller.startManual()
        }
    }
}
