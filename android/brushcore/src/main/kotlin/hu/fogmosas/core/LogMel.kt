package hu.fogmosas.core

import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * 32-band log-mel energies, 1024-sample frames, 160-sample hop.
 * Matches log_mel() in analysis/brushdetect/learned.py (scipy.signal.stft,
 * periodic Hann, output scaled by 1/sum(window)).
 */
class LogMelExtractor {
    companion object {
        const val N_MELS = 32
        const val NFFT = 1024
        const val HOP = 160

        fun makeFilterbank(fmin: Double = 80.0, fmax: Double = 7900.0): Array<DoubleArray> {
            fun mel(f: Double) = 2595.0 * log10(1.0 + f / 700.0)
            fun imel(m: Double) = 700.0 * (10.0.pow(m / 2595.0) - 1.0)
            val n = N_MELS + 2
            val m0 = mel(fmin)
            val m1 = mel(fmax)
            val pts = DoubleArray(n) { imel(m0 + (m1 - m0) * it / (n - 1)) }
            val bins = NFFT / 2 + 1
            return Array(N_MELS) { i ->
                val lo = pts[i]; val c = pts[i + 1]; val hi = pts[i + 2]
                DoubleArray(bins) { b ->
                    val f = b.toDouble() * SAMPLE_RATE / NFFT
                    max(min((f - lo) / (c - lo), (hi - f) / (hi - c)), 0.0)
                }
            }
        }
    }

    private val fft = FFT(NFFT)
    private val window = Windows.hannPeriodic(NFFT)
    private val scale: Double
    private val filterbank = makeFilterbank()

    init {
        val ws = window.sum()
        scale = 1.0 / (ws * ws)
    }

    /** One frame from x[offset until offset + NFFT]. */
    fun frame(x: DoubleArray, offset: Int): DoubleArray {
        val buf = DoubleArray(NFFT) { x[offset + it] * window[it] }
        val p = fft.powerSpectrum(buf)
        return DoubleArray(N_MELS) { m ->
            val w = filterbank[m]
            var s = 0.0
            for (b in p.indices) if (w[b] != 0.0) s += w[b] * p[b]
            ln(s * scale + 1e-10)
        }
    }

    fun frames(x: DoubleArray): List<DoubleArray> {
        if (x.size < NFFT) return emptyList()
        val count = (x.size - NFFT) / HOP + 1
        return List(count) { frame(x, it * HOP) }
    }
}

/** Minimal 16-bit PCM WAV reader (golden tests). */
object WavReader {
    fun read(bytes: ByteArray): Pair<DoubleArray, Int> {
        fun u32(o: Int) = (bytes[o].toInt() and 0xff) or ((bytes[o + 1].toInt() and 0xff) shl 8) or
            ((bytes[o + 2].toInt() and 0xff) shl 16) or ((bytes[o + 3].toInt() and 0xff) shl 24)
        fun u16(o: Int) = (bytes[o].toInt() and 0xff) or ((bytes[o + 1].toInt() and 0xff) shl 8)
        require(String(bytes, 0, 4) == "RIFF" && String(bytes, 8, 4) == "WAVE") { "not a WAV file" }
        var pos = 12
        var channels = 1
        var rate = SAMPLE_RATE
        var dataStart = -1
        var dataLen = 0
        while (pos + 8 <= bytes.size) {
            val id = String(bytes, pos, 4)
            val len = u32(pos + 4)
            if (id == "fmt ") {
                channels = u16(pos + 10)
                rate = u32(pos + 12)
            } else if (id == "data") {
                dataStart = pos + 8
                dataLen = min(len, bytes.size - dataStart)
                break
            }
            pos += 8 + len + (len and 1)
        }
        require(dataStart >= 0) { "no data chunk" }
        val frames = dataLen / (2 * channels)
        val out = DoubleArray(frames) { f ->
            var acc = 0.0
            for (c in 0 until channels) {
                val o = dataStart + 2 * (f * channels + c)
                val v = ((bytes[o].toInt() and 0xff) or (bytes[o + 1].toInt() shl 8)).toShort()
                acc += v / 32768.0
            }
            acc / channels
        }
        return out to rate
    }
}
