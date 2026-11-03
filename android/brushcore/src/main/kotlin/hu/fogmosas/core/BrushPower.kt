package hu.fogmosas.core

import kotlin.math.roundToInt

// Electric brush health from the motor hum. Same as ios/BrushCore/.../BrushPower.swift.

/**
 * Notes about the brush's battery after a session: the motor stopped mid-session and the user went
 * on by hand, the motor slowed down during the session, or it hums slower than in earlier sessions
 * ([history]: earlier session frequencies, e.g. the calibration list).
 */
fun brushPowerNotes(s: BrushingSession, history: List<Double>): List<String> {
    val out = ArrayList<String>()
    val stop = s.sonicStoppedAt
    if (stop != null && s.manualAfterSonicS >= 2.0)
        out += tr("A fogkefe motorja {0}-nál leállt, utána kézzel sikáltál tovább. Valószínűleg lemerült – tedd töltőre!", Formatting.clock(stop))
    val f = s.sonicF0s
    if (f.size >= 40) {
        val first = Stats.median(f.take(20))
        val last = Stats.median(f.takeLast(20))
        val drop = (first - last) / first * 100
        if (drop >= 1.5) out += tr("A motor a mosás végére {0}%-kal lassult – merül az akkumulátor.", drop.roundToInt())
    }
    if (f.size >= 20 && history.size >= 3) {
        val base = Stats.median(history.takeLast(10))
        val now = Stats.median(f)
        val drop = (base - now) / base * 100
        if (drop >= 2.0) out += tr("A fogkeféd most {0}%-kal lassabban zúg, mint általában. Töltsd fel; ha feltöltve is így marad, gyengül az akkumulátora.", drop.roundToInt())
    }
    return out
}
