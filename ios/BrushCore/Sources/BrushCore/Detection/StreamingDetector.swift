import Foundation

/// One aligned detector output every 0.5 s (water-window grid, like pipeline.py).
public struct ScoreRow: Equatable {
    public let t: Double       // water-window centre (s from start of listening)
    public let brush: Double   // smoothed brushing probability
    public let water: Double   // water probability
    public let sonic: Double   // sonic-hum score (0 when disabled)
    public let sonicF0: Double
}

/// Real-time version of analysis/brushdetect/pipeline.py + session.py.
///
/// Feed 16 kHz mono samples with `append`. Every 0.5 s of audio produces one
/// ScoreRow, with ~1 s latency because the 3 s brushing window centred on that
/// moment needs 1 s of future audio. Rows drive the SessionDetector.
/// Not thread-safe: call from one serial queue.
public final class StreamingDetector {
    public let heads: ModelHeads
    public let session: SessionDetector
    public var useSonic: Bool
    public var onRow: ((ScoreRow) -> Void)?

    private let mel = LogMelExtractor()
    private let brushEx = WindowFeatureExtractor(win: WindowFeatureExtractor.brushWindow)
    private let waterEx = WindowFeatureExtractor(win: WindowFeatureExtractor.waterWindow)
    private let sonic: SonicDetector
    private let gate: EnergyGate?

    // Audio buffer (absolute sample index of samples[0] = bufferStart).
    private var samples: [Double] = []
    private var bufferStart = 0
    private var totalSamples = 0

    // Log-mel frames (absolute frame index of frames[0] = framesStart).
    private var frames: [[Double]] = []
    private var framesStart = 0
    private var frameCount = 0

    private var waterCount = 0
    private var brushRaw: [Double] = []
    private var brushSmoothed: [Double] = []
    private var sonicScores: [SonicResult] = []
    private var pendingWater: [Double] = []  // water probabilities not yet emitted
    private var emitted = 0
    private var gateOpen = true

    public static let hopS = 0.5

    public init(heads: ModelHeads, sessionConfig: SessionConfig = SessionConfig(),
                sonicConfig: SonicConfig = SonicConfig(), useSonic: Bool = true, batterySaver: Bool = false) {
        self.heads = heads
        self.session = SessionDetector(cfg: sessionConfig)
        self.sonic = SonicDetector(cfg: sonicConfig)
        self.useSonic = useSonic
        self.gate = batterySaver ? EnergyGate() : nil
    }

    /// Seconds of audio processed so far.
    public var audioTime: Double { Double(totalSamples) / Double(Audio.sampleRate) }

    public func append(_ newSamples: [Float]) {
        samples.reserveCapacity(samples.count + newSamples.count)
        for v in newSamples { samples.append(Double(v)) }
        totalSamples += newSamples.count
        process()
    }

    private func sampleSlice(_ absStart: Int, _ count: Int) -> ArraySlice<Double> {
        let s = absStart - bufferStart
        return samples[s..<(s + count)]
    }

    private func process() {
        let nfft = LogMelExtractor.nfft
        let hop = LogMelExtractor.hop
        // 1. log-mel frames
        while frameCount * hop + nfft <= totalSamples {
            frames.append(mel.frame(sampleSlice(frameCount * hop, nfft)))
            frameCount += 1
        }
        // 2. water windows (1 s) and brushing windows (3 s), 0.5 s hop
        let hf = WindowFeatureExtractor.hopFrames
        while waterCount * hf + WindowFeatureExtractor.waterWindow <= frameCount {
            let s = waterCount * hf - framesStart
            updateGate(forWindow: waterCount)
            let p = gateOpen
                ? heads.water.predict(waterEx.features(frames[s..<(s + WindowFeatureExtractor.waterWindow)]))
                : 0
            pendingWater.append(p)
            waterCount += 1
        }
        while brushRaw.count * hf + WindowFeatureExtractor.brushWindow <= frameCount {
            let s = brushRaw.count * hf - framesStart
            let p = gateOpen
                ? heads.brush.predict(brushEx.features(frames[s..<(s + WindowFeatureExtractor.brushWindow)]))
                : 0
            brushRaw.append(p)
            let n = Swift.min(5, brushRaw.count)
            brushSmoothed.append(brushRaw.suffix(n).reduce(0, +) / Double(n))
        }
        // 3. sonic windows (3 s of raw audio), 0.5 s hop
        while sonicScores.count * SonicDetector.hopSamples + SonicDetector.windowSamples <= totalSamples {
            let st = sonicScores.count * SonicDetector.hopSamples
            if useSonic && gateOpen {
                sonicScores.append(sonic.process(sampleSlice(st, SonicDetector.windowSamples)))
            } else {
                sonicScores.append(SonicResult(score: 0, f0Hz: 0, prominenceDb: 0, noveltyDb: 0))
            }
        }
        emitRows(final: false)
        trimBuffers()
    }

    /// Row k (water window k, centre 0.5k + 0.5 s) uses brushing/sonic window k - 2
    /// (same centre); before 1.5 s there is no brushing window yet -> 0.
    private func emitRows(final: Bool) {
        while emitted < waterCount {
            let k = emitted
            let j = k - 2
            var brush = 0.0, son = 0.0, f0 = 0.0
            if j >= 0 {
                if j < brushSmoothed.count {
                    brush = brushSmoothed[j]
                } else if final, let last = brushSmoothed.last {
                    brush = last
                } else if !final {
                    return  // wait for the brushing window
                }
                if j < sonicScores.count {
                    son = sonicScores[j].score
                    f0 = sonicScores[j].f0Hz
                } else if let last = sonicScores.last {
                    son = last.score
                    f0 = last.f0Hz
                }
            }
            let row = ScoreRow(t: 0.5 * Double(k) + 0.5, brush: brush, water: pendingWater[k - (waterCount - pendingWater.count)],
                               sonic: son, sonicF0: f0)
            emitted += 1
            session.update(t: row.t + StreamingDetector.hopS / 2, water: row.water, brush: row.brush,
                           sonic: row.sonic, dt: StreamingDetector.hopS)
            onRow?(row)
        }
    }

    private func updateGate(forWindow k: Int) {
        guard let gate = gate else { return }
        // RMS of the newest 0.5 s of audio covered by this water window.
        let endSample = (k * WindowFeatureExtractor.hopFrames + WindowFeatureExtractor.waterWindow) * LogMelExtractor.hop
        let n = Audio.sampleRate / 2
        let st = Swift.max(endSample - n, bufferStart)
        let len = Swift.min(n, totalSamples - st)
        guard len > 0 else { return }
        var e = 0.0
        for v in sampleSlice(st, len) { e += v * v }
        let db = 10 * log10(e / Double(len) + 1e-12)
        gateOpen = gate.update(t: 0.5 * Double(k) + 0.5, rmsDb: db)
    }

    private func trimBuffers() {
        // Keep the audio still needed by the next mel frame and the next sonic window.
        let needSample = Swift.min(frameCount * LogMelExtractor.hop, sonicScores.count * SonicDetector.hopSamples)
        let dropS = needSample - bufferStart
        if dropS > 32000 {
            samples.removeFirst(dropS)
            bufferStart += dropS
        }
        // Keep the frames needed by the next brushing window (the longest).
        let needFrame = Swift.min(brushRaw.count, waterCount) * WindowFeatureExtractor.hopFrames
        let dropF = needFrame - framesStart
        if dropF > 200 {
            frames.removeFirst(dropF)
            framesStart += dropF
        }
        // Emitted water probabilities are no longer needed.
        let dropW = pendingWater.count - (waterCount - emitted)
        if dropW > 50 {
            pendingWater.removeFirst(dropW)
        }
    }

    /// End of listening: emit the remaining rows and close the session.
    @discardableResult
    public func finish() -> [BrushingSession] {
        emitRows(final: true)
        return session.finish()
    }
}
