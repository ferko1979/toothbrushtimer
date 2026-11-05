package hu.fogmosas.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Test builds only ("Tesztfelvétel" switch): saves the microphone audio as a 16 kHz mono WAV and the
 * detector's timeline (scores every 0.5 s, events, result) as JSON, so a tester can send both to the
 * developers. Same format as ios/BrushCore/.../TestRecording.swift. Not thread-safe across threads
 * except through the synchronized methods.
 */
class TestRecording(dir: File, private val meta: Map<String, Any?>) {
    companion object {
        const val MAX_SECONDS = 8 * 60
        private const val RATE = 16000

        /** Newest recording (wav + json + remark) in the folder, if any. */
        fun latest(dir: File): List<File> {
            val base = bases(dir).lastOrNull() ?: return emptyList()
            return filesOf(dir, base)
        }

        /** Recording names (oldest first): one per WAV or JSON timeline. */
        fun bases(dir: File): List<String> = (dir.listFiles()?.map { it.name } ?: emptyList())
            .filter { it.startsWith("denthub-brush-") && (it.endsWith(".wav") || (it.endsWith(".json"))) }
            .map { it.substringBeforeLast('.') }.distinct().sorted()

        /** The files of one recording that exist: audio, timeline, tester's remark. */
        fun filesOf(dir: File, base: String): List<File> =
            listOf("$base.wav", "$base.json", "$base$REMARK").map { File(dir, it) }.filter { it.exists() }

        /** Every recording with its remark (oldest first). */
        fun all(dir: File): List<File> = bases(dir).flatMap { filesOf(dir, it) }

        const val REMARK = "-remark.txt"

        /** Saves (overwrites) the tester's remark next to the recording, as they type it. */
        fun saveRemark(dir: File, base: String, text: String) {
            if (!File(dir, "$base.wav").exists()) return
            File(dir, "$base$REMARK").writeText(text)
        }

        /** Keeps every recording; only when they take more than maxBytes are the oldest dropped. */
        fun prune(dir: File, maxBytes: Long = 2_000_000_000L) {
            val groups = bases(dir).map { filesOf(dir, it) }
            var total = groups.sumOf { g -> g.sumOf { it.length() } }
            for (g in groups) {
                if (total <= maxBytes) break
                total -= g.sumOf { it.length() }
                g.forEach { it.delete() }
            }
        }

        /** Packs every recording and remark into one ZIP (for Drive / e-mail). */
        fun zipAll(dir: File, out: File): File? {
            val files = all(dir)
            if (files.isEmpty()) return null
            out.parentFile?.mkdirs()
            java.util.zip.ZipOutputStream(out.outputStream().buffered()).use { z ->
                for (f in files) {
                    z.putNextEntry(java.util.zip.ZipEntry(f.name))
                    f.inputStream().use { it.copyTo(z) }
                    z.closeEntry()
                }
            }
            return out
        }
    }

    val base: String = "denthub-brush-" + SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
    val wavFile = File(dir.apply { mkdirs() }, "$base.wav")
    val jsonFile = File(dir, "$base.json")
    private val raf = RandomAccessFile(wavFile, "rw").apply { setLength(0); write(ByteArray(44)) }
    private var samples = 0L
    private val rows = ArrayList<JsonArray>()
    private val events = ArrayList<JsonArray>()
    private var closed = false
    private val buf = ByteArray(2 * 4096)

    @Synchronized fun append(x: FloatArray, n: Int) {
        if (closed || samples >= MAX_SECONDS.toLong() * RATE) return
        var i = 0
        while (i < n) {
            val m = minOf(n - i, 4096)
            for (k in 0 until m) {
                val v = (x[i + k].coerceIn(-1f, 1f) * 32767f).toInt()
                buf[2 * k] = (v and 0xff).toByte(); buf[2 * k + 1] = ((v shr 8) and 0xff).toByte()
            }
            raf.write(buf, 0, 2 * m)
            i += m
        }
        samples += n
    }

    private fun num(d: Double) = JsonPrimitive(Math.round(d * 1000) / 1000.0)

    @Synchronized fun row(r: ScoreRow, state: String, rmsDb: Double = -120.0) {
        if (!closed) rows += JsonArray(listOf(num(r.t), num(r.brush), num(r.water), num(r.sonic), num(r.sonicF0), JsonPrimitive(state), num(rmsDb)))
    }

    @Synchronized fun event(t: Double, name: String) {
        if (!closed) events += JsonArray(listOf(num(t), JsonPrimitive(name)))
    }

    /** Finalises the WAV header and writes the JSON. result: durationS, endReason, cue, waterRunningS (or empty). */
    @Synchronized fun finish(result: Map<String, Any?>): List<File> {
        if (closed) return listOf(wavFile, jsonFile)
        closed = true
        val dataBytes = samples * 2
        raf.seek(0)
        raf.write(wavHeader(dataBytes))
        raf.close()
        fun js(v: Any?): kotlinx.serialization.json.JsonElement = when (v) {
            null -> kotlinx.serialization.json.JsonNull
            is Number -> JsonPrimitive(v)
            is Boolean -> JsonPrimitive(v)
            is Map<*, *> -> JsonObject(v.entries.associate { it.key.toString() to js(it.value) })
            else -> JsonPrimitive(v.toString())
        }
        val obj = JsonObject(mapOf(
            "format" to JsonPrimitive("denthub-brush-test-1"),
            "wav" to JsonPrimitive(wavFile.name),
            "sampleRate" to JsonPrimitive(RATE),
            "audioSeconds" to JsonPrimitive(samples.toDouble() / RATE),
            "meta" to js(meta),
            "result" to js(result),
            "rowColumns" to JsonArray(listOf("t", "brush", "water", "sonic", "sonicF0", "state", "rmsDb").map { JsonPrimitive(it) }),
            "rows" to JsonArray(rows),
            "events" to JsonArray(events),
        ))
        jsonFile.writeText(obj.toString())
        return listOf(wavFile, jsonFile)
    }

    private fun wavHeader(dataBytes: Long): ByteArray {
        val b = java.nio.ByteBuffer.allocate(44).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()); b.putInt((36 + dataBytes).toInt()); b.put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()); b.putInt(16); b.putShort(1); b.putShort(1); b.putInt(RATE); b.putInt(RATE * 2)
        b.putShort(2); b.putShort(16)
        b.put("data".toByteArray()); b.putInt(dataBytes.toInt())
        return b.array()
    }
}
