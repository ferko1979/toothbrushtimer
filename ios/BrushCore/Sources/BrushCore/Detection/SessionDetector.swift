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
    /// App: while brushing, "water" that is not clearly louder than the brushing itself (scrubbing
    /// without the motor can sound like water) must run this long before it counts as a rinse. nil = off.
    public var quietWaterRinseS: Double? = nil
    public var loudWaterDb = 3.0
    /// App: a short loud splash before brushing (wetting the brush head) arms the session like the water cue.
    public var wetCue = false
    /// App, electric brush: notice when the motor stops mid-session (flat battery) and the user goes on by hand.
    public var sonicStopWatch = false
    /// App: after the water cue the brushing starts when the brushing itself starts (toothpaste comes first).
    public var startAtBrushing = false
    /// App, oscillating brush (Oral-B): listen for the brush's own timer signal (motor stutter). Sonic brushes just stop.
    public var timerSignalWatch = false

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
    case brushWet = "brush_wet"
    case sonicStopped = "sonic_stopped"
    case sonicResumed = "sonic_resumed"
    case timerSignal = "timer_signal"
}

public struct BrushingSession: Equatable {
    public var start: Double
    public var end: Double = 0
    public var cue: String = "water"  // "water" or "no_water"
    public var waterRunningS: Double = 0
    public var events: [(Double, SessionEvent)] = []
    /// Why the session ended: "rinse", "quiet" or "finish" (listening stopped).
    public var endReason = "finish"
    /// The brush head was wetted just before (short splash cue).
    public var wetBefore = false
    /// Session time when the motor stopped mid-session (nil: it did not, or it came back).
    public var sonicStoppedAt: Double? = nil
    /// Brushing by hand after the motor stopped.
    public var manualAfterSonicS = 0.0
    /// Motor frequency while humming, one value per 0.5 s.
    public var sonicF0s: [Double] = []
    /// Session time when the motor hum was first heard.
    public var sonicStartAt: Double? = nil
    /// Session time of the brush's own timer signal (short stutter of the motor, e.g. Oral-B at 2 min).
    public var timerSignalAt: Double? = nil
    /// Typical loudness while brushing (dBFS), when the loudness was known.
    public var brushLevelDb: Double? = nil

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
    private var brushLevelDb: Double? = nil, waterLoud = false
    private var floorDb: Double? = nil, loudRun = 0.0, wetArmed = false, wetAt = -1e9
    private var sonicRun = 0.0, sonicGap = 0.0, sonicBack = 0.0, humRun = 0.0

    public init(cfg: SessionConfig = SessionConfig()) {
        self.cfg = cfg
    }

    private func resetRuns() {
        waterRun = 0; dryRun = 0; brushRun = 0; quietRun = 0
        waterEnd = 0; rinseStart = 0; lastBrush = 0; rinseWater = 0
        dryBeforeWater = 0; sinceWater = 0
        brushLevelDb = nil; waterLoud = false; loudRun = 0; wetArmed = false
        sonicRun = 0; sonicGap = 0; sonicBack = 0; humRun = 0
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
        var s = BrushingSession(start: start, cue: wetArmed && cue == "water" ? "wet" : cue)
        s.wetBefore = wetArmed
        sessions.append(s)
        wetArmed = false
        state = .brushing
        lastBrush = time
        quietRun = 0
        event(time, .brushingDetected)
    }

    private func endSession(_ time: Double, end: Double, reason: String = "finish") {
        sessions[sessions.count - 1].end = end
        sessions[sessions.count - 1].endReason = reason
        sessions[sessions.count - 1].brushLevelDb = brushLevelDb
        // A "signal" in the last seconds is the brush being switched off before rinsing.
        if let sig = sessions[sessions.count - 1].timerSignalAt, sessions[sessions.count - 1].durationS - sig < 5 {
            sessions[sessions.count - 1].timerSignalAt = nil
        }
        if wasteIcon {
            wasteIcon = false
            event(time, .wasteIconOff)
        }
        event(time, .sessionEnd)
        state = .listening
        resetRuns()
    }

    /// `rmsDb`: loudness of this step (dBFS), NaN if unknown; `sonicF0`: motor frequency, 0 if none.
    public func update(t time: Double, water: Double, brush: Double, sonic sonicIn: Double, dt: Double,
                       rmsDb: Double = .nan, sonicF0: Double = 0) {
        let c = cfg
        t = time
        let app = c.quietWaterRinseS != nil
        let level = !rmsDb.isNaN
        // A hum much quieter than the brushing is a background tone (fan), not the brush; water clearly
        // louder than the brushing is the tap even while something hums.
        let humAudible = !level || brushLevelDb == nil || rmsDb >= brushLevelDb! - 10
        let sonic = (app && !humAudible) ? 0 : sonicIn
        let brushing = Swift.max(brush, sonic)
        let loudWaterNow = level && brushLevelDb != nil && rmsDb >= brushLevelDb! + c.loudWaterDb && water >= c.waterOn
        let humming = c.sonicSuppressesWater && sonic >= c.off && (state == .brushing || state == .rinse) && (!app || !loudWaterNow)
        humRun = humming ? humRun + dt : 0
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
        if !isWater {
            waterLoud = false
        } else if level, let b = brushLevelDb, rmsDb >= b + c.loudWaterDb {
            waterLoud = true
        }
        if level && state == .brushing && brushing >= c.on && !isWater {
            brushLevelDb = brushLevelDb.map { $0 + 0.1 * (rmsDb - $0) } ?? rmsDb
        }
        if c.wetCue && level && (state == .listening || state == .armed) && !wetArmed {
            wetSplash(time, rmsDb: rmsDb, sonic: sonic, dt: dt)
        }
        // The splash itself sounds like scrubbing for a few seconds (smoothed scores): not brushing yet.
        if wetArmed && time - wetAt < 3 { brushRun = 0 }

        switch state {
        case .listening:
            if waterRun >= c.waterMinS {
                state = .water
                event(time, .waterStart)
            } else if brushRun >= c.fallbackS {
                startSession(time, start: time - brushRun, cue: "no_water")
            }
            if state == .listening && wetArmed {
                state = .armed
                waterEnd = time
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
                // After wetting, toothpaste comes first: brushing starts with the brushing itself.
                startSession(time, start: (wetArmed || c.startAtBrushing) ? Swift.max(waterEnd, time - brushRun) : waterEnd, cue: "water")
            } else if time - waterEnd > c.armS {
                state = .listening
                wetArmed = false
            }

        case .brushing:
            let idx = sessions.count - 1
            if brushing >= c.off {
                lastBrush = time
                quietRun = 0
            } else {
                quietRun += dt
            }
            // Quiet "water" while scrubbing is usually the scrubbing itself: not a running tap.
            if isWater && (c.quietWaterRinseS == nil || !level || brushLevelDb == nil || waterLoud) { sessions[idx].waterRunningS += dt }
            let early = c.holdUntilS.map { time - sessions[idx].start < $0 } ?? false
            var rinseMin = early ? Swift.max(c.rinseMinS, c.rinseMinEarlyS) : c.rinseMinS
            if let q = c.quietWaterRinseS, level, brushLevelDb != nil, !waterLoud { rinseMin = Swift.max(rinseMin, q) }
            if c.sonicStopWatch { watchSonic(time, idx: idx, brush: brush, sonic: sonic, f0: sonicF0, dt: dt) }
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
            // App: the hum must last 2 s to bring the rinse back to brushing (a tone in the rinse water is not enough).
            if (humming && (!app || humRun >= 2)) || (dryRun > 0 && brushRun >= c.resumeS && dryRun >= c.resumeS) {
                state = .brushing
                event(time, .brushingResumed)
            } else if dryRun >= c.rinseDoneS {
                sessions[idx].waterRunningS = Swift.max(sessions[idx].waterRunningS - rinseWater, 0)
                endSession(time, end: rinseStart, reason: "rinse")
            }
        }
    }

    /// Short loud burst (about 1–3 s, 10 dB over the quiet room) without the motor = wetting the brush.
    private func wetSplash(_ time: Double, rmsDb: Double, sonic: Double, dt: Double) {
        let floor: Double
        if let f = floorDb, rmsDb >= f { floor = f + 0.04 * dt } else { floor = rmsDb }
        floorDb = floor
        if rmsDb >= floor + 10 && sonic < cfg.off {
            loudRun += dt
            return
        }
        if loudRun >= 0.5 && loudRun <= 3 {
            wetArmed = true
            wetAt = time
            brushRun = 0
            event(time, .brushWet)
        }
        loudRun = 0
    }

    private func watchSonic(_ time: Double, idx: Int, brush: Double, sonic: Double, f0: Double, dt: Double) {
        let c = cfg
        if sonic >= c.on && f0 > 0 { sessions[idx].sonicF0s.append(f0) }
        // A hum heard in the first seconds was already there when the brushing was recognised.
        if sonic >= c.on && sessions[idx].sonicStartAt == nil {
            let at = time - sessions[idx].start
            sessions[idx].sonicStartAt = at < 10 ? 0 : at
        }
        if sonic >= c.off {
            sonicGap = 0
            if sonic >= c.on { sonicRun += dt }
        } else {
            sonicGap += dt
        }
        let stopped = sessions[idx].sonicStoppedAt != nil
        if !stopped && sonicGap >= 3 && sonicRun >= 30 {
            sessions[idx].sonicStoppedAt = time - sonicGap - sessions[idx].start
            sonicRun = 0
            event(time, .sonicStopped)
        } else if stopped {
            if sonic < c.off && brush >= c.off { sessions[idx].manualAfterSonicS += dt }
            sonicBack = sonic >= c.on ? sonicBack + dt : 0
            if sonicBack >= 2 {
                sessions[idx].sonicStoppedAt = nil
                sessions[idx].manualAfterSonicS = 0
                sonicBack = 0
                event(time, .sonicResumed)
            }
        }
    }

    /// The brush's own timer signal (motor stutter) heard at `time`; kept once per session while brushing.
    public func timerSignal(at time: Double) {
        guard state == .brushing, let idx = sessions.indices.last, sessions[idx].timerSignalAt == nil else { return }
        sessions[idx].timerSignalAt = time - sessions[idx].start
        event(time, .timerSignal)
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

/// The brush's own timer signal: the motor stutters (several 0.1 s drops of 8 dB or more within
/// 1.5 s) and then hums on at the same level, e.g. Oral-B at 2 minutes. A motor that stops does not
/// come back, so it is not a signal. Same as StutterDetector in Session.kt.
public final class StutterDetector {
    private var blocks: [Double] = []   // last 2 s of 0.1 s levels (dBFS), drops left out
    private var dips: [Double] = []     // times of recent drops
    private var lowRun = 0
    private var lastSignal = -1e9

    public init() {}

    /// Feed one stretch (normally 0.5 s) ending at `endTime` s; returns the signal time when one is complete.
    public func add(_ x: [Double], endTime: Double) -> Double? {
        let b = Audio.sampleRate / 10
        var found: Double?
        var i = 0
        while i + b <= x.count {
            var e = 0.0
            for j in i..<(i + b) { e += x[j] * x[j] }
            let db = 10 * log10(e / Double(b) + 1e-12)
            let t = endTime - Double(x.count - i - b) / Double(Audio.sampleRate)
            i += b
            if blocks.count < 10 { blocks.append(db); continue }
            let ref = Stats.median(blocks)
            while let f = dips.first, t - f > 1.5 { dips.removeFirst() }
            if ref > -60 && ref - db >= 8 {
                dips.append(t)
                // A level that stays down (motor off, silence) is the new normal, not a stutter.
                lowRun += 1
                if lowRun >= 15 { blocks.removeAll(); dips.removeAll(); lowRun = 0 }
                continue
            }
            lowRun = 0
            // Back at the same level after a few short drops (not a long gap, not louder water), from a
            // steady hum (an oscillating motor is steady within ~1 dB; scrubbing noise is not).
            let mean = blocks.reduce(0, +) / Double(blocks.count)
            let sd = (blocks.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(blocks.count)).squareRoot()
            if ref > -60 && abs(ref - db) < 3 && (3...8).contains(dips.count) && sd <= 2.5 && t - lastSignal > 10 {
                found = dips[0]
                lastSignal = t
                dips.removeAll()
            }
            blocks.append(db)
            if blocks.count > 20 { blocks.removeFirst(blocks.count - 20) }
        }
        return found
    }
}
