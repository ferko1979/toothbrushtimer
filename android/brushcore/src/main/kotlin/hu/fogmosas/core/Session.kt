package hu.fogmosas.core

import kotlin.math.max

/** Water cue -> brushing -> rinse state machine (1:1 port of session.py). */
data class SessionConfig(
    val on: Double = 0.6, val off: Double = 0.4,
    val waterOn: Double = 0.55, val waterOff: Double = 0.3,
    val waterMinS: Double = 1.0, val waterStopS: Double = 1.0,
    val armS: Double = 20.0, val brushConfirmS: Double = 2.0, val fallbackS: Double = 6.0,
    val endQuietS: Double = 15.0, val rinseMinS: Double = 2.0, val resumeS: Double = 5.0,
    val rinseDoneS: Double = 5.0, val minBrushingBeforeRinseS: Double = 10.0, val wasteIconS: Double = 5.0,
    /** App: until the session is this long (the goal), stop only after a long silence or a clear rinse. */
    val holdUntilS: Double? = null, val holdQuietS: Double = 45.0, val rinseMinEarlyS: Double = 4.0,
    /** App, electric brush: while the sonic hum is heard, the session never ends and water is ignored. */
    val sonicSuppressesWater: Boolean = false,
    /** App: the brushing run only restarts when the signal drops below `off` (short dips keep it). */
    val runHysteresis: Boolean = false,
    /**
     * App: while brushing, "water" that is not clearly louder than the brushing itself (scrubbing
     * without the motor can sound like water) must run this long before it counts as a rinse. null = off.
     */
    val quietWaterRinseS: Double? = null, val loudWaterDb: Double = 3.0,
    /** App: a short loud splash before brushing (wetting the brush head) arms the session like the water cue. */
    val wetCue: Boolean = false,
    /** App, electric brush: notice when the motor stops mid-session (flat battery) and the user goes on by hand. */
    val sonicStopWatch: Boolean = false,
    /** App: after the water cue the brushing starts when the brushing itself starts (toothpaste comes first). */
    val startAtBrushing: Boolean = false,
) {
    companion object {
        /** Opened from a reminder: start sooner, wait longer for the water cue. */
        val ARMED = SessionConfig(fallbackS = 3.0, armS = 40.0)
    }
}

enum class SessionEvent(val id: String) {
    WATER_START("water_start"), WATER_STOP("water_stop"), BRUSHING_DETECTED("brushing_detected"),
    RINSE_START("rinse_start"), BRUSHING_RESUMED("brushing_resumed"), WASTE_ICON_ON("waste_icon_on"),
    WASTE_ICON_OFF("waste_icon_off"), SESSION_END("session_end"),
    BRUSH_WET("brush_wet"), SONIC_STOPPED("sonic_stopped"), SONIC_RESUMED("sonic_resumed"),
}

class BrushingSession(var start: Double, var cue: String = "water") {
    var end = 0.0
    /** Why the session ended: "rinse", "quiet" or "finish" (listening stopped). */
    var endReason = "finish"
    var waterRunningS = 0.0
    /** The brush head was wetted just before (short splash cue). */
    var wetBefore = false
    /** Session time when the motor stopped mid-session (null: it did not, or it came back). */
    var sonicStoppedAt: Double? = null
    /** Brushing by hand after the motor stopped. */
    var manualAfterSonicS = 0.0
    /** Motor frequency while humming, one value per 0.5 s. */
    val sonicF0s = ArrayList<Double>()
    /** Typical loudness while brushing (dBFS), when the loudness was known. */
    var brushLevelDb: Double? = null
    val events = ArrayList<Pair<Double, SessionEvent>>()
    val durationS get() = max(end - start, 0.0)
    val wastedWater get() = waterRunningS >= 5.0
}

class SessionDetector(val cfg: SessionConfig = SessionConfig()) {
    enum class State { LISTENING, WATER, ARMED, BRUSHING, RINSE }

    var state = State.LISTENING; private set
    val sessions = ArrayList<BrushingSession>()
    val events = ArrayList<Pair<Double, SessionEvent>>()
    var wasteIcon = false; private set
    var onEvent: ((Double, SessionEvent) -> Unit)? = null

    private var waterOn = false
    private var waterRun = 0.0; private var dryRun = 0.0; private var brushRun = 0.0; private var quietRun = 0.0
    private var waterEnd = 0.0; private var rinseStart = 0.0; private var lastBrush = 0.0; private var rinseWater = 0.0
    private var dryBeforeWater = 0.0; private var sinceWater = 0.0
    private var t = 0.0
    private var brushLevelDb: Double? = null; private var waterLoud = false
    private var floorDb: Double? = null; private var loudRun = 0.0; private var wetArmed = false; private var wetAt = -1e9
    private var sonicRun = 0.0; private var sonicGap = 0.0; private var sonicBack = 0.0; private var humRun = 0.0

    private fun resetRuns() {
        waterRun = 0.0; dryRun = 0.0; brushRun = 0.0; quietRun = 0.0
        waterEnd = 0.0; rinseStart = 0.0; lastBrush = 0.0; rinseWater = 0.0
        dryBeforeWater = 0.0; sinceWater = 0.0
        brushLevelDb = null; waterLoud = false; loudRun = 0.0; wetArmed = false
        sonicRun = 0.0; sonicGap = 0.0; sonicBack = 0.0; humRun = 0.0
    }

    private val hasCurrent get() = state == State.BRUSHING || state == State.RINSE
    val current: BrushingSession? get() = if (hasCurrent) sessions.lastOrNull() else null

    private fun event(time: Double, e: SessionEvent) {
        events.add(time to e)
        if (hasCurrent) sessions.last().events.add(time to e)
        onEvent?.invoke(time, e)
    }

    private fun startSession(time: Double, start: Double, cue: String) {
        sessions.add(BrushingSession(start, if (wetArmed && cue == "water") "wet" else cue).also { it.wetBefore = wetArmed })
        wetArmed = false
        state = State.BRUSHING
        lastBrush = time
        quietRun = 0.0
        event(time, SessionEvent.BRUSHING_DETECTED)
    }

    private fun endSession(time: Double, end: Double, reason: String = "finish") {
        sessions.last().end = end
        sessions.last().brushLevelDb = brushLevelDb
        sessions.last().endReason = reason
        if (wasteIcon) { wasteIcon = false; event(time, SessionEvent.WASTE_ICON_OFF) }
        event(time, SessionEvent.SESSION_END)
        state = State.LISTENING
        resetRuns()
    }

    /** [rmsDb]: loudness of this step (dBFS), NaN if unknown; [sonicF0]: motor frequency, 0 if none. */
    fun update(time: Double, water: Double, brush: Double, sonicIn: Double, dt: Double,
               rmsDb: Double = Double.NaN, sonicF0: Double = 0.0) {
        val c = cfg
        t = time
        val app = c.quietWaterRinseS != null
        val level = !rmsDb.isNaN()
        val ref = brushLevelDb
        // A hum much quieter than the brushing is a background tone (fan), not the brush; water clearly
        // louder than the brushing is the tap even while something hums.
        val humAudible = !level || ref == null || rmsDb >= ref - 10.0
        val sonic = if (app && !humAudible) 0.0 else sonicIn
        val brushing = max(brush, sonic)
        val loudWaterNow = level && ref != null && rmsDb >= ref + c.loudWaterDb && water >= c.waterOn
        val humming = c.sonicSuppressesWater && sonic >= c.off && (state == State.BRUSHING || state == State.RINSE) &&
            (!app || !loudWaterNow)
        humRun = if (humming) humRun + dt else 0.0
        if (humming) waterOn = false
        else if (water >= c.waterOn) waterOn = true else if (water < c.waterOff) waterOn = false
        val isWater = waterOn
        val noWater = !waterOn
        if (isWater && waterRun == 0.0) dryBeforeWater = sinceWater
        sinceWater = if (isWater) 0.0 else sinceWater + dt
        waterRun = if (isWater) waterRun + dt else 0.0
        dryRun = if (noWater) dryRun + dt else 0.0
        brushRun = if (brushing >= c.on) brushRun + dt else if (c.runHysteresis && brushing >= c.off) brushRun else 0.0
        if (!isWater) waterLoud = false
        else if (level && brushLevelDb != null && rmsDb >= brushLevelDb!! + c.loudWaterDb) waterLoud = true
        if (level && state == State.BRUSHING && brushing >= c.on && !isWater)
            brushLevelDb = brushLevelDb?.let { it + 0.1 * (rmsDb - it) } ?: rmsDb
        if (c.wetCue && level && (state == State.LISTENING || state == State.ARMED) && !wetArmed) wetSplash(time, rmsDb, sonic, dt)
        // The splash itself sounds like scrubbing for a few seconds (smoothed scores): not brushing yet.
        if (wetArmed && time - wetAt < 3.0) brushRun = 0.0

        when (state) {
            State.LISTENING -> {
                if (waterRun >= c.waterMinS) {
                    state = State.WATER
                    event(time, SessionEvent.WATER_START)
                } else if (brushRun >= c.fallbackS) {
                    startSession(time, time - brushRun, "no_water")
                }
                if (state == State.LISTENING && wetArmed) { state = State.ARMED; waterEnd = time }
            }
            State.WATER -> {
                if (dryRun >= c.waterStopS) {
                    waterEnd = time - dryRun
                    state = State.ARMED
                    event(time, SessionEvent.WATER_STOP)
                } else if (brushRun >= c.brushConfirmS && waterRun >= c.brushConfirmS) {
                    startSession(time, time - brushRun, "water")
                }
            }
            State.ARMED -> {
                if (waterRun >= c.waterMinS) {
                    state = State.WATER
                } else if (brushRun >= c.brushConfirmS) {
                    // After wetting, toothpaste comes first: brushing starts with the brushing itself.
                    startSession(time, if (wetArmed || c.startAtBrushing) maxOf(waterEnd, time - brushRun) else waterEnd, "water")
                } else if (time - waterEnd > c.armS) {
                    state = State.LISTENING
                    wetArmed = false
                }
            }
            State.BRUSHING -> {
                val s = sessions.last()
                if (brushing >= c.off) { lastBrush = time; quietRun = 0.0 } else quietRun += dt
                // Quiet "water" while scrubbing is usually the scrubbing itself: not a running tap.
                if (isWater && (c.quietWaterRinseS == null || !level || brushLevelDb == null || waterLoud)) s.waterRunningS += dt
                val early = c.holdUntilS != null && time - s.start < c.holdUntilS
                var rinseMin = if (early) maxOf(c.rinseMinS, c.rinseMinEarlyS) else c.rinseMinS
                if (c.quietWaterRinseS != null && level && brushLevelDb != null && !waterLoud) rinseMin = maxOf(rinseMin, c.quietWaterRinseS)
                if (c.sonicStopWatch) watchSonic(time, s, brush, sonic, sonicF0, dt)
                if (waterRun >= rinseMin && !wasteIcon && dryBeforeWater >= c.wasteIconS &&
                    time - s.start >= c.minBrushingBeforeRinseS
                ) {
                    rinseStart = time - waterRun
                    rinseWater = waterRun
                    state = State.RINSE
                    event(time, SessionEvent.RINSE_START)
                } else if (waterRun >= c.wasteIconS && !wasteIcon) {
                    wasteIcon = true
                    event(time, SessionEvent.WASTE_ICON_ON)
                } else if (wasteIcon && dryRun >= c.waterStopS) {
                    wasteIcon = false
                    event(time, SessionEvent.WASTE_ICON_OFF)
                }
                if (state == State.BRUSHING && quietRun >= (if (early) maxOf(c.endQuietS, c.holdQuietS) else c.endQuietS)) endSession(time, lastBrush, "quiet")
            }
            State.RINSE -> {
                val s = sessions.last()
                if (isWater) { rinseWater += dt; s.waterRunningS += dt }
                // App: the hum must last 2 s to bring the rinse back to brushing (a tone in the rinse water is not enough).
                if ((humming && (!app || humRun >= 2.0)) || (dryRun > 0 && brushRun >= c.resumeS && dryRun >= c.resumeS)) {
                    state = State.BRUSHING
                    event(time, SessionEvent.BRUSHING_RESUMED)
                } else if (dryRun >= c.rinseDoneS) {
                    s.waterRunningS = max(s.waterRunningS - rinseWater, 0.0)
                    endSession(time, rinseStart, "rinse")
                }
            }
        }
    }

    /** Short loud burst (about 1–3 s, 10 dB over the quiet room) without the motor = wetting the brush. */
    private fun wetSplash(time: Double, rmsDb: Double, sonic: Double, dt: Double) {
        val f = floorDb
        floorDb = if (f == null || rmsDb < f) rmsDb else f + 0.04 * dt
        if (rmsDb >= floorDb!! + 10 && sonic < cfg.off) { loudRun += dt; return }
        if (loudRun in 1.0..3.0) {
            wetArmed = true
            wetAt = time
            brushRun = 0.0
            event(time, SessionEvent.BRUSH_WET)
        }
        loudRun = 0.0
    }

    private fun watchSonic(time: Double, s: BrushingSession, brush: Double, sonic: Double, f0: Double, dt: Double) {
        val c = cfg
        if (sonic >= c.on && f0 > 0) s.sonicF0s.add(f0)
        if (sonic >= c.off) { sonicGap = 0.0; if (sonic >= c.on) sonicRun += dt } else sonicGap += dt
        val stopped = s.sonicStoppedAt != null
        if (!stopped && sonicGap >= 3.0 && sonicRun >= 30.0) {
            s.sonicStoppedAt = time - sonicGap - s.start
            sonicRun = 0.0
            event(time, SessionEvent.SONIC_STOPPED)
        } else if (stopped) {
            if (sonic < c.off && brush >= c.off) s.manualAfterSonicS += dt
            sonicBack = if (sonic >= c.on) sonicBack + dt else 0.0
            if (sonicBack >= 2.0) {
                s.sonicStoppedAt = null
                s.manualAfterSonicS = 0.0
                sonicBack = 0.0
                event(time, SessionEvent.SONIC_RESUMED)
            }
        }
    }

    fun finish(): List<BrushingSession> {
        if (state == State.BRUSHING) endSession(t, lastBrush)
        else if (state == State.RINSE) {
            val s = sessions.last()
            s.waterRunningS = max(s.waterRunningS - rinseWater, 0.0)
            endSession(t, rinseStart)
        }
        return sessions
    }
}

data class ScoreRow(val t: Double, val brush: Double, val water: Double, val sonic: Double, val sonicF0: Double)

/** Battery saver: cheap loudness gate (power_gate.py). */
class EnergyGate(val openDb: Double = 6.0, val holdS: Double = 15.0, val floorRiseDbPerS: Double = 0.05, val hopS: Double = 0.5) {
    private var floor: Double? = null
    private var lastLoud = -1e9

    fun update(t: Double, rmsDb: Double): Boolean {
        val f = floor
        floor = if (f != null && rmsDb >= f) f + floorRiseDbPerS * hopS else rmsDb
        if (rmsDb >= floor!! + openDb) lastLoud = t
        return t - lastLoud <= holdS
    }
}

/**
 * Real-time pipeline (pipeline.py + session.py). Feed 16 kHz samples; every 0.5 s of
 * audio yields one ScoreRow with ~1 s latency. Not thread-safe: use one thread.
 */
class StreamingDetector(
    val heads: ModelHeads,
    sessionConfig: SessionConfig = SessionConfig(),
    sonicConfig: SonicConfig = SonicConfig(),
    var useSonic: Boolean = true,
    batterySaver: Boolean = false,
    /**
     * Near-sound filter: a new brushing/water cue is only considered when the sound is at least this
     * many dB above the room's background level (far, quiet sources are ignored). A running session is
     * never gated. null = off.
     */
    nearGateDb: Double? = null,
) {
    companion object { const val HOP_S = 0.5 }

    /** Watch on the brushing hand: wrist-rhythm score (MotionRhythm), counted as brushing evidence. */
    @Volatile var motionBrush = 0.0

    /** Loudness of the newest 0.5 s (dBFS), for test recordings. */
    var lastRmsDb = -120.0; private set
    private val nearGate = nearGateDb != null

    val session = SessionDetector(sessionConfig)
    var onRow: ((ScoreRow) -> Unit)? = null

    private val mel = LogMelExtractor()
    private val brushEx = WindowFeatureExtractor(WindowFeatureExtractor.BRUSH_WINDOW)
    private val waterEx = WindowFeatureExtractor(WindowFeatureExtractor.WATER_WINDOW)
    private val sonic = SonicDetector(sonicConfig)
    private val gate = when {
        nearGateDb != null -> EnergyGate(openDb = nearGateDb, holdS = 2.0)
        batterySaver -> EnergyGate()
        else -> null
    }

    private var samples = DoubleArray(1 shl 16)
    private var sampleCount = 0      // valid samples in `samples`
    private var bufferStart = 0      // absolute index of samples[0]
    private var totalSamples = 0

    private val frames = ArrayList<DoubleArray>()
    private var framesStart = 0
    private var frameCount = 0

    private var waterCount = 0
    private val brushRaw = ArrayList<Double>()
    private val brushSmoothed = ArrayList<Double>()
    private val sonicScores = ArrayList<SonicResult>()
    private val pendingWater = ArrayList<Double>()
    private val pendingRms = ArrayList<Double>()
    private var emitted = 0
    private var gateOpen = true

    val audioTime get() = totalSamples.toDouble() / SAMPLE_RATE

    fun append(newSamples: FloatArray, count: Int = newSamples.size) {
        if (sampleCount + count > samples.size) samples = samples.copyOf(maxOf(samples.size * 2, sampleCount + count))
        for (i in 0 until count) samples[sampleCount + i] = newSamples[i].toDouble()
        sampleCount += count
        totalSamples += count
        process()
    }

    private fun rel(abs: Int) = abs - bufferStart

    private fun process() {
        val nfft = LogMelExtractor.NFFT
        val hop = LogMelExtractor.HOP
        while (frameCount * hop + nfft <= totalSamples) {
            frames.add(mel.frame(samples, rel(frameCount * hop)))
            frameCount++
        }
        val hf = WindowFeatureExtractor.HOP_FRAMES
        while (waterCount * hf + WindowFeatureExtractor.WATER_WINDOW <= frameCount) {
            updateGate(waterCount)
            val p = if (gateOpen) heads.water.predict(waterEx.features(frames, waterCount * hf - framesStart)) else 0.0
            pendingWater.add(p)
            pendingRms.add(lastRmsDb)
            waterCount++
        }
        while (brushRaw.size * hf + WindowFeatureExtractor.BRUSH_WINDOW <= frameCount) {
            val p = if (gateOpen) heads.brush.predict(brushEx.features(frames, brushRaw.size * hf - framesStart)) else 0.0
            brushRaw.add(p)
            val n = minOf(5, brushRaw.size)
            brushSmoothed.add(brushRaw.subList(brushRaw.size - n, brushRaw.size).sum() / n)
        }
        while (sonicScores.size * SonicDetector.HOP_SAMPLES + SonicDetector.WINDOW_SAMPLES <= totalSamples) {
            val st = sonicScores.size * SonicDetector.HOP_SAMPLES
            sonicScores.add(if (useSonic && gateOpen) sonic.process(samples, rel(st)) else SonicResult(0.0, 0.0, 0.0, 0.0))
        }
        emitRows(false)
        trim()
    }

    /** Row k (centre 0.5k + 0.5 s) uses brushing/sonic window k - 2 (same centre). */
    private fun emitRows(final: Boolean) {
        while (emitted < waterCount) {
            val k = emitted
            val j = k - 2
            var brush = 0.0
            var son = 0.0
            var f0 = 0.0
            if (j >= 0) {
                if (j < brushSmoothed.size) brush = brushSmoothed[j]
                else if (final && brushSmoothed.isNotEmpty()) brush = brushSmoothed.last()
                else if (!final) return
                val sr = if (j < sonicScores.size) sonicScores[j] else sonicScores.lastOrNull()
                if (sr != null) { son = sr.score; f0 = sr.f0Hz }
            }
            val water = pendingWater[k - (waterCount - pendingWater.size)]
            val rms = pendingRms[k - (waterCount - pendingRms.size)]
            if (!final) brush = maxOf(brush, motionBrush)
            val row = ScoreRow(0.5 * k + 0.5, brush, water, son, f0)
            emitted++
            session.update(row.t + HOP_S / 2, row.water, row.brush, row.sonic, HOP_S, rms, row.sonicF0)
            onRow?.invoke(row)
        }
    }

    private fun updateGate(k: Int) {
        val end = (k * WindowFeatureExtractor.HOP_FRAMES + WindowFeatureExtractor.WATER_WINDOW) * LogMelExtractor.HOP
        val n = SAMPLE_RATE / 2
        val st = maxOf(end - n, bufferStart)
        val len = minOf(n, totalSamples - st)
        if (len <= 0) return
        var e = 0.0
        for (i in rel(st) until rel(st) + len) e += samples[i] * samples[i]
        lastRmsDb = 10 * kotlin.math.log10(e / len + 1e-12)
        val g = gate ?: return
        val open = g.update(0.5 * k + 0.5, lastRmsDb)
        val inSession = session.state == SessionDetector.State.BRUSHING || session.state == SessionDetector.State.RINSE
        gateOpen = open || (nearGate && inSession)
    }

    private fun trim() {
        val need = minOf(frameCount * LogMelExtractor.HOP, sonicScores.size * SonicDetector.HOP_SAMPLES)
        val drop = need - bufferStart
        if (drop > 32000) {
            System.arraycopy(samples, drop, samples, 0, sampleCount - drop)
            sampleCount -= drop
            bufferStart += drop
        }
        val needF = minOf(brushRaw.size, waterCount) * WindowFeatureExtractor.HOP_FRAMES
        val dropF = needF - framesStart
        if (dropF > 200) {
            frames.subList(0, dropF).clear()
            framesStart += dropF
        }
        val dropW = pendingWater.size - (waterCount - emitted)
        if (dropW > 50) { pendingWater.subList(0, dropW).clear(); pendingRms.subList(0, dropW).clear() }
    }

    fun finish(): List<BrushingSession> {
        emitRows(true)
        return session.finish()
    }
}
