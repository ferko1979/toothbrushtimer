import Foundation

// Electric brush health from the motor hum. Same as android/brushcore/.../BrushPower.kt.

/// Notes about the brush's battery after a session: the motor stopped mid-session and the user went
/// on by hand, the motor slowed down during the session, or it hums slower than in earlier sessions
/// (`history`: earlier session frequencies, e.g. the calibration list).
public func brushPowerNotes(_ s: BrushingSession, history: [Double]) -> [String] {
    var out: [String] = []
    if let stop = s.sonicStoppedAt, s.manualAfterSonicS >= 2 {
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
