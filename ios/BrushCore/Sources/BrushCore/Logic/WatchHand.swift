import Foundation

// Watch placement: which hand brushes and which wrist wears the watch. Same as android/brushcore/.../WatchHand.kt.

/// How the watch should listen, from the brushing hand and the watch wrist ("left" / "right").
public struct WatchListening: Equatable {
    public let sameHand: Bool
    public let nearGateDb: Double
    public let useMotion: Bool
    public let distanceText: String
}

public func watchListening(brushHand: String, watchWrist: String) -> WatchListening {
    brushHand == watchWrist
        ? WatchListening(sameHand: true, nearGateDb: 14, useMotion: true,
                         distanceText: tr("Az óra a fogmosó kezeden van: kb. 10–20 cm-ről hallja a fogmosást, és a csuklód mozgását is figyeli."))
        : WatchListening(sameHand: false, nearGateDb: 8, useMotion: false,
                         distanceText: tr("Az óra a másik kezeden van: kb. 30–50 cm-ről figyeli a hangot."))
}

/// Wrist rhythm of brushing (watch on the brushing hand): share of the acceleration power in the
/// 2.5–7 Hz stroke band over the last 3 s, times a minimum movement. Feed user acceleration in g.
public final class MotionRhythm {
    private let rateHz: Double
    private let n: Int
    // Per-axis buffers: summing the axes' spectra is rotation-invariant and, unlike the magnitude,
    // does not fold a back-and-forth stroke onto twice its frequency.
    private var axes: [[Double]] = [[], [], []]

    public init(rateHz: Double = 50, windowS: Double = 3) {
        self.rateHz = rateHz
        self.n = Int(rateHz * windowS)
    }

    public func add(_ ax: Double, _ ay: Double, _ az: Double) {
        for (k, v) in [ax, ay, az].enumerated() {
            axes[k].append(v)
            if axes[k].count > n { axes[k].removeFirst(axes[k].count - n) }
        }
    }

    public func reset() { axes = [[], [], []] }

    public func score() -> Double {
        let count = axes[0].count
        guard count >= n / 2 else { return 0 }
        var band = 0.0, total = 0.0, variance = 0.0
        for buf in axes {
            let mean = buf.reduce(0, +) / Double(count)
            let x = buf.map { $0 - mean }
            variance += x.reduce(0) { $0 + $1 * $1 } / Double(count)
            var f = 0.5
            while f <= 15 {
                var re = 0.0, im = 0.0
                for (i, v) in x.enumerated() {
                    let a = 2 * Double.pi * f * Double(i) / rateHz
                    re += v * cos(a)
                    im -= v * sin(a)
                }
                let p = re * re + im * im
                total += p
                if f >= 2.5 && f <= 7 { band += p }
                f += 0.25
            }
        }
        guard total > 0 else { return 0 }
        return Stats.ramp(band / total, 0.35, 0.6) * Stats.ramp(variance.squareRoot(), 0.03, 0.08)
    }
}

/// Experimental: left/right balance from the wrist roll (gravity along the watch's x axis) while
/// brushing. The first quarter is the upper right (the cue order), so the roll seen in the first
/// `calibrationS` seconds of brushing is taken as "right".
public final class SideBalance {
    private let calibrationS: Double
    private let threshold: Double
    private var calib = 0.0, pos = 0.0, neg = 0.0

    public init(calibrationS: Double = 15, threshold: Double = 0.25) {
        self.calibrationS = calibrationS
        self.threshold = threshold
    }

    public func reset() { calib = 0; pos = 0; neg = 0 }

    /// `gx` gravity along x in g, `dt` seconds since the last sample, `elapsedS` brushing time so far.
    public func add(gx: Double, dt: Double, brushing: Bool, elapsedS: Double) {
        guard brushing else { return }
        let s = gx > threshold ? 1.0 : (gx < -threshold ? -1.0 : 0)
        guard s != 0 else { return }
        if elapsedS < calibrationS { calib += s * dt }
        if s > 0 { pos += dt } else { neg += dt }
    }

    /// (right %, left %), or nil when the start was unclear or too little was measured.
    public func result() -> (right: Int, left: Int)? {
        guard abs(calib) >= 4, pos + neg >= 30 else { return nil }
        let right = calib > 0 ? pos : neg
        let r = Int((100 * right / (pos + neg)).rounded())
        return (r, 100 - r)
    }

    public func note() -> String? {
        guard let (r, l) = result() else { return nil }
        if l < 30 { return tr("A bal oldalra kevesebb idő jutott (kb. {0}%). (kísérleti)", l) }
        if r < 30 { return tr("A jobb oldalra kevesebb idő jutott (kb. {0}%). (kísérleti)", r) }
        return tr("Jobb {0}% · bal {1}% – kiegyensúlyozott. (kísérleti)", r, l)
    }
}
