import Foundation

public enum Audio {
    /// All detectors work on 16 kHz mono audio.
    public static let sampleRate = 16000
}

enum Windows {
    /// scipy `get_window('hann', n)`: periodic Hann.
    static func hannPeriodic(_ n: Int) -> [Double] {
        (0..<n).map { 0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / Double(n)) }
    }

    /// numpy `np.hanning(n)`: symmetric Hann.
    static func hannSymmetric(_ n: Int) -> [Double] {
        if n == 1 { return [1.0] }
        return (0..<n).map { 0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / Double(n - 1)) }
    }
}

enum Stats {
    static func mean(_ a: [Double]) -> Double {
        a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count)
    }

    /// Population standard deviation (numpy default, ddof = 0).
    static func std(_ a: [Double]) -> Double {
        let m = mean(a)
        var s = 0.0
        for v in a { s += (v - m) * (v - m) }
        return a.isEmpty ? 0 : (s / Double(a.count)).squareRoot()
    }

    /// numpy median: average of the two middle values for even counts.
    static func median(_ a: [Double]) -> Double {
        if a.isEmpty { return 0 }
        let s = a.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : 0.5 * (s[n / 2 - 1] + s[n / 2])
    }

    /// scipy.ndimage.median_filter(a, size, mode="nearest") for odd `size`.
    static func medianFilterNearest(_ a: [Double], size: Int) -> [Double] {
        let n = a.count
        let h = size / 2
        var out = [Double](repeating: 0, count: n)
        var buf = [Double](repeating: 0, count: size)
        for i in 0..<n {
            for o in 0..<size {
                let idx = Swift.min(Swift.max(i + o - h, 0), n - 1)
                buf[o] = a[idx]
            }
            buf.sort()
            out[i] = buf[h]
        }
        return out
    }

    /// Index of the first maximum (numpy argmax semantics).
    static func argmax(_ a: [Double], from lo: Int = 0, to hi: Int? = nil) -> Int {
        let end = Swift.min(hi ?? a.count, a.count)
        var best = lo
        var i = lo
        while i < end {
            if a[i] > a[best] { best = i }
            i += 1
        }
        return best
    }

    static func ramp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max((x - lo) / (hi - lo), 0), 1)
    }
}
