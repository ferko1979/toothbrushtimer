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
    @State private var lastResult: BrushingController.Result?

    private var kid: Bool { profile.child }
    private var settings: AppSettings { model.settings }

    var body: some View {
        NavigationStack {
            Group {
                if let rec = record {
                    ResultView(profile: profile, record: rec, achievements: achievements, testLog: controller.testLog,
                               endReason: lastResult?.endReason ?? "finish", manual: lastResult?.manual ?? false,
                               notes: (lastResult?.notes ?? []) + [lastResult?.scrubNote, lastResult?.timerNote].compactMap { $0 },
                               recordingBase: settings.isOn("test_recording", platform: .ios) ? controller.lastRecordingBase : nil,
                               onResume: { resume(rec) }) { dismiss() }
                } else {
                    listening
                }
            }
            .toolbar {
                if record == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Bezárás")) { controller.stop(); dismiss() }
                    }
                }
            }
        }
        .onAppear(perform: begin)
        .onDisappear(perform: end)
        .onChange(of: controller.phase) { _, _ in updateLiveActivity() }
        .onChange(of: controller.wasteIcon) { _, _ in updateLiveActivity() }
        .onChange(of: scenePhase) { _, phase in
            let t = Date().timeIntervalSince(began)
            if phase == .background {
                policy.appBackgrounded(t: t)
                if !policy.listening && controller.isListening && !controller.manual && !controller.testMode {
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
            if controller.testMode {
                Text(tr("🔴 Teszt mód: a felvétel addig megy, amíg le nem állítod")).font(.caption).foregroundStyle(Theme.danger)
            }
            statusBanner
            if controller.testMode || !controller.testLog.isEmpty { TestLogCard(lines: controller.testLog) }
            if !controller.testMode && !controller.testLog.isEmpty && controller.result == nil { TestRecordingShareButton() }
            switch controller.phase {
            case .brushing, .rinsing:
                let p = brushProgress(elapsedS: controller.elapsedS, targetS: profile.goals.targetS)
                if kid { AvatarCircle(emoji: profile.avatarEmoji, size: 70) }
                ProgressRing(fraction: p.fraction, label: formatClock(controller.elapsedS),
                             sublabel: tr("cél: {0}", formatClock(profile.goals.targetS)),
                             color: controller.wasteIcon ? Theme.warn : Theme.brand)
                if profile.canRead { Text(tr("Most: {0} negyed", p.quadrantName)).font(.headline) }
                QuadrantGrid(current: p.quadrant, labels: profile.canRead)
                if profile.brushType.powered, let f0 = controller.liveF0, profile.canRead {
                    Text("🔊 " + SonicDetector.describe(f0Hz: f0)).font(.footnote).foregroundStyle(.secondary)
                }
                if controller.wasteIcon && settings.isOn("water_warnings") {
                    let r = WaterReport(seconds: controller.waterRunningS, locale: settings.waterLocale)
                    Card {
                        Text(tr("Eddig elfolyt")).font(.subheadline).foregroundStyle(.secondary)
                        Text(tr("≈ {0} l", String(format: "%.1f", r.litres))).font(.title.bold()).foregroundStyle(Theme.danger)
                    }
                }
            case .failed(let msg):
                Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(tr("Kézi indítás (időzítő)")) { controller.startManual() }.buttonStyle(.borderedProminent)
            default:
                Spacer()
                Text(kid ? "🚰 → 🪥" : "🪥").font(.system(size: 64))
                if profile.canRead {
                    Text(waitingText).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                if let note = stopNote { Text(tr("Leállt: {0}", note)).font(.footnote).foregroundStyle(Theme.warn) }
                Button(tr("Kézi indítás (időzítő)")) { controller.startManual() }.buttonStyle(.bordered)
            }
            Spacer()
            Button { controller.stop() } label: {
                Text(controller.testMode ? tr("⏹ Felvétel leállítása") : tr("Kész")).font(.headline).frame(maxWidth: .infinity).padding()
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.brand, lineWidth: 2))
            }.buttonStyle(.plain)
        }
        .padding()
        .background(kid ? LinearGradient(colors: [Theme.kidTop, Theme.kidBottom], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(.systemBackground)], startPoint: .top, endPoint: .bottom))
    }

    private var waitingText: String {
        switch controller.phase {
        case .water: return tr("Folyik a víz… Nedvesítsd a fogkefét, majd zárd el a csapot.")
        case .armed: return tr("Várom a fogmosást…")
        default:
            return policy.placed
                ? tr("Figyelek. A telefon maradhat letéve, a képernyő lezárása után is mérek.")
                : tr("Figyelek. Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted.")
        }
    }

    @ViewBuilder private var statusBanner: some View {
        switch controller.phase {
        case .brushing:
            if controller.wasteIcon && settings.isOn("water_warnings") {
                Banner(text: tr("🚰 Folyik a csap! Zárd el, amíg fogat mosol."), color: Theme.danger)
            } else if controller.manual {
                Banner(text: tr("⏱️ Kézi időzítő"), color: Theme.brand)
            } else {
                Banner(text: tr("✅ Fogmosás észlelve · a víz elzárásától mérve"), color: Theme.ok)
            }
        case .rinsing:
            Banner(text: tr("💧 Öblítés…"), color: Theme.brand)
        case .water:
            Banner(text: tr("🚰 Víz"), color: Theme.brand)
        default:
            if armed { Banner(text: tr("🔔 Emlékeztetőből indítva: várom a fogmosást"), color: Theme.brand) }
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
                if !policy.listening && controller.isListening && !controller.manual && !controller.testMode {
                    stopNote = policy.stopReason
                    controller.stop()
                }
            }
        }
        if settings.isOn("live_activity", platform: .ios) {
            LiveActivity.start(name: profile.name, targetS: profile.goals.targetS, child: profile.child)
        }
        controller.targetS = profile.goals.targetS
        controller.cuesEnabled = settings.isOn("quadrant_cues")
        controller.onCue = { cue in Haptics.play(cue.haptic) }
        controller.onActivity = { policy.activity(t: now()) }
        controller.onFinished = { result in finished(result) }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            policy.tick(t: now())
            if !policy.listening && controller.isListening && !controller.manual && !controller.testMode && controller.phase != .brushing {
                stopNote = policy.stopReason
                controller.stop()
            }
        }
        guard settings.isOn("auto_detect"), let heads = model.heads else {
            controller.startManual()
            return
        }
        var sonicCfg = settings.isOn("calibration") && profile.calibration.brushF0 != nil ? profile.calibration.sonicConfig()
            : (profile.brushType == .oscillating ? SonicConfig.oscillating : SonicConfig())
        sonicCfg.lockOn = true
        // Until the goal is reached, stop only after a long silence or a clear rinse; tolerance learned from feedback.
        var sc = policy.sessionConfig
        sc.holdUntilS = profile.goals.targetS
        sc.endQuietS += profile.quietExtraS
        // Manual scrubbing has quieter stretches (up to ~15 s in the test recordings): wait longer.
        if !profile.brushType.powered { sc.endQuietS += 10 }
        sc.holdQuietS += profile.quietExtraS
        sc.sonicSuppressesWater = profile.brushType.powered
        sc.runHysteresis = true
        sc.quietWaterRinseS = 6.0
        sc.wetCue = true
        sc.startAtBrushing = true
        sc.timerSignalWatch = profile.brushType == .oscillating
        sc.sonicStopWatch = profile.brushType.powered
        controller.f0History = profile.calibration.f0s
        controller.timerStopsRecent = model.records(for: profile.id).sorted { $0.start > $1.start }.prefix(10)
            .filter { wasTimerStop(motorS: $0.motorS, afterMotorS: $0.afterMotorS) }.count
        controller.scrubHistory = model.records(for: profile.id).sorted { $0.start < $1.start }.compactMap(\.brushDb)
        controller.manualBrush = !profile.brushType.powered
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let faceDown = UIDevice.current.orientation == .faceDown
        let testing = settings.isOn("test_recording", platform: .ios)
        controller.start(heads: heads, sessionConfig: sc, sonicConfig: sonicCfg,
                         useSonic: profile.brushType.powered, batterySaver: settings.isOn("battery_saver"),
                         nearGateDb: settings.isOn("near_only") ? 10 : nil,
                         towardsScreen: settings.isOn("mic_direction", platform: .ios) ? !faceDown : nil,
                         testRecordTo: testing ? AppModel.recordingsDir : nil,
                         testMeta: ["platform": "ios", "device": UIDevice.current.model, "ios": UIDevice.current.systemVersion,
                                    "brushType": profile.brushType.rawValue, "targetS": profile.goals.targetS,
                                    "quietExtraS": profile.quietExtraS, "faceDown": faceDown, "language": I18n.lang])
    }

    private func updateLiveActivity() {
        let name: String
        switch controller.phase {
        case .water: name = "water"
        case .armed: name = "armed"
        case .brushing: name = "brushing"
        case .rinsing: name = "rinsing"
        case .finished: name = "done"
        default: name = "listening"
        }
        LiveActivity.update(phase: name, elapsedS: controller.elapsedS, waterRunning: controller.wasteIcon)
    }

    /// "Még mostam – folytatás": drop the saved record and keep timing from where it stopped.
    private func resume(_ rec: BrushRecord) {
        model.data.records.removeAll { $0.id == rec.id }
        record = nil
        achievements = []
        controller.startManual(resumeFrom: rec.durationS)
    }

    private func end() {
        LiveActivity.end(durationS: nil)
        ticker?.invalidate()
        motion.stop()
        if controller.isListening { controller.stop() }
    }

    private func finished(_ r: BrushingController.Result) {
        policy.sessionFinished(t: now())
        LiveActivity.end(durationS: r.durationS >= 5 ? r.durationS : nil)
        guard r.durationS >= 5 else {
            stopNote = tr("túl rövid volt ({0} s), nem mentettem", Int(r.durationS))
            return
        }
        lastResult = r
        let rec = BrushRecord(profileId: profile.id, start: r.start, durationS: r.durationS,
                              waterRunningS: r.waterRunningS, source: r.manual ? "manual" : "phone", brushF0: r.brushF0, brushDb: r.brushDb,
                              motorS: r.motorS, afterMotorS: r.afterMotorS)
        achievements = model.add(record: rec)
        record = rec
        model.noteBattery(r.notes, manual: r.manual, brushF0: r.brushF0)
        let fb = feedback(for: profile, durationS: r.durationS, coach: model.coach)
        if settings.isOn("spoken_feedback") && fb.speak { Speaker.shared.say(fb.text) }
    }
}
