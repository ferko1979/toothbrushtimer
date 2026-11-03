package hu.fogmosas.shared

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import hu.fogmosas.core.tr

/**
 * Microphone -> 16 kHz mono float chunks on a background thread. Uses the
 * UNPROCESSED source when available (no noise suppression, which would remove
 * the brushing sound). No audio is ever stored.
 */
class AudioEngine(private val onSamples: (FloatArray, Int) -> Unit) {
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false

    @SuppressLint("MissingPermission")
    fun start(context: Context) {
        if (running) return
        val am = context.getSystemService(AudioManager::class.java)
        val unprocessed = am?.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        val source = if (unprocessed) MediaRecorder.AudioSource.UNPROCESSED else MediaRecorder.AudioSource.VOICE_RECOGNITION
        val rate = 16000
        val minBuf = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val r = AudioRecord(source, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, maxOf(minBuf, rate * 4))
        check(r.state == AudioRecord.STATE_INITIALIZED) { tr("A mikrofon nem érhető el.") }
        r.startRecording()
        record = r
        direction?.let { applyDirection(r, it) }
        running = true
        thread = Thread({
            val buf = FloatArray(1600)
            while (running) {
                val n = r.read(buf, 0, buf.size, AudioRecord.READ_BLOCKING)
                if (n > 0) onSamples(buf, n)
            }
        }, "brush-audio").apply { start() }
    }

    private var direction: Boolean? = null

    /**
     * Directional pickup where the phone supports it (Android 10+): towards the user = the screen /
     * selfie-camera side (phone face up), away = the back (phone face down).
     */
    fun setDirection(towardsScreen: Boolean) {
        if (direction == towardsScreen) return
        direction = towardsScreen
        record?.let { applyDirection(it, towardsScreen) }
    }

    private fun applyDirection(r: AudioRecord, towardsScreen: Boolean) {
        if (android.os.Build.VERSION.SDK_INT < 29) return
        runCatching {
            r.setPreferredMicrophoneDirection(
                if (towardsScreen) android.media.MicrophoneDirection.MIC_DIRECTION_TOWARDS_USER
                else android.media.MicrophoneDirection.MIC_DIRECTION_AWAY_FROM_USER)
        }
    }

    fun stop() {
        running = false
        thread?.join(1000)
        thread = null
        record?.let { runCatching { it.stop() }; it.release() }
        record = null
    }
}
