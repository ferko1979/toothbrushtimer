import Foundation

// Electric brush health from the motor hum. Same as android/brushcore/.../BrushPower.kt.

/// Notes about the brush's battery after a session: the motor stopped mid-session and the user went
/// on by hand, the motor slowed down during the session, or it hums slower than in earlier sessions
/// (`history`: earlier session frequencies, e.g. the calibration list).
public func brushPowerNotes(_ s: BrushingSession, history: [Double]) -> [String] {
    var out: [String] = []
    // A stop at a brush-timer mark (2:00, 2:30, 3:00 of humming) is the timer, not the battery.
    if let stop = s.sonicStoppedAt, s.manualAfterSonicS >= 2, motorRunS(s).flatMap(timerMark) == nil {
        out.append(tr("A fogkefe motorja {0}-nál leállt, utána kézzel sikáltál tovább. Valószínűleg lemerült – tedd töltőre!", formatClock(stop)))
    }
    let f = s.sonicF0s
    if f.count >= 40 {
        let first = Stats.median(Array(f.prefix(20)))
        let last = Stats.median(Array(f.suffix(20)))
        let drop = (first - last) / first * 100
        if drop >= 1.5 { out.append(tr("A motor a mosás végére {0}%-kal lassult – merül az akkumulátor.", Int(drop.rounded()))) }
    }
    if f.count >= 20 && history.count >= 3 {
        let base = Stats.median(Array(history.suffix(10)))
        let now = Stats.median(f)
        let drop = (base - now) / base * 100
        if drop >= 2 {
            out.append(tr("A fogkeféd most {0}%-kal lassabban zúg, mint általában. Töltsd fel; ha feltöltve is így marad, gyengül az akkumulátora.", Int(drop.rounded())))
        }
    }
    return out
}

/// How long the motor hummed before it stopped (nil: it did not stop, or no hum).
public func motorRunS(_ s: BrushingSession) -> Double? {
    guard let a = s.sonicStartAt, let b = s.sonicStoppedAt, b > a else { return nil }
    return b - a
}

/// The usual brush-timer mark (120 / 150 / 180 s) this motor run matches, within 4 s; else nil.
public func timerMark(_ motorS: Double) -> Double? { [120.0, 150, 180].first { abs(motorS - $0) <= 4 } }

/// An earlier brushing where the brush's timer stopped the motor and the user went on by hand.
public func wasTimerStop(motorS: Double?, afterMotorS: Double?) -> Bool {
    guard let m = motorS, let a = afterMotorS else { return false }
    return a >= 5 && timerMark(m) != nil
}

/// The brush's own timer: it stopped the motor at a timer mark and the user went on by hand (if this
/// keeps happening, set the brush's timer longer), or it signalled (stutter) during the brushing.
public func brushTimerNote(_ s: BrushingSession, earlierTimerStops: Int) -> String? {
    if let mark = motorRunS(s).flatMap(timerMark), s.manualAfterSonicS >= 5 {
        return earlierTimerStops >= 2
            ? tr("A fogkeféd időzítője {0} után leállítja a motort, de rendszeresen tovább mosol kézzel. Ha a fogkeféd engedi, állítsd hosszabbra az időzítőjét.", formatClock(mark))
            : tr("A fogkeféd időzítője {0} után leállította a motort, utána kézzel folytattad. Ha gyakran így lesz, érdemes hosszabbra állítani az időzítőt.", formatClock(mark))
    }
    guard let sig = s.timerSignalAt else { return nil }
    let after = s.durationS - sig
    return after >= 10
        ? tr("A fogkeféd {0}-nál jelzett (beépített időzítő), és utána még {1}-ig mostál.", formatClock(sig), formatClock(after))
        : tr("A fogkeféd {0}-nál jelzett (beépített időzítő).", formatClock(sig))
}
