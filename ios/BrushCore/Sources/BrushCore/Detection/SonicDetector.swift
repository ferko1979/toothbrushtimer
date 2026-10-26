import Foundation

/// Sonic (electric) toothbrush detector: a new, stable, narrow tone with a 2x harmonic.
/// Port of analysis/brushdetect/sonic.py.
public struct SonicConfig: Equatable {
    public var bandLowHz: Double = 150
    public var bandHighHz: Double = 400
    public var neighbourhoodHz: Double = 30
    public var stabilityHz: Double = 3
    public var promRamp: (Double, Double) { (8, 16) }
    public var noveltyRamp: (Double, Double) { (3, 9) }
    public var floorRiseDbPerS: Double = 0.1
    public var harmonicMinDb: Double = 3
    public var hopS: Double = 0.5

    public init() {}

    /// Narrow band around a calibrated brush frequency.
    public init(calibratedF0 f0: Double, toleranceHz: Double = 10) {
        bandLowHz = f0 - toleranceHz
        bandHighHz = f0 + toleranceHz
    }
}

public struct SonicResult: Equatable {
    public let score: Double
    public let f0Hz: Double
    public let prominenceDb: Double
    public let noveltyDb: Double
}

public final class SonicDetector {
    public static let windowSamples = 3 * Audio.sampleRate
    public static let hopSamples = Audio.sampleRate / 2
    static let nperseg = 8192

    public let cfg: SonicConfig
    private let fft: FFT
    private let window: [Double]
    private let densityScale: Double
    private let wideLo: Int
    private let wideHi: Int  // inclusive
    private let inBand: [Bool]
    private let freqs: [Double]
    private let nb: Int
    private let tol: Int
    private var floor: [Double]?

    public init(cfg: SonicConfig = SonicConfig()) {
        self.cfg = cfg
        let df = Double(Audio.sampleRate) / Double(SonicDetector.nperseg)
        let all = (0...(SonicDetector.nperseg / 2)).map { Double($0) * df }
        var lo = -1, hi = -1
        for (k, f) in all.enumerated()
        where f >= cfg.bandLowHz - cfg.neighbourhoodHz && f <= 2 * cfg.bandHighHz + cfg.neighbourhoodHz {
            if lo < 0 { lo = k }
            hi = k
        }
        let wideFreqs = Array(all[lo...hi])
        let w = Windows.hannPeriodic(SonicDetector.nperseg)
        var w2 = 0.0
        for v in w { w2 += v * v }
        fft = FFT(n: SonicDetector.nperseg)
        window = w
        densityScale = 1.0 / (Double(Audio.sampleRate) * w2)
        wideLo = lo
        wideHi = hi
        freqs = wideFreqs
        inBand = wideFreqs.map { $0 >= cfg.bandLowHz && $0 <= cfg.bandHighHz }
        nb = 2 * Int(cfg.neighbourhoodHz / df) + 1
        tol = Int((cfg.stabilityHz / df).rounded(.up))
    }

    public func reset() { floor = nil }

    /// scipy.signal.welch(x, fs, nperseg=8192, noverlap=4096) restricted to the wide band, in dB.
    private func welchDb(_ x: ArraySlice<Double>) -> [Double] {
        let n = SonicDetector.nperseg
        let step = n / 2
        let segs = (x.count - n) / step + 1
        let base = x.startIndex
        var acc = [Double](repeating: 0, count: n / 2 + 1)
        for s in 0..<segs {
            let st = base + s * step
            var m = 0.0
            for i in 0..<n { m += x[st + i] }
            m /= Double(n)
            var seg = [Double](repeating: 0, count: n)
            for i in 0..<n { seg[i] = (x[st + i] - m) * window[i] }
            let p = fft.powerSpectrum(seg)
            for k in 0..<p.count {
                var v = p[k] * densityScale
                if k != 0 && k != n / 2 { v *= 2 }
                acc[k] += v
            }
        }
        var out = [Double](repeating: 0, count: wideHi - wideLo + 1)
        for k in wideLo...wideHi {
            out[k - wideLo] = 10 * log10(acc[k] / Double(segs) + 1e-16)
        }
        return out
    }

    /// One 3 s window (48000 samples). Windows must be fed in order (adaptive floor).
    public func process(_ x: ArraySlice<Double>) -> SonicResult {
        precondition(x.count == SonicDetector.windowSamples)
        let sub = Audio.sampleRate
        var subs: [[Double]] = []
        for k in 0..<(SonicDetector.windowSamples / sub) {
            let st = x.startIndex + k * sub
            subs.append(welchDb(x[st..<(st + sub)]))
        }
        let m = subs[0].count
        var spec = [Double](repeating: 0, count: m)
        for i in 0..<m {
            var s = 0.0
            for row in subs { s += pow(10.0, row[i] / 10.0) }
            spec[i] = 10 * log10(s / Double(subs.count))
        }
        let rise = cfg.floorRiseDbPerS * cfg.hopS
        if var fl = floor {
            for i in 0..<m { fl[i] = Swift.min(spec[i], fl[i] + rise) }
            floor = fl
        } else {
            floor = spec
        }

        let medSpec = Stats.medianFilterNearest(spec, size: nb)
        var prom = [Double](repeating: 0, count: m)
        for i in 0..<m { prom[i] = spec[i] - medSpec[i] }
        var k = -1
        for i in 0..<m where inBand[i] {
            if k < 0 || prom[i] > prom[k] { k = i }
        }
        if k < 0 { return SonicResult(score: 0, f0Hz: 0, prominenceDb: 0, noveltyDb: 0) }

        let lo = Swift.max(k - 3 * tol, 0)
        let hi = Swift.min(k + 3 * tol + 1, m)
        var stable = true
        for row in subs {
            let med = Stats.medianFilterNearest(row, size: nb)
            var sp = [Double](repeating: 0, count: m)
            for i in 0..<m { sp[i] = row[i] - med[i] }
            let j = Stats.argmax(sp, from: lo, to: hi)
            stable = stable && abs(j - k) <= tol && sp[j] >= 6.0
        }
        let target = 2 * freqs[k]
        var k2 = 0
        for i in 0..<m where abs(freqs[i] - target) < abs(freqs[k2] - target) { k2 = i }
        var hmax = -Double.infinity
        for i in Swift.max(k2 - tol, 0)..<Swift.min(k2 + tol + 1, m) { hmax = Swift.max(hmax, prom[i]) }
        let harmonic = hmax >= cfg.harmonicMinDb
        let novelty = spec[k] - (floor ?? spec)[k]
        let promScore = Stats.ramp(prom[k], cfg.promRamp.0, cfg.promRamp.1)
        let noveltyScore = Stats.ramp(novelty, cfg.noveltyRamp.0, cfg.noveltyRamp.1)
        let score = promScore * noveltyScore * ((stable && harmonic) ? 1.0 : 0.0)
        return SonicResult(score: score, f0Hz: freqs[k], prominenceDb: prom[k], noveltyDb: novelty)
    }

    /// Human-readable description of a detected brush tone.
    public static func describe(f0Hz: Double) -> String {
        let moves = Int((f0Hz * 120).rounded())
        let kind = (220...300).contains(f0Hz) ? "szónikus fogkefe (Sonicare-típusú)" : "elektromos fogkefe"
        return "\(kind): \(Int(f0Hz.rounded())) Hz-es zúgás, kb. \(Formatting.grouped(moves)) mozdulat/perc"
    }
}
