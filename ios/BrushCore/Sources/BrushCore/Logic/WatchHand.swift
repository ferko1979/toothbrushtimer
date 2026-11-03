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
