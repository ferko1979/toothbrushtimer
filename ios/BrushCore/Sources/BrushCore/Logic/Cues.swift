import Foundation

/// Haptic cues while brushing (cues.py): start, quadrant changes, goal reached.
public enum Quadrant {
    public static let names = ["jobb felső", "bal felső", "bal alsó", "jobb alsó"]
}

public struct Cue: Equatable {
    public enum Kind: String { case start, quadrant, done }
    public enum Haptic: String { case tap, success }
    public let atS: Double
    public let kind: Kind
    public let quadrant: Int
    public let haptic: Haptic
    public let text: String
}

public func cueSchedule(targetS: Double) -> [Cue] {
    let n = Quadrant.names.count
    let step = targetS / Double(n)
    var cues = [Cue(atS: 0, kind: .start, quadrant: 1, haptic: .tap, text: "Kezdd a \(Quadrant.names[0]) negyeddel")]
    for k in 1..<n {
        cues.append(Cue(atS: step * Double(k), kind: .quadrant, quadrant: k + 1, haptic: .tap,
                        text: "Jöhet a \(Quadrant.names[k]) negyed"))
    }
    cues.append(Cue(atS: targetS, kind: .done, quadrant: n, haptic: .success, text: "Kész, elérted a célidőt! 🎉"))
    return cues
}

public struct BrushProgress: Equatable {
    public let fraction: Double
    public let quadrant: Int
    public let quadrantName: String
    public let remainingS: Double
}

public func brushProgress(elapsedS: Double, targetS: Double) -> BrushProgress {
    let frac = Swift.min(Swift.max(elapsedS / targetS, 0), 1)
    let q = Swift.min(Int(frac * Double(Quadrant.names.count)), Quadrant.names.count - 1)
    return BrushProgress(fraction: frac, quadrant: q + 1, quadrantName: Quadrant.names[q],
                         remainingS: Swift.max(targetS - elapsedS, 0))
}

/// Returns each cue exactly once, as soon as its time has passed.
public final class CueTracker {
    private var pending: [Cue]
    public init(targetS: Double) { pending = cueSchedule(targetS: targetS) }
    public func update(elapsedS: Double) -> [Cue] {
        let fired = pending.filter { $0.atS <= elapsedS }
        pending.removeAll { $0.atS <= elapsedS }
        return fired
    }
}
