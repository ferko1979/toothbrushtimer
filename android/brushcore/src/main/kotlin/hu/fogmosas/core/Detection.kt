package hu.fogmosas.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** 66 level-independent features per window of log-mel frames (window_features in learned.py). */
class WindowFeatureExtractor(val win: Int) {
    companion object {
        const val BRUSH_WINDOW = 300
        const val WATER_WINDOW = 100
        const val HOP_FRAMES = 50
        const val FEATURE_COUNT = 2 * LogMelExtractor.N_MELS + 2

        fun allWindows(frames: List<DoubleArray>, win: Int): Pair<List<Double>, List<DoubleArray>> {
            val ex = WindowFeatureExtractor(win)
            val times = ArrayList<Double>()
            val feats = ArrayList<DoubleArray>()
            var s = 0
            while (s + win <= frames.size) {
                feats.add(ex.features(frames, s))
                times.add((s + win / 2).toDouble() * LogMelExtractor.HOP / SAMPLE_RATE)
                s += HOP_FRAMES
            }
            return times to feats
        }
    }

    private var floor: DoubleArray? = null
    private val fft = FFT(1024)
    private val hann = Windows.hannSymmetric(win)
    private val bandIdx: IntArray
    private val refIdx: IntArray
    private val tol: Int

    init {
        val df = 100.0 / 1024.0
        bandIdx = (0..512).filter { val f = it * df; f >= 3.0 && f <= 6.5 }.toIntArray()
        refIdx = (0..512).filter { val f = it * df; f >= 1.5 && f <= 15.0 }.toIntArray()
        tol = (0.4 / df).roundToInt()
    }

    fun reset() { floor = null }

    /** Features of frames[start until start + win]. Windows must be fed in order. */
    fun features(frames: List<DoubleArray>, start: Int): DoubleArray {
        val nm = LogMelExtractor.N_MELS
        val mu = DoubleArray(nm)
        for (t in start until start + win) { val fr = frames[t]; for (b in 0 until nm) mu[b] += fr[b] }
        for (b in 0 until nm) mu[b] /= win.toDouble()
        val fl = floor?.let { old -> DoubleArray(nm) { min(old[it] + 0.01, mu[it]) } } ?: mu.copyOf()
        floor = fl

        val sd = DoubleArray(nm)
        for (t in start until start + win) { val fr = frames[t]; for (b in 0 until nm) sd[b] += (fr[b] - mu[b]) * (fr[b] - mu[b]) }
        for (b in 0 until nm) sd[b] = sqrt(sd[b] / win)

        val e = DoubleArray(win) { i ->
            var s = 0.0
            for (v in frames[start + i]) s += exp(v)
            ln(s)
        }
        val em = Stats.mean(e)
        for (k in 0 until win) e[k] = (e[k] - em) * hann[k]
        val p = fft.powerSpectrum(e)
        val med = Stats.median(refIdx.map { p[it] }) + 1e-12
        for (k in p.indices) p[k] /= med
        var c = bandIdx[0]
        for (k in bandIdx) if (p[k] > p[c]) c = k
        val c2 = 2 * c
        var hmax = Double.NEGATIVE_INFINITY
        for (k in max(c2 - tol, 0) until min(c2 + tol + 1, p.size)) hmax = max(hmax, p[k])
        val comb = log10(p[c] + 1e-12) + log10(hmax + 1e-12)

        val muMean = mu.average()
        val out = DoubleArray(FEATURE_COUNT)
        for (b in 0 until nm) out[b] = mu[b] - muMean
        for (b in 0 until nm) out[nm + b] = sd[b]
        var rel = 0.0
        for (b in 0 until nm) rel += mu[b] - fl[b]
        out[2 * nm] = rel / nm
        out[2 * nm + 1] = comb
        return out
    }
}

@Serializable
data class LinearModel(val mean: List<Double>, val scale: List<Double>, val coef: List<Double>, val intercept: Double) {
    fun predict(x: DoubleArray): Double {
        var z = intercept
        for (i in coef.indices) z += (x[i] - mean[i]) / scale[i] * coef[i]
        return 1.0 / (1.0 + exp(-z))
    }
}

@Serializable
private data class HeadsFile(val feature_version: Int, val heads: Map<String, LinearModel>)

/** Brushing + water heads trained in Python (analysis/train.py). */
class ModelHeads(val brush: LinearModel, val water: LinearModel) {
    companion object {
        const val FEATURE_VERSION = 1
        private val json = Json { ignoreUnknownKeys = true }

        fun fromJson(text: String): ModelHeads {
            val f = json.decodeFromString(HeadsFile.serializer(), text)
            require(f.feature_version == FEATURE_VERSION) { "feature version ${f.feature_version}" }
            return ModelHeads(f.heads.getValue("brush"), f.heads.getValue("water"))
        }

        /** The model shipped with the app (trained on real recordings). */
        fun bundled(): ModelHeads {
            val stream = ModelHeads::class.java.getResourceAsStream("/brush_model.json")
                ?: error("brush_model.json missing")
            return fromJson(stream.bufferedReader().use { it.readText() })
        }
    }
}

data class SonicConfig(val bandLowHz: Double = 150.0, val bandHighHz: Double = 400.0) {
    val neighbourhoodHz = 30.0
    val stabilityHz = 3.0
    val floorRiseDbPerS = 0.1
    val harmonicMinDb = 3.0
    val hopS = 0.5

    companion object {
        fun calibrated(f0: Double, toleranceHz: Double = 10.0) = SonicConfig(f0 - toleranceHz, f0 + toleranceHz)
    }
}

data class SonicResult(val score: Double, val f0Hz: Double, val prominenceDb: Double, val noveltyDb: Double)

/** Sonic toothbrush detector: new, stable, narrow tone with 2x harmonic (sonic.py). */
class SonicDetector(val cfg: SonicConfig = SonicConfig()) {
    companion object {
        const val WINDOW_SAMPLES = 3 * SAMPLE_RATE
        const val HOP_SAMPLES = SAMPLE_RATE / 2
        const val NPERSEG = 8192

        fun describe(f0Hz: Double): String {
            val moves = (f0Hz * 120).roundToInt()
            val kind = if (f0Hz in 220.0..300.0) "szónikus fogkefe (Sonicare-típusú)" else "elektromos fogkefe"
            return "$kind: ${f0Hz.roundToInt()} Hz-es zúgás, kb. ${Formatting.grouped(moves)} mozdulat/perc"
        }
    }

    private val fft = FFT(NPERSEG)
    private val window = Windows.hannPeriodic(NPERSEG)
    private val densityScale: Double
    private val wideLo: Int
    private val wideHi: Int
    private val freqs: DoubleArray
    private val inBand: BooleanArray
    private val nb: Int
    private val tol: Int
    private var floor: DoubleArray? = null

    init {
        val df = SAMPLE_RATE.toDouble() / NPERSEG
        val idx = (0..NPERSEG / 2).filter {
            val f = it * df
            f >= cfg.bandLowHz - cfg.neighbourhoodHz && f <= 2 * cfg.bandHighHz + cfg.neighbourhoodHz
        }
        wideLo = idx.first()
        wideHi = idx.last()
        freqs = DoubleArray(wideHi - wideLo + 1) { (wideLo + it) * df }
        inBand = BooleanArray(freqs.size) { freqs[it] >= cfg.bandLowHz && freqs[it] <= cfg.bandHighHz }
        nb = 2 * (cfg.neighbourhoodHz / df).toInt() + 1
        tol = ceil(cfg.stabilityHz / df).toInt()
        var w2 = 0.0
        for (v in window) w2 += v * v
        densityScale = 1.0 / (SAMPLE_RATE * w2)
    }

    fun reset() { floor = null }

    private fun welchDb(x: DoubleArray, offset: Int, length: Int): DoubleArray {
        val n = NPERSEG
        val step = n / 2
        val segs = (length - n) / step + 1
        val acc = DoubleArray(n / 2 + 1)
        val seg = DoubleArray(n)
        for (s in 0 until segs) {
            val st = offset + s * step
            var m = 0.0
            for (i in 0 until n) m += x[st + i]
            m /= n
            for (i in 0 until n) seg[i] = (x[st + i] - m) * window[i]
            val p = fft.powerSpectrum(seg)
            for (k in p.indices) {
                var v = p[k] * densityScale
                if (k != 0 && k != n / 2) v *= 2
                acc[k] += v
            }
        }
        return DoubleArray(wideHi - wideLo + 1) { 10 * log10(acc[wideLo + it] / segs + 1e-16) }
    }

    /** One 3 s window x[offset until offset + 48000]; windows must be fed in order. */
    fun process(x: DoubleArray, offset: Int): SonicResult {
        val sub = SAMPLE_RATE
        val subs = List(WINDOW_SAMPLES / sub) { welchDb(x, offset + it * sub, sub) }
        val m = subs[0].size
        val spec = DoubleArray(m) { i ->
            var s = 0.0
            for (row in subs) s += 10.0.pow(row[i] / 10.0)
            10 * log10(s / subs.size)
        }
        val rise = cfg.floorRiseDbPerS * cfg.hopS
        val fl = floor?.let { old -> DoubleArray(m) { min(spec[it], old[it] + rise) } } ?: spec.copyOf()
        floor = fl

        val med = Stats.medianFilterNearest(spec, nb)
        val prom = DoubleArray(m) { spec[it] - med[it] }
        var k = -1
        for (i in 0 until m) if (inBand[i] && (k < 0 || prom[i] > prom[k])) k = i
        if (k < 0) return SonicResult(0.0, 0.0, 0.0, 0.0)

        val lo = max(k - 3 * tol, 0)
        val hi = min(k + 3 * tol + 1, m)
        var stable = true
        for (row in subs) {
            val rm = Stats.medianFilterNearest(row, nb)
            val sp = DoubleArray(m) { row[it] - rm[it] }
            val j = Stats.argmax(sp, lo, hi)
            stable = stable && abs(j - k) <= tol && sp[j] >= 6.0
        }
        val target = 2 * freqs[k]
        var k2 = 0
        for (i in 0 until m) if (abs(freqs[i] - target) < abs(freqs[k2] - target)) k2 = i
        var hmax = Double.NEGATIVE_INFINITY
        for (i in max(k2 - tol, 0) until min(k2 + tol + 1, m)) hmax = max(hmax, prom[i])
        val harmonic = hmax >= cfg.harmonicMinDb
        val novelty = spec[k] - fl[k]
        val score = Stats.ramp(prom[k], 8.0, 16.0) * Stats.ramp(novelty, 3.0, 9.0) * (if (stable && harmonic) 1.0 else 0.0)
        return SonicResult(score, freqs[k], prom[k], novelty)
    }
}
