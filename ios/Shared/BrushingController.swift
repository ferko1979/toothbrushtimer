import BrushCore
import Foundation

/// Runs one listening period: microphone -> StreamingDetector -> session,
/// publishes the state for the UI and fires the quadrant cues.
final class BrushingController: ObservableObject {
    enum Phase: Equatable { case idle, listening, water, armed, brushing, rinsing, finished, failed(String) }

    struct Result: Equatable {
        let start: Date
        let durationS: Double
        let waterRunningS: Double
        let cue: String
        let brushF0: Double?
        let manual: Bool
        /// rinse, quiet, user or finish
        var endReason = "finish"
        /// Electric brush: battery notes (motor stopped / slowed down).
        var notes: [String] = []
        /// Typical scrubbing loudness and the "too hard" note (manual brush).
        var brushDb: Double? = nil
        var scrubNote: String? = nil
        /// Electric brush: how long the motor ran before it stopped, the manual brushing after it, and
        /// the brush's own timer note (stopped the motor / signalled; not a battery problem).
        var motorS: Double? = nil
        var afterMotorS: Double? = nil
        var timerNote: String? = nil
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedS: Double = 0
    @Published private(set) var wasteIcon = false
    @Published private(set) var waterRunningS: Double = 0
    @Published private(set) var liveF0: Double?
    @Published private(set) var result: Result?
    @Published private(set) var manual = false
    /// Test mode: what the detector noticed (shown live) and the session it measured on its own.
    @Published private(set) var testMode = false
    @Published private(set) var testLog: [String] = []
    @Published private(set) var testResult: Result?
    /// Name of the newest test recording (the tester's remark is saved next to it).
    private(set) var lastRecordingBase: String?

    var targetS: Double = 120
    /// Earlier sessions' motor frequencies (battery trend); set before start().
    var f0History: [Double] = []
    /// Earlier brushings' scrubbing loudness and whether the brush is manual; set before start().
    var scrubHistory: [Double] = []
    /// Recent brushings where the brush's own timer stopped the motor and the user went on by hand.
    var timerStopsRecent = 0
    var manualBrush = false
    var cuesEnabled = true
    var onCue: ((Cue) -> Void)?
    var onActivity: (() -> Void)?
    var onFinished: ((Result) -> Void)?
    /// A test recording is written: the app uploads it.
    var onRecordingSaved: (() -> Void)?

    private let queue = DispatchQueue(label: "brushdetect.detector")
    private let capture = AudioCapture()
    private var detector: StreamingDetector?
    private var cueTracker: CueTracker?
    private var f0s: [Double] = []
    private var listenStarted = Date()
    private var manualStart: Date?
    private var manualTimer: Timer?
    private var userStop = false
    private var recording: TestRecording?
    private var recordDir: URL?

    var isListening: Bool { capture.isRunning || manualStart != nil }

    /// testRecordTo: test mode: record audio + timeline there, keep listening until the tester stops.
    func start(heads: ModelHeads, sessionConfig: SessionConfig, sonicConfig: SonicConfig,
               useSonic: Bool, batterySaver: Bool, nearGateDb: Double? = nil, towardsScreen: Bool? = nil,
               testRecordTo: URL? = nil, testMeta: [String: Any] = [:]) {
        guard !isListening else { return }
        reset()
        let det = StreamingDetector(heads: heads, sessionConfig: sessionConfig, sonicConfig: sonicConfig,
                                    useSonic: useSonic, batterySaver: batterySaver, nearGateDb: nearGateDb)
        recordDir = testRecordTo
        testMode = testRecordTo != nil
        recording = testRecordTo.flatMap { try? TestRecording(directory: $0, meta: testMeta.merging(["useSonic": useSonic]) { a, _ in a }) }
        if let r = recording { lastRecordingBase = r.base }
        #if os(iOS)
        capture.towardsScreen = towardsScreen
        #endif
        det.onRow = { [weak self, weak det] row in
            guard let det = det else { return }
            self?.recording?.row(row, state: det.session.state.rawValue, rmsDb: det.lastRmsDb)
            self?.handle(row: row, detector: det)
        }
        det.session.onEvent = { [weak self, weak det] t, e in
            guard let det = det else { return }
            self?.recording?.event(t, e.rawValue)
            self?.handle(event: e, at: t, detector: det)
        }
        detector = det
        userStop = false
        listenStarted = Date()
        AudioCapture.requestPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.phase = .failed(tr("A mikrofon-hozzáférés nincs engedélyezve. Beállítások → Adatvédelem → Mikrofon."))
                return
            }
            do {
                try self.capture.start { [weak self] samples in
                    self?.queue.async {
                        det.append(samples)
                        self?.recording?.append(samples)
                    }
                }
                self.phase = .listening
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stop listening; an open session is closed and reported.
    func stop() {
        if manualStart != nil {
            stopManual()
            return
        }
        userStop = true
        capture.stop()
        guard let det = detector else { return }
        queue.async { [weak self] in
            det.finish()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.testMode {
                    // The tester ended the recording: report what the detector measured on its own.
                    self.testMode = false
                    if let r = self.testResult { self.finish(with: r) } else { self.closeRecording(nil) }
                }
                if self.result == nil && self.phase != .finished { self.phase = .idle }
                self.detector = nil
            }
        }
    }

    /// Watch on the brushing hand: wrist-rhythm score as brushing evidence.
    func setMotionBrush(_ score: Double) {
        guard let det = detector else { return }
        queue.async { det.motionBrush = score }
    }

    /// Fallback: plain timer without detection ("Kézi indítás").
    func startManual(resumeFrom fromS: Double = 0) {
        capture.stop()
        detector = nil
        reset()
        manual = true
        manualStart = Date().addingTimeInterval(-fromS)
        cueTracker = CueTracker(targetS: targetS)
        if fromS > 0 { _ = cueTracker?.update(elapsedS: fromS) }
        phase = .brushing
        manualTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, let st = self.manualStart else { return }
            self.elapsedS = Date().timeIntervalSince(st)
            self.fireCues()
        }
    }

    private func stopManual() {
        guard let st = manualStart else { return }
        manualTimer?.invalidate()
        manualTimer = nil
        manualStart = nil
        let r = Result(start: st, durationS: Date().timeIntervalSince(st), waterRunningS: 0, cue: "manual",
                       brushF0: nil, manual: true, endReason: "user")
        finish(with: r)
    }

    private func reset() {
        queue.sync { f0s = [] }
        elapsedS = 0
        wasteIcon = false
        waterRunningS = 0
        liveF0 = nil
        result = nil
        manual = false
        cueTracker = nil
        testLog = []
        testResult = nil
    }

    private func fireCues() {
        guard cuesEnabled, let tracker = cueTracker else { return }
        for c in tracker.update(elapsedS: elapsedS) { onCue?(c) }
    }

    // Called on the detector queue.
    private func handle(row: ScoreRow, detector det: StreamingDetector) {
        let s = det.session
        let current = s.current
        if s.state == .brushing && row.sonic > 0.5 && row.sonicF0 > 0 { f0s.append(row.sonicF0) }
        let elapsed = current.map { Swift.max(det.audioTime - $0.start, 0) } ?? 0
        let water = current?.waterRunningS ?? 0
        let state = s.state
        let waste = s.wasteIcon
        let activity = row.water > 0.5 || row.brush > 0.5 || row.sonic > 0.5
        let medianF0: Double? = f0s.isEmpty ? nil : f0s.sorted()[f0s.count / 2]
        DispatchQueue.main.async {
            if activity { self.onActivity?() }
            guard self.result == nil else { return }
            switch state {
            case .listening: self.phase = .listening
            case .water: self.phase = .water
            case .armed: self.phase = .armed
            case .brushing: self.phase = .brushing
            case .rinse: self.phase = .rinsing
            }
            self.elapsedS = elapsed
            self.waterRunningS = water
            self.wasteIcon = waste
            self.liveF0 = medianF0
            if state == .brushing || state == .rinse { self.fireCues() }
        }
    }

    private func makeResult(of session: BrushingSession, brushF0: Double?, reason: String) -> Result {
        let motor = motorRunS(session)
        return Result(start: listenStarted.addingTimeInterval(session.start), durationS: session.durationS,
                      waterRunningS: session.waterRunningS, cue: session.cue, brushF0: brushF0, manual: false, endReason: reason,
                      notes: brushPowerNotes(session, history: f0History), brushDb: session.brushLevelDb,
                      scrubNote: scrubNote(brushDb: session.brushLevelDb, history: scrubHistory, manual: manualBrush),
                      motorS: motor, afterMotorS: motor == nil ? nil : session.manualAfterSonicS,
                      timerNote: brushTimerNote(session, earlierTimerStops: timerStopsRecent))
    }

    // Called on the detector queue.
    private func handle(event: SessionEvent, at t: Double, detector det: StreamingDetector) {
        if testMode {
            let clock = formatClock(t)
            if event == .sessionEnd, let session = det.session.sessions.last {
                let reason = session.endReason == "finish" && userStop ? "user" : session.endReason
                let r = makeResult(of: session, brushF0: nil, reason: reason)
                DispatchQueue.main.async {
                    if self.testResult == nil || r.durationS > self.testResult!.durationS { self.testResult = r }
                    self.testLog.append(clock + " " + tr("🏁 vége – mért idő: {0}", formatClock(r.durationS)))
                    Haptics.play(.success)
                }
            } else if let label = testLabel(event) {
                DispatchQueue.main.async {
                    if event == .brushingDetected { self.cueTracker = CueTracker(targetS: self.targetS); Haptics.play(.tap) }
                    self.testLog.append(clock + " " + label)
                }
            }
            return
        }
        switch event {
        case .brushingDetected:
            DispatchQueue.main.async { self.cueTracker = CueTracker(targetS: self.targetS) }
        case .wasteIconOn:
            DispatchQueue.main.async { Haptics.warning() }
        case .sessionEnd:
            guard let session = det.session.sessions.last else { return }
            let f0 = f0s.count >= 4 ? f0s.sorted()[f0s.count / 2] : nil
            let reason = session.endReason == "finish" && userStop ? "user" : session.endReason
            let r = makeResult(of: session, brushF0: f0, reason: reason)
            DispatchQueue.main.async {
                self.capture.stop()
                self.finish(with: r)
            }
        default:
            break
        }
    }

    private func closeRecording(_ r: Result?) {
        guard let rec = recording else { return }
        recording = nil
        let dir = recordDir
        var res: [String: Any] = ["endReason": r?.endReason ?? "no_session"]
        if let r = r { res["durationS"] = r.durationS; res["cue"] = r.cue; res["waterRunningS"] = r.waterRunningS; res["manual"] = r.manual }
        queue.async {
            rec.finish(result: res)
            if let d = dir { TestRecording.prune(in: d) }
            DispatchQueue.main.async { self.onRecordingSaved?() }
        }
    }

    private func testLabel(_ e: SessionEvent) -> String? {
        switch e {
        case .waterStart: return tr("🚰 víz")
        case .waterStop: return tr("víz elzárva")
        case .brushingDetected: return tr("🪥 fogmosás észlelve")
        case .rinseStart: return tr("💧 öblítés")
        case .brushingResumed: return tr("🪥 folytatódik")
        case .wasteIconOn: return tr("⚠️ folyik a csap")
        case .brushWet: return tr("💦 fogkefe nedvesítése")
        case .sonicStopped: return tr("🔋 a fogkefe motorja leállt")
        case .sonicResumed: return tr("🔋 a motor újra zúg")
        case .timerSignal: return tr("⏱ a fogkefe jelzett")
        default: return nil
        }
    }

    private func finish(with r: Result) {
        guard result == nil else { return }
        closeRecording(r)
        result = r
        elapsedS = r.durationS
        phase = .finished
        onFinished?(r)
    }
}
