import BrushCore
import SwiftUI

/// One brushing: listens (policy + detector), shows progress, then the result.
struct BrushingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let profile: Profile
    let armed: Bool

    @StateObject private var controller = BrushingController()
    @State private var policy = ListeningPolicy()
    @State private var motion = MotionMonitor()
    @State private var ticker: Timer?
    @State private var began = Date()
    @State private var record: BrushRecord?
    @State private var achievements: [Achievement] = []
    @State private var stopNote: String?

    private var kid: Bool { profile.child }
    private var settings: AppSettings { model.settings }

    var body: some View {
        NavigationStack {
            Group {
                if let rec = record {
                    ResultView(profile: profile, record: rec, achievements: achievements) { dismiss() }
                } else {
                    listening
                }
            }
            .toolbar {
                if record == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Bezárás") { controller.stop(); dismiss() }
                    }
                }
            }
        }
        .onAppear(perform: begin)
        .onDisappear(perform: end)
        .onChange(of: scenePhase) { _, phase in
            let t = Date().timeIntervalSince(began)
            if phase == .background {
                policy.appBackgrounded(t: t)
                if !policy.listening && controller.isListening && !controller.manual {
                    stopNote = policy.stopReason
                    controller.stop()
                }
            } else if phase == .active {
                policy.appForegrounded(t: t)
            }
        }
    }

    // MARK: - Listening screen

    private var listening: some View {
        VStack(spacing: 18) {
            statusBanner
            switch controller.phase {
            case .brushing, .rinsing:
                let p = brushProgress(elapsedS: controller.elapsedS, targetS: profile.goals.targetS)
                if kid { AvatarCircle(emoji: profile.avatarEmoji, size: 70) }
                ProgressRing(fraction: p.fraction, label: formatClock(controller.elapsedS),
                             sublabel: "cél: \(formatClock(profile.goals.targetS))",
                             color: controller.wasteIcon ? Theme.warn : Theme.brand)
                if profile.canRead { Text("Most: \(p.quadrantName) negyed").font(.headline) }
                QuadrantGrid(current: p.quadrant, labels: profile.canRead)
                if profile.brushType == .electric, let f0 = controller.liveF0, profile.canRead {
                    Text("🔊 " + SonicDetector.describe(f0Hz: f0)).font(.footnote).foregroundStyle(.secondary)
                }
                if controller.wasteIcon && settings.isOn("water_warnings") {
                    let r = WaterReport(seconds: controller.waterRunningS, locale: settings.waterLocale)
                    Card {
                        Text("Eddig elfolyt").font(.subheadline).foregroundStyle(.secondary)
                        Text("≈ \(String(format: "%.1f", r.litres)) l").font(.title.bold()).foregroundStyle(Theme.danger)
                    }
                }
            case .failed(let msg):
                Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Kézi indítás (időzítő)") { controller.startManual() }.buttonStyle(.borderedProminent)
            default:
                Spacer()
                Text(kid ? "🚰 → 🪥" : "🪥").font(.system(size: 64))
                if profile.canRead {
                    Text(waitingText).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                if let note = stopNote { Text("Leállt: \(note)").font(.footnote).foregroundStyle(Theme.warn) }
                Button("Kézi indítás (időzítő)") { controller.startManual() }.buttonStyle(.bordered)
            }
            Spacer()
            Button { controller.stop() } label: {
                Text("Kész").font(.headline).frame(maxWidth: .infinity).padding()
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.brand, lineWidth: 2))
            }.buttonStyle(.plain)
        }
        .padding()
        .background(kid ? LinearGradient(colors: [Theme.kidTop, Theme.kidBottom], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(.systemBackground)], startPoint: .top, endPoint: .bottom))
    }

    private var waitingText: String {
        switch controller.phase {
        case .water: return "Folyik a víz… Nedvesítsd a fogkefét, majd zárd el a csapot."
        case .armed: return "Várom a fogmosást…"
        default:
            return policy.placed
                ? "Figyelek. A telefon maradhat letéve, a képernyő lezárása után is mérek."
                : "Figyelek. Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted."
        }
    }

    @ViewBuilder private var statusBanner: some View {
        switch controller.phase {
        case .brushing:
            if controller.wasteIcon && settings.isOn("water_warnings") {
                Banner(text: "🚰 Folyik a csap! Zárd el, amíg fogat mosol.", color: Theme.danger)
            } else if controller.manual {
                Banner(text: "⏱️ Kézi időzítő", color: Theme.brand)
            } else {
                Banner(text: "✅ Fogmosás észlelve · a víz elzárásától mérve", color: Theme.ok)
            }
        case .rinsing:
            Banner(text: "💧 Öblítés…", color: Theme.brand)
        case .water:
            Banner(text: "🚰 Víz", color: Theme.brand)
        default:
            if armed { Banner(text: "🔔 Emlékeztetőből indítva: várom a fogmosást", color: Theme.brand) }
        }
    }

    // MARK: - Lifecycle

    private func now() -> Double { Date().timeIntervalSince(began) }

    private func begin() {
        began = Date()
        policy.appOpened(t: 0, fromNotification: armed)
        if settings.isOn("keep_listening_when_placed", platform: .ios) {
            motion.start { gx, gy, gz in
                policy.motion(t: now(), gx: gx, gy: gy, gz: gz)
                if !policy.listening && controller.isListening && !controller.manual {
                    stopNote = policy.stopReason
                    controller.stop()
                }
            }
        }
        controller.targetS = profile.goals.targetS
        controller.cuesEnabled = settings.isOn("quadrant_cues")
        controller.onCue = { cue in Haptics.play(cue.haptic) }
        controller.onActivity = { policy.activity(t: now()) }
        controller.onFinished = { result in finished(result) }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            policy.tick(t: now())
            if !policy.listening && controller.isListening && !controller.manual && controller.phase != .brushing {
                stopNote = policy.stopReason
                controller.stop()
            }
        }
        guard settings.isOn("auto_detect"), let heads = model.heads else {
            controller.startManual()
            return
        }
        let sonicCfg = settings.isOn("calibration") ? profile.calibration.sonicConfig() : SonicConfig()
        controller.start(heads: heads, sessionConfig: policy.sessionConfig, sonicConfig: sonicCfg,
                         useSonic: profile.brushType == .electric, batterySaver: settings.isOn("battery_saver"))
    }

    private func end() {
        ticker?.invalidate()
        motion.stop()
        if controller.isListening { controller.stop() }
    }

    private func finished(_ r: BrushingController.Result) {
        policy.sessionFinished(t: now())
        guard r.durationS >= 5 else {
            stopNote = "túl rövid volt (\(Int(r.durationS)) s), nem mentettem"
            return
        }
        let rec = BrushRecord(profileId: profile.id, start: r.start, durationS: r.durationS,
                              waterRunningS: r.waterRunningS, source: r.manual ? "manual" : "phone", brushF0: r.brushF0)
        achievements = model.add(record: rec)
        record = rec
        let fb = feedback(for: profile, durationS: r.durationS, coach: model.coach)
        if settings.isOn("spoken_feedback") && fb.speak { Speaker.shared.say(fb.text) }
    }
}
