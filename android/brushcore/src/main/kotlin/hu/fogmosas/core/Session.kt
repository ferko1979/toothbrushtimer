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
}

class BrushingSession(var start: Double, var cue: String = "water") {
    var end = 0.0
    var waterRunningS = 0.0
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

    private fun resetRuns() {
        waterRun = 0.0; dryRun = 0.0; brushRun = 0.0; quietRun = 0.0
        waterEnd = 0.0; rinseStart = 0.0; lastBrush = 0.0; rinseWater = 0.0
        dryBeforeWater = 0.0; sinceWater = 0.0
    }

    private val hasCurrent get() = state == State.BRUSHING || state == State.RINSE
    val current: BrushingSession? get() = if (hasCurrent) sessions.lastOrNull() else null

    private fun event(time: Double, e: SessionEvent) {
        events.add(time to e)
        if (hasCurrent) sessions.last().events.add(time to e)
        onEvent?.invoke(time, e)
    }

    private fun startSession(time: Double, start: Double, cue: String) {
        sessions.add(BrushingSession(start, cue))
        state = State.BRUSHING
        lastBrush = time
        quietRun = 0.0
        event(time, SessionEvent.BRUSHING_DETECTED)
    }

    private fun endSession(time: Double, end: Double) {
        sessions.last().end = end
        if (wasteIcon) { wasteIcon = false; event(time, SessionEvent.WASTE_ICON_OFF) }
        event(time, SessionEvent.SESSION_END)
        state = State.LISTENING
        resetRuns()
    }

    fun update(time: Double, water: Double, brush: Double, sonic: Double, dt: Double) {
        val c = cfg
        t = time
        val brushing = max(brush, sonic)
        if (water >= c.waterOn) waterOn = true else if (water < c.waterOff) waterOn = false
        val isWater = waterOn
        val noWater = !waterOn
        if (isWater && waterRun == 0.0) dryBeforeWater = sinceWater
        sinceWater = if (isWater) 0.0 else sinceWater + dt
        waterRun = if (isWater) waterRun + dt else 0.0
        dryRun = if (noWater) dryRun + dt else 0.0
        brushRun = if (brushing >= c.on) brushRun + dt else 0.0

        when (state) {
            State.LISTENING -> {
                if (waterRun >= c.waterMinS) {
                    state = State.WATER
                    event(time, SessionEvent.WATER_START)
                } else if (brushRun >= c.fallbackS) {
                    startSession(time, time - brushRun, "no_water")
                }
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
                    startSession(time, waterEnd, "water")
                } else if (time - waterEnd > c.armS) {
                    state = State.LISTENING
                }
            }
            State.BRUSHING -> {
                val s = sessions.last()
                if (brushing >= c.off) { lastBrush = time; quietRun = 0.0 } else quietRun += dt
                if (isWater) s.waterRunningS += dt
                if (waterRun >= c.rinseMinS && !wasteIcon && dryBeforeWater >= c.wasteIconS &&
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
                if (state == State.BRUSHING && quietRun >= c.endQuietS) endSession(time, lastBrush)
            }
            State.RINSE -> {
                val s = sessions.last()
                if (isWater) { rinseWater += dt; s.waterRunningS += dt }
                if (dryRun > 0 && brushRun >= c.resumeS && dryRun >= c.resumeS) {
                    state = State.BRUSHING
                    event(time, SessionEvent.BRUSHING_RESUMED)
                } else if (dryRun >= c.rinseDoneS) {
                    s.waterRunningS = max(s.waterRunningS - rinseWater, 0.0)
                    endSession(time, rinseStart)
                }
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
) {
    companion object { const val HOP_S = 0.5 }

    val session = SessionDetector(sessionConfig)
    var onRow: ((ScoreRow) -> Unit)? = null

    private val mel = LogMelExtractor()
    private val brushEx = WindowFeatureExtractor(WindowFeatureExtractor.BRUSH_WINDOW)
    private val waterEx = WindowFeatureExtractor(WindowFeatureExtractor.WATER_WINDOW)
    private val sonic = SonicDetector(sonicConfig)
    private val gate = if (batterySaver) EnergyGate() else null

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
            val row = ScoreRow(0.5 * k + 0.5, brush, water, son, f0)
            emitted++
            session.update(row.t + HOP_S / 2, row.water, row.brush, row.sonic, HOP_S)
            onRow?.invoke(row)
        }
    }

    private fun updateGate(k: Int) {
        val g = gate ?: return
        val end = (k * WindowFeatureExtractor.HOP_FRAMES + WindowFeatureExtractor.WATER_WINDOW) * LogMelExtractor.HOP
        val n = SAMPLE_RATE / 2
        val st = maxOf(end - n, bufferStart)
        val len = minOf(n, totalSamples - st)
        if (len <= 0) return
        var e = 0.0
        for (i in rel(st) until rel(st) + len) e += samples[i] * samples[i]
        gateOpen = g.update(0.5 * k + 0.5, 10 * kotlin.math.log10(e / len + 1e-12))
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
        if (dropW > 50) pendingWater.subList(0, dropW).clear()
    }

    fun finish(): List<BrushingSession> {
        emitRows(true)
        return session.finish()
    }
}
