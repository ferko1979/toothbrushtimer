package hu.fogmosas.core

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** All detectors work on 16 kHz mono audio. */
const val SAMPLE_RATE = 16000

/** Iterative radix-2 complex FFT (pure Kotlin, same algorithm as the Swift port). */
class FFT(val n: Int) {
    private val cosT: DoubleArray
    private val sinT: DoubleArray
    private val rev: IntArray

    init {
        require(n > 1 && (n and (n - 1)) == 0) { "FFT size must be a power of two" }
        var levels = 0
        var m = n
        while (m > 1) { m = m shr 1; levels++ }
        cosT = DoubleArray(n / 2) { cos(2.0 * PI * it / n) }
        sinT = DoubleArray(n / 2) { sin(2.0 * PI * it / n) }
        rev = IntArray(n) { i ->
            var x = i
            var r = 0
            repeat(levels) { r = (r shl 1) or (x and 1); x = x shr 1 }
            r
        }
    }

    fun transform(re: DoubleArray, im: DoubleArray) {
        for (i in 0 until n) {
            val j = rev[i]
            if (j > i) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var size = 2
        while (size <= n) {
            val half = size / 2
            val step = n / size
            var start = 0
            while (start < n) {
                var k = 0
                for (j in start until start + half) {
                    val c = cosT[k]
                    val s = sinT[k]
                    val l = j + half
                    val tre = re[l] * c + im[l] * s
                    val tim = im[l] * c - re[l] * s
                    re[l] = re[j] - tre
                    im[l] = im[j] - tim
                    re[j] += tre
                    im[j] += tim
                    k += step
                }
                start += size
            }
            size *= 2
        }
    }

    /** |X[k]|^2 for k = 0..n/2 of a real signal (zero-padded or truncated to n). */
    fun powerSpectrum(x: DoubleArray, offset: Int = 0, length: Int = x.size): DoubleArray {
        val re = DoubleArray(n)
        val im = DoubleArray(n)
        val m = minOf(length, n)
        for (i in 0 until m) re[i] = x[offset + i]
        transform(re, im)
        return DoubleArray(n / 2 + 1) { re[it] * re[it] + im[it] * im[it] }
    }
}

internal object Windows {
    /** scipy get_window('hann', n): periodic. */
    fun hannPeriodic(n: Int) = DoubleArray(n) { 0.5 - 0.5 * cos(2.0 * PI * it / n) }

    /** numpy np.hanning(n): symmetric. */
    fun hannSymmetric(n: Int) = if (n == 1) doubleArrayOf(1.0) else DoubleArray(n) { 0.5 - 0.5 * cos(2.0 * PI * it / (n - 1)) }
}

internal object Stats {
    fun mean(a: DoubleArray) = if (a.isEmpty()) 0.0 else a.sum() / a.size
    fun mean(a: List<Double>) = if (a.isEmpty()) 0.0 else a.sum() / a.size

    fun std(a: DoubleArray): Double {
        if (a.isEmpty()) return 0.0
        val m = mean(a)
        var s = 0.0
        for (v in a) s += (v - m) * (v - m)
        return sqrt(s / a.size)
    }

    /** numpy median (average of the two middle values for even counts). */
    fun median(a: List<Double>): Double {
        if (a.isEmpty()) return 0.0
        val s = a.sorted()
        val n = s.size
        return if (n % 2 == 1) s[n / 2] else 0.5 * (s[n / 2 - 1] + s[n / 2])
    }

    /** scipy.ndimage.median_filter(a, size, mode="nearest") for odd size. */
    fun medianFilterNearest(a: DoubleArray, size: Int): DoubleArray {
        val n = a.size
        val h = size / 2
        val buf = DoubleArray(size)
        return DoubleArray(n) { i ->
            for (o in 0 until size) buf[o] = a[(i + o - h).coerceIn(0, n - 1)]
            buf.sort()
            buf[h]
        }
    }

    /** First index of the maximum in [lo, hi). */
    fun argmax(a: DoubleArray, lo: Int = 0, hi: Int = a.size): Int {
        val end = minOf(hi, a.size)
        var best = lo
        for (i in lo until end) if (a[i] > a[best]) best = i
        return best
    }

    fun ramp(x: Double, lo: Double, hi: Double) = ((x - lo) / (hi - lo)).coerceIn(0.0, 1.0)
}
