import Foundation

/// When does the app listen? (listening.py)
/// Listen while the app is open; keep listening when the phone lies flat and still
/// (also if it already lay there when the app was opened); opened from a reminder
/// = armed; stop when picked up in the background, on timeout, or after a session.
public final class ListeningPolicy {
    public var flatMaxTiltDeg = 20.0
    public var stillMaxStdG = 0.03
    public var stillWindowS = 2.0
    public var idleTimeoutS = 300.0
    public var armedTimeoutS = 600.0
    public var afterSessionGraceS = 30.0

    public private(set) var listening = false
    public private(set) var foreground = false
    public private(set) var armed = false
    public private(set) var placed = false
    public private(set) var stopReason = ""

    private var motionSamples: [(Double, Double, Double, Double)] = []
    private var lastActivity = 0.0
    private var sessionEnd: Double?

    public init() {}

    public func appOpened(t: Double, fromNotification: Bool = false) {
        foreground = true
        listening = true
        armed = armed || fromNotification
        lastActivity = t
        sessionEnd = nil
        stopReason = ""
    }

    public func appBackgrounded(t: Double) {
        foreground = false
        if listening && !placed { stop("app háttérbe került, a telefon nincs letéve") }
    }

    public func appForegrounded(t: Double) {
        foreground = true
    }

    public func motion(t: Double, gx: Double, gy: Double, gz: Double) {
        motionSamples.append((t, gx, gy, gz))
        motionSamples.removeAll { $0.0 < t - stillWindowS }
        let span = (motionSamples.last?.0 ?? t) - (motionSamples.first?.0 ?? t)
        let wasPlaced = placed
        placed = span >= stillWindowS * 0.9 && flatAndStill()
        if wasPlaced && !flat(gx, gy, gz) && listening && !foreground { stop("felvették a telefont") }
    }

    public func activity(t: Double) { lastActivity = t }

    public func sessionFinished(t: Double) {
        sessionEnd = t
        armed = false
    }

    public func tick(t: Double) {
        guard listening else { return }
        if let end = sessionEnd, !foreground, t - end >= afterSessionGraceS {
            stop("a fogmosás véget ért")
            return
        }
        let timeout = armed ? armedTimeoutS : idleTimeoutS
        if t - lastActivity >= timeout { stop("hosszú ideig nem hallatszott víz vagy fogmosás") }
    }

    public func stopManually() { stop("leállítva") }

    public var sessionConfig: SessionConfig { armed ? .armed : SessionConfig() }

    private func stop(_ reason: String) {
        listening = false
        armed = false
        stopReason = reason
    }

    private func flat(_ gx: Double, _ gy: Double, _ gz: Double) -> Bool {
        let n = (gx * gx + gy * gy + gz * gz).squareRoot()
        return abs(gz) / (n > 0 ? n : 1) >= cos(flatMaxTiltDeg * Double.pi / 180)
    }

    private func flatAndStill() -> Bool {
        guard motionSamples.count >= 3 else { return false }
        guard motionSamples.allSatisfy({ flat($0.1, $0.2, $0.3) }) else { return false }
        let axes: [[Double]] = [motionSamples.map { $0.1 }, motionSamples.map { $0.2 }, motionSamples.map { $0.3 }]
        return axes.allSatisfy { Stats.std($0) <= stillMaxStdG }
    }
}
