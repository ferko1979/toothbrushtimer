package hu.fogmosas.core

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// Watch placement: which hand brushes and which wrist wears the watch. Same as ios/BrushCore/.../WatchHand.swift.

/** How the watch should listen, from the brushing hand and the watch wrist ("left" / "right"). */
data class WatchListening(val sameHand: Boolean, val nearGateDb: Double, val useMotion: Boolean, val distanceText: String)

fun watchListening(brushHand: String, watchWrist: String): WatchListening =
    if (brushHand == watchWrist) WatchListening(true, 14.0, true, tr("Az óra a fogmosó kezeden van: kb. 10–20 cm-ről hallja a fogmosást, és a csuklód mozgását is figyeli."))
    else WatchListening(false, 8.0, false, tr("Az óra a másik kezeden van: kb. 30–50 cm-ről figyeli a hangot."))

/**
 * Wrist rhythm of brushing (watch on the brushing hand): share of the acceleration power in the
 * 2.5–7 Hz stroke band over the last 3 s, times a minimum movement. Feed user acceleration in g at
 * about [rateHz]; [score] is 0…1.
 */
class MotionRhythm(private val rateHz: Double = 50.0, windowS: Double = 3.0) {
    private val n = (rateHz * windowS).toInt()
    // Per-axis buffers: summing the axes' spectra is rotation-invariant and, unlike the magnitude,
    // does not fold a back-and-forth stroke onto twice its frequency.
    private val axes = List(3) { ArrayDeque<Double>() }

    fun add(ax: Double, ay: Double, az: Double) {
        doubleArrayOf(ax, ay, az).forEachIndexed { k, v ->
            axes[k].addLast(v)
            while (axes[k].size > n) axes[k].removeFirst()
        }
    }

    fun reset() = axes.forEach { it.clear() }

    fun score(): Double {
        if (axes[0].size < n / 2) return 0.0
        var band = 0.0
        var total = 0.0
        var variance = 0.0
        for (axis in axes) {
            val x = axis.toDoubleArray()
            val mean = x.average()
            for (i in x.indices) x[i] -= mean
            variance += x.sumOf { it * it } / x.size
            var f = 0.5
            while (f <= 15.0) {
                var re = 0.0; var im = 0.0
                for (i in x.indices) { val a = 2 * PI * f * i / rateHz; re += x[i] * cos(a); im -= x[i] * sin(a) }
                val p = re * re + im * im
                total += p
                if (f in 2.5..7.0) band += p
                f += 0.25
            }
        }
        if (total <= 0) return 0.0
        return Stats.ramp(band / total, 0.35, 0.6) * Stats.ramp(sqrt(variance), 0.03, 0.08)
    }
}
