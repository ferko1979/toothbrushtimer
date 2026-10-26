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
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedS: Double = 0
    @Published private(set) var wasteIcon = false
    @Published private(set) var waterRunningS: Double = 0
    @Published private(set) var liveF0: Double?
    @Published private(set) var result: Result?
    @Published private(set) var manual = false

    var targetS: Double = 120
    var cuesEnabled = true
    var onCue: ((Cue) -> Void)?
    var onActivity: (() -> Void)?
    var onFinished: ((Result) -> Void)?

    private let queue = DispatchQueue(label: "brushdetect.detector")
    private let capture = AudioCapture()
    private var detector: StreamingDetector?
    private var cueTracker: CueTracker?
    private var f0s: [Double] = []
    private var listenStarted = Date()
    private var manualStart: Date?
    private var manualTimer: Timer?

    var isListening: Bool { capture.isRunning || manualStart != nil }

    func start(heads: ModelHeads, sessionConfig: SessionConfig, sonicConfig: SonicConfig,
               useSonic: Bool, batterySaver: Bool) {
        guard !isListening else { return }
        reset()
        let det = StreamingDetector(heads: heads, sessionConfig: sessionConfig, sonicConfig: sonicConfig,
                                    useSonic: useSonic, batterySaver: batterySaver)
        det.onRow = { [weak self, weak det] row in
            guard let det = det else { return }
            self?.handle(row: row, detector: det)
        }
        det.session.onEvent = { [weak self, weak det] t, e in
            guard let det = det else { return }
            self?.handle(event: e, at: t, detector: det)
        }
        detector = det
        listenStarted = Date()
        AudioCapture.requestPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.phase = .failed("A mikrofon-hozzáférés nincs engedélyezve. Beállítások → Adatvédelem → Mikrofon.")
                return
            }
            do {
                try self.capture.start { [weak self] samples in
                    self?.queue.async { det.append(samples) }
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
        capture.stop()
        guard let det = detector else { return }
        queue.async { [weak self] in
            det.finish()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.result == nil && self.phase != .finished { self.phase = .idle }
                self.detector = nil
            }
        }
    }

    /// Fallback: plain timer without detection ("Kézi indítás").
    func startManual() {
        capture.stop()
        detector = nil
        reset()
        manual = true
        manualStart = Date()
        cueTracker = CueTracker(targetS: targetS)
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
                       brushF0: nil, manual: true)
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
    }

    private func fireCues() {
        guard cuesEnabled, let tr = cueTracker else { return }
        for c in tr.update(elapsedS: elapsedS) { onCue?(c) }
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

    // Called on the detector queue.
    private func handle(event: SessionEvent, at t: Double, detector det: StreamingDetector) {
        switch event {
        case .brushingDetected:
            DispatchQueue.main.async { self.cueTracker = CueTracker(targetS: self.targetS) }
        case .wasteIconOn:
            DispatchQueue.main.async { Haptics.warning() }
        case .sessionEnd:
            guard let session = det.session.sessions.last else { return }
            let f0 = f0s.count >= 4 ? f0s.sorted()[f0s.count / 2] : nil
            let start = listenStarted.addingTimeInterval(session.start)
            let r = Result(start: start, durationS: session.durationS, waterRunningS: session.waterRunningS,
                           cue: session.cue, brushF0: f0, manual: false)
            DispatchQueue.main.async {
                self.capture.stop()
                self.finish(with: r)
            }
        default:
            break
        }
    }

    private func finish(with r: Result) {
        guard result == nil else { return }
        result = r
        elapsedS = r.durationS
        phase = .finished
        onFinished?(r)
    }
}
