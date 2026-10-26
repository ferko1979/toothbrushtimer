import Foundation

/// 66 level-independent features per window of log-mel frames.
/// Port of `window_features()` in analysis/brushdetect/learned.py.
/// Stateful: the adaptive floor carries over from window to window, so feed
/// windows in order (one extractor per window length).
public final class WindowFeatureExtractor {
    public static let brushWindow = 300  // frames = 3 s
    public static let waterWindow = 100  // frames = 1 s
    public static let hopFrames = 50     // 0.5 s
    public static let featureCount = 2 * LogMelExtractor.nMels + 2

    public let win: Int
    private var floor: [Double]?
    private let fft: FFT
    private let hann: [Double]
    private let bandIdx: [Int]
    private let refIdx: [Int]
    private let tol: Int

    public init(win: Int) {
        self.win = win
        fft = FFT(n: 1024)
        hann = Windows.hannSymmetric(win)
        let df = 100.0 / 1024.0  // rfftfreq(1024, 0.01)
        var band: [Int] = []
        var ref: [Int] = []
        for k in 0...512 {
            let f = Double(k) * df
            if f >= 3.0 && f <= 6.5 { band.append(k) }
            if f >= 1.5 && f <= 15.0 { ref.append(k) }
        }
        bandIdx = band
        refIdx = ref
        tol = Int((0.4 / df).rounded())
    }

    public func reset() { floor = nil }

    /// `frames` must contain exactly `win` log-mel frames.
    public func features(_ frames: ArraySlice<[Double]>) -> [Double] {
        precondition(frames.count == win)
        let nm = LogMelExtractor.nMels
        var mu = [Double](repeating: 0, count: nm)
        for fr in frames { for b in 0..<nm { mu[b] += fr[b] } }
        for b in 0..<nm { mu[b] /= Double(win) }

        if var fl = floor {
            for b in 0..<nm { fl[b] = Swift.min(fl[b] + 0.01, mu[b]) }
            floor = fl
        } else {
            floor = mu
        }

        var sd = [Double](repeating: 0, count: nm)
        for fr in frames { for b in 0..<nm { sd[b] += (fr[b] - mu[b]) * (fr[b] - mu[b]) } }
        for b in 0..<nm { sd[b] = (sd[b] / Double(win)).squareRoot() }

        // Stroke rhythm: modulation spectrum of the total-energy envelope.
        var e = [Double](repeating: 0, count: win)
        var i = 0
        for fr in frames {
            var s = 0.0
            for v in fr { s += exp(v) }
            e[i] = log(s)
            i += 1
        }
        let em = Stats.mean(e)
        for k in 0..<win { e[k] = (e[k] - em) * hann[k] }
        var p = fft.powerSpectrum(e)
        let med = Stats.median(refIdx.map { p[$0] }) + 1e-12
        for k in 0..<p.count { p[k] /= med }
        var c = bandIdx[0]
        for k in bandIdx where p[k] > p[c] { c = k }
        let c2 = 2 * c
        var hmax = -Double.infinity
        for k in Swift.max(c2 - tol, 0)..<Swift.min(c2 + tol + 1, p.count) { hmax = Swift.max(hmax, p[k]) }
        let comb = log10(p[c] + 1e-12) + log10(hmax + 1e-12)

        let muMean = Stats.mean(mu)
        var out: [Double] = []
        out.reserveCapacity(WindowFeatureExtractor.featureCount)
        for b in 0..<nm { out.append(mu[b] - muMean) }
        out.append(contentsOf: sd)
        var rel = 0.0
        let fl = floor ?? mu
        for b in 0..<nm { rel += mu[b] - fl[b] }
        out.append(rel / Double(nm))
        out.append(comb)
        return out
    }

    /// Window centre times and features for a whole recording (offline / tests).
    public static func allWindows(_ frames: [[Double]], win: Int) -> (times: [Double], features: [[Double]]) {
        let ex = WindowFeatureExtractor(win: win)
        var times: [Double] = []
        var feats: [[Double]] = []
        var s = 0
        while s + win <= frames.count {
            feats.append(ex.features(frames[s..<(s + win)]))
            times.append(Double(s + win / 2) * Double(LogMelExtractor.hop) / Double(Audio.sampleRate))
            s += hopFrames
        }
        return (times, feats)
    }
}
