import Foundation

/// 32-band log-mel energies, 64 ms frames (1024 samples), 10 ms hop (160 samples).
/// Matches `log_mel()` in analysis/brushdetect/learned.py (scipy.signal.stft
/// with a periodic Hann window, output scaled by 1/sum(window)).
public final class LogMelExtractor {
    public static let nMels = 32
    public static let nfft = 1024
    public static let hop = 160

    private let fft: FFT
    private let window: [Double]
    private let scale: Double
    private let filterbank: [[Double]]  // nMels x (nfft/2 + 1)

    public init() {
        let w = Windows.hannPeriodic(LogMelExtractor.nfft)
        let wsum = w.reduce(0, +)
        fft = FFT(n: LogMelExtractor.nfft)
        window = w
        scale = 1.0 / (wsum * wsum)
        filterbank = LogMelExtractor.makeFilterbank()
    }

    static func makeFilterbank(fmin: Double = 80, fmax: Double = 7900) -> [[Double]] {
        func mel(_ f: Double) -> Double { 2595.0 * log10(1.0 + f / 700.0) }
        func imel(_ m: Double) -> Double { 700.0 * (pow(10.0, m / 2595.0) - 1.0) }
        let n = nMels + 2
        let m0 = mel(fmin), m1 = mel(fmax)
        let pts = (0..<n).map { imel(m0 + (m1 - m0) * Double($0) / Double(n - 1)) }
        let bins = nfft / 2 + 1
        let freqs = (0..<bins).map { Double($0) * Double(Audio.sampleRate) / Double(nfft) }
        var fb = [[Double]](repeating: [Double](repeating: 0, count: bins), count: nMels)
        for i in 0..<nMels {
            let lo = pts[i], c = pts[i + 1], hi = pts[i + 2]
            for b in 0..<bins {
                let f = freqs[b]
                let v = Swift.min((f - lo) / (c - lo), (hi - f) / (hi - c))
                fb[i][b] = Swift.max(v, 0)
            }
        }
        return fb
    }

    /// One frame: `samples` must hold exactly `nfft` values.
    public func frame(_ samples: ArraySlice<Double>) -> [Double] {
        precondition(samples.count == LogMelExtractor.nfft)
        var x = [Double](repeating: 0, count: LogMelExtractor.nfft)
        var i = 0
        for v in samples {
            x[i] = v * window[i]
            i += 1
        }
        let p = fft.powerSpectrum(x)
        var out = [Double](repeating: 0, count: LogMelExtractor.nMels)
        for m in 0..<LogMelExtractor.nMels {
            let w = filterbank[m]
            var s = 0.0
            for b in 0..<p.count where w[b] != 0 {
                s += w[b] * p[b]
            }
            out[m] = log(s * scale + 1e-10)
        }
        return out
    }

    /// All frames of a recording (offline use and tests).
    public func frames(_ x: [Double]) -> [[Double]] {
        let n = LogMelExtractor.nfft
        if x.count < n { return [] }
        let count = (x.count - n) / LogMelExtractor.hop + 1
        var out: [[Double]] = []
        out.reserveCapacity(count)
        for f in 0..<count {
            let s = f * LogMelExtractor.hop
            out.append(frame(x[s..<(s + n)]))
        }
        return out
    }
}
