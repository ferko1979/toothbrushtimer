import Foundation

/// Water cue -> brushing -> rinse state machine with water-waste tracking.
/// 1:1 port of analysis/brushdetect/session.py.
public struct SessionConfig: Equatable {
    public var on = 0.6
    public var off = 0.4
    public var waterOn = 0.55
    public var waterOff = 0.3
    public var waterMinS = 1.0
    public var waterStopS = 1.0
    public var armS = 20.0
    public var brushConfirmS = 2.0
    public var fallbackS = 6.0
    public var endQuietS = 15.0
    public var rinseMinS = 2.0
    public var resumeS = 5.0
    public var rinseDoneS = 5.0
    public var minBrushingBeforeRinseS = 10.0
    public var wasteIconS = 5.0
    /// App: until the session is this long (the goal), stop only after a long silence or a clear rinse.
    public var holdUntilS: Double? = nil
    public var holdQuietS = 45.0
    public var rinseMinEarlyS = 4.0
    /// App, electric brush: while the sonic hum is heard, the session never ends and water is ignored.
    public var sonicSuppressesWater = false
    /// App: the brushing run only restarts when the signal drops below `off` (short dips keep it).
    public var runHysteresis = false

    public init() {}

    /// Opened from a reminder: start sooner, wait longer for the water cue.
    public static var armed: SessionConfig {
        var c = SessionConfig()
        c.fallbackS = 3.0
        c.armS = 40.0
        return c
    }
}

public enum SessionEvent: String, Codable {
    case waterStart = "water_start"
    case waterStop = "water_stop"
    case brushingDetected = "brushing_detected"
    case rinseStart = "rinse_start"
    case brushingResumed = "brushing_resumed"
    case wasteIconOn = "waste_icon_on"
    case wasteIconOff = "waste_icon_off"
    case sessionEnd = "session_end"
}

public struct BrushingSession: Equatable {
    public var start: Double
    public var end: Double = 0
    public var cue: String = "water"  // "water" or "no_water"
    public var waterRunningS: Double = 0
    public var events: [(Double, SessionEvent)] = []
    /// Why the session ended: "rinse", "quiet" or "finish" (listening stopped).
    public var endReason = "finish"

    public var durationS: Double { Swift.max(end - start, 0) }
    public var wastedWater: Bool { waterRunningS >= 5.0 }

    public static func == (a: BrushingSession, b: BrushingSession) -> Bool {
        a.start == b.start && a.end == b.end && a.cue == b.cue && a.waterRunningS == b.waterRunningS
    }
}

public final class SessionDetector {
    public enum State: String { case listening, water, armed, brushing, rinse }

    public let cfg: SessionConfig
    public private(set) var state: State = .listening
    public private(set) var sessions: [BrushingSession] = []
    public private(set) var events: [(Double, SessionEvent)] = []
    public private(set) var wasteIcon = false
    public var onEvent: ((Double, SessionEvent) -> Void)?

    private var waterOn = false
    private var waterRun = 0.0, dryRun = 0.0, brushRun = 0.0, quietRun = 0.0
    private var waterEnd = 0.0, rinseStart = 0.0, lastBrush = 0.0, rinseWater = 0.0
    private var dryBeforeWater = 0.0, sinceWater = 0.0
    private var t = 0.0

    public init(cfg: SessionConfig = SessionConfig()) {
        self.cfg = cfg
    }

    private func resetRuns() {
        waterRun = 0; dryRun = 0; brushRun = 0; quietRun = 0
        waterEnd = 0; rinseStart = 0; lastBrush = 0; rinseWater = 0
        dryBeforeWater = 0; sinceWater = 0
    }

    private var hasCurrent: Bool { state == .brushing || state == .rinse }

    /// The session in progress (brushing or rinsing), if any.
    public var current: BrushingSession? { hasCurrent ? sessions.last : nil }

    private func event(_ time: Double, _ e: SessionEvent) {
        events.append((time, e))
        if hasCurrent { sessions[sessions.count - 1].events.append((time, e)) }
        onEvent?(time, e)
    }

    private func startSession(_ time: Double, start: Double, cue: String) {
        sessions.append(BrushingSession(start: start, cue: cue))
        state = .brushing
        lastBrush = time
        quietRun = 0
        event(time, .brushingDetected)
    }

    private func endSession(_ time: Double, end: Double, reason: String = "finish") {
        sessions[sessions.count - 1].end = end
        sessions[sessions.count - 1].endReason = reason
        if wasteIcon {
            wasteIcon = false
            event(time, .wasteIconOff)
        }
        event(time, .sessionEnd)
        state = .listening
        resetRuns()
    }

    public func update(t time: Double, water: Double, brush: Double, sonic: Double, dt: Double) {
        let c = cfg
        t = time
        let brushing = Swift.max(brush, sonic)
        let humming = c.sonicSuppressesWater && sonic >= c.off && (state == .brushing || state == .rinse)
        if humming {
            waterOn = false
        } else if water >= c.waterOn {
            waterOn = true
        } else if water < c.waterOff {
            waterOn = false
        }
        let isWater = waterOn
        let noWater = !waterOn
        if isWater && waterRun == 0 { dryBeforeWater = sinceWater }
        sinceWater = isWater ? 0 : sinceWater + dt
        waterRun = isWater ? waterRun + dt : 0
        dryRun = noWater ? dryRun + dt : 0
        brushRun = brushing >= c.on ? brushRun + dt : ((c.runHysteresis && brushing >= c.off) ? brushRun : 0)

        switch state {
        case .listening:
            if waterRun >= c.waterMinS {
                state = .water
                event(time, .waterStart)
            } else if brushRun >= c.fallbackS {
                startSession(time, start: time - brushRun, cue: "no_water")
            }

        case .water:
            if dryRun >= c.waterStopS {
                waterEnd = time - dryRun
                state = .armed
                event(time, .waterStop)
            } else if brushRun >= c.brushConfirmS && waterRun >= c.brushConfirmS {
                startSession(time, start: time - brushRun, cue: "water")
            }

        case .armed:
            if waterRun >= c.waterMinS {
                state = .water
            } else if brushRun >= c.brushConfirmS {
                startSession(time, start: waterEnd, cue: "water")
            } else if time - waterEnd > c.armS {
                state = .listening
            }

        case .brushing:
            let idx = sessions.count - 1
            if brushing >= c.off {
                lastBrush = time
                quietRun = 0
            } else {
                quietRun += dt
            }
            if isWater { sessions[idx].waterRunningS += dt }
            let early = c.holdUntilS.map { time - sessions[idx].start < $0 } ?? false
            let rinseMin = early ? Swift.max(c.rinseMinS, c.rinseMinEarlyS) : c.rinseMinS
            if waterRun >= rinseMin && !wasteIcon && dryBeforeWater >= c.wasteIconS
                && time - sessions[idx].start >= c.minBrushingBeforeRinseS {
                rinseStart = time - waterRun
                rinseWater = waterRun
                state = .rinse
                event(time, .rinseStart)
            } else if waterRun >= c.wasteIconS && !wasteIcon {
                wasteIcon = true
                event(time, .wasteIconOn)
            } else if wasteIcon && dryRun >= c.waterStopS {
                wasteIcon = false
                event(time, .wasteIconOff)
            }
            if state == .brushing && quietRun >= (early ? Swift.max(c.endQuietS, c.holdQuietS) : c.endQuietS) {
                endSession(time, end: lastBrush, reason: "quiet")
            }

        case .rinse:
            let idx = sessions.count - 1
            if isWater {
                rinseWater += dt
                sessions[idx].waterRunningS += dt
            }
            if humming || (dryRun > 0 && brushRun >= c.resumeS && dryRun >= c.resumeS) {
                state = .brushing
                event(time, .brushingResumed)
            } else if dryRun >= c.rinseDoneS {
                sessions[idx].waterRunningS = Swift.max(sessions[idx].waterRunningS - rinseWater, 0)
                endSession(time, end: rinseStart, reason: "rinse")
            }
        }
    }

    /// Close an open session (end of listening).
    @discardableResult
    public func finish() -> [BrushingSession] {
        if state == .brushing {
            endSession(t, end: lastBrush)
        } else if state == .rinse {
            let idx = sessions.count - 1
            sessions[idx].waterRunningS = Swift.max(sessions[idx].waterRunningS - rinseWater, 0)
            endSession(t, end: rinseStart)
        }
        return sessions
    }
}
