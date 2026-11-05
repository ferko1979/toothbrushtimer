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
    // A stop at a brush-timer mark (2:00, 2:30, 3:00 of humming) is the timer, not the battery.
    if (stop != null && s.manualAfterSonicS >= 2.0 && motorRunS(s)?.let(::timerMark) == null)
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

/** How long the motor hummed before it stopped (null: it did not stop, or no hum). */
fun motorRunS(s: BrushingSession): Double? {
    val a = s.sonicStartAt ?: return null
    val b = s.sonicStoppedAt ?: return null
    return (b - a).takeIf { it > 0 }
}

/** The usual brush-timer mark (120 / 150 / 180 s) this motor run matches, within 4 s; else null. */
fun timerMark(motorS: Double): Double? = listOf(120.0, 150.0, 180.0).firstOrNull { kotlin.math.abs(motorS - it) <= 4.0 }

/** An earlier brushing where the brush's timer stopped the motor and the user went on by hand. */
fun wasTimerStop(motorS: Double?, afterMotorS: Double?): Boolean =
    motorS != null && afterMotorS != null && afterMotorS >= 5.0 && timerMark(motorS) != null

/**
 * The brush's own timer: it stopped the motor at a timer mark and the user went on by hand (if this
 * keeps happening, set the brush's timer longer), or it signalled (stutter) during the brushing.
 */
fun brushTimerNote(s: BrushingSession, earlierTimerStops: Int): String? {
    val run = motorRunS(s)
    val mark = run?.let(::timerMark)
    if (mark != null && s.manualAfterSonicS >= 5.0) {
        return if (earlierTimerStops >= 2)
            tr("A fogkeféd időzítője {0} után leállítja a motort, de rendszeresen tovább mosol kézzel. Ha a fogkeféd engedi, állítsd hosszabbra az időzítőjét.", Formatting.clock(mark))
        else tr("A fogkeféd időzítője {0} után leállította a motort, utána kézzel folytattad. Ha gyakran így lesz, érdemes hosszabbra állítani az időzítőt.", Formatting.clock(mark))
    }
    val sig = s.timerSignalAt ?: return null
    val after = s.durationS - sig
    return if (after >= 10.0) tr("A fogkeféd {0}-nál jelzett (beépített időzítő), és utána még {1}-ig mostál.", Formatting.clock(sig), Formatting.clock(after))
    else tr("A fogkeféd {0}-nál jelzett (beépített időzítő).", Formatting.clock(sig))
}
