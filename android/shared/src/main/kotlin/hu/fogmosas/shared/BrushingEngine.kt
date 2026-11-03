package hu.fogmosas.shared

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import hu.fogmosas.core.CueTracker
import hu.fogmosas.core.Formatting
import hu.fogmosas.core.ListeningPolicy
import hu.fogmosas.core.ModelHeads
import hu.fogmosas.core.ScoreRow
import hu.fogmosas.core.SessionConfig
import hu.fogmosas.core.SessionDetector
import hu.fogmosas.core.SessionEvent
import hu.fogmosas.core.SonicConfig
import hu.fogmosas.core.StreamingDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import hu.fogmosas.core.tr

/** One listening period: microphone -> StreamingDetector -> session, as observable state. */
object BrushingEngine {
    enum class Phase { IDLE, LISTENING, WATER, ARMED, BRUSHING, RINSING, FINISHED, FAILED }

    data class Result(val startMs: Long, val durationS: Double, val waterRunningS: Double, val cue: String,
                      val brushF0: Double?, val manual: Boolean, val endReason: String = "finish")

    data class State(
        val phase: Phase = Phase.IDLE,
        val elapsedS: Double = 0.0,
        val wasteIcon: Boolean = false,
        val waterRunningS: Double = 0.0,
        val liveF0: Double? = null,
        val result: Result? = null,
        val manual: Boolean = false,
        val error: String? = null,
        val placed: Boolean = false,
        val armed: Boolean = false,
        val stopNote: String? = null,
        /** Test mode: what the detector noticed (shown live), and the session it measured on its own. */
        val testMode: Boolean = false,
        val testLog: List<String> = emptyList(),
        val testDetected: Result? = null,
    ) {
        val active get() = phase in setOf(Phase.LISTENING, Phase.WATER, Phase.ARMED, Phase.BRUSHING, Phase.RINSING)
    }

    data class Config(
        val heads: ModelHeads?,
        val autoDetect: Boolean,
        val armed: Boolean,
        val sonicConfig: SonicConfig,
        val useSonic: Boolean,
        val batterySaver: Boolean,
        val targetS: Double,
        val cues: Boolean,
        val keepListeningWhenPlaced: Boolean,
        /** Learned from feedback: extra seconds of silence before the measurement stops. */
        val quietExtraS: Double = 0.0,
        /** Only sounds close to the phone (about 2 m) may start a measurement. */
        val nearOnly: Boolean = false,
        /** Point the microphone by orientation (screen side when face up, back when face down). */
        val directional: Boolean = false,
        /** Test builds: save audio + detector timeline for the developers. */
        val testRecording: Boolean = false,
        val meta: Map<String, Any?> = emptyMap(),
    )

    /** Near-sound filter threshold above the background level (tuned from test recordings). */
    const val NEAR_GATE_DB = 10.0

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    /** Called (on the main thread) when a brushing ends; the app saves the record. */
    var onFinished: ((Result) -> Unit)? = null

    val policy = ListeningPolicy()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var appContext: Context? = null
    private var audio: AudioEngine? = null
    @Volatile private var detector: StreamingDetector? = null
    private var cueTracker: CueTracker? = null
    private var cuesOn = true
    private var targetS = 120.0
    /** Goal of the running brushing (for the ongoing notification). */
    val currentTargetS get() = targetS
    private val f0s = ArrayList<Double>()
    private var listenStartMs = 0L
    private var manualStartMs: Long? = null
    @Volatile private var userStop = false
    @Volatile private var recording: hu.fogmosas.core.TestRecording? = null
    @Volatile private var testMode = false
    @Volatile private var testResult: Result? = null
    private var policyUsesMotion = false
    private var directional = false

    fun recordingsDir(ctx: Context) = java.io.File(ctx.cacheDir, "recordings")

    /** Closes the test recording (if any) on a background thread. */
    private fun closeRecording(r: Result?) {
        val rec = recording ?: return
        recording = null
        val ctx = appContext
        Thread {
            rec.finish(if (r == null) mapOf("endReason" to "no_session") else mapOf(
                "durationS" to r.durationS, "endReason" to r.endReason, "cue" to r.cue, "waterRunningS" to r.waterRunningS, "manual" to r.manual))
            ctx?.let { hu.fogmosas.core.TestRecording.prune(recordingsDir(it)) }
        }.start()
    }
    private var ticker: Job? = null
    private val t0 = System.currentTimeMillis()
    private fun now() = (System.currentTimeMillis() - t0) / 1000.0

    fun start(context: Context, cfg: Config) {
        if (_state.value.active) return
        val ctx = context.applicationContext
        appContext = ctx
        targetS = cfg.targetS
        cuesOn = cfg.cues
        f0s.clear()
        cueTracker = null
        policy.appOpened(now(), cfg.armed)
        policyUsesMotion = cfg.keepListeningWhenPlaced
        directional = cfg.directional
        // Test mode: the detector works on its own while the recording runs until the tester stops it.
        testMode = cfg.testRecording && cfg.autoDetect && cfg.heads != null
        testResult = null
        _state.value = State(phase = Phase.LISTENING, armed = cfg.armed, testMode = testMode)
        val heads = cfg.heads
        if (!cfg.autoDetect || heads == null) {
            startManual(ctx)
            return
        }
        // Until the goal is reached, stop only after a long silence or a clear rinse.
        val sc = policy.sessionConfig.let {
            it.copy(holdUntilS = cfg.targetS, endQuietS = it.endQuietS + cfg.quietExtraS, holdQuietS = it.holdQuietS + cfg.quietExtraS,
                sonicSuppressesWater = cfg.useSonic, runHysteresis = true)
        }
        userStop = false
        val det = StreamingDetector(heads, sc, cfg.sonicConfig, cfg.useSonic, cfg.batterySaver,
            nearGateDb = if (cfg.nearOnly) NEAR_GATE_DB else null)
        recording = if (cfg.testRecording) runCatching {
            hu.fogmosas.core.TestRecording(recordingsDir(ctx), cfg.meta + mapOf("sessionConfig" to sc.toString(), "useSonic" to cfg.useSonic))
        }.getOrNull() else null
        det.onRow = { row -> recording?.row(row, det.session.state.name, det.lastRmsDb); onRow(row, det) }
        det.session.onEvent = { t, e -> recording?.event(t, e.id); onEvent(t, e, det) }
        detector = det
        listenStartMs = System.currentTimeMillis()
        try {
            audio = AudioEngine { buf, n -> det.append(buf, n); recording?.append(buf, n) }.also { it.start(ctx) }
        } catch (e: Exception) {
            detector = null
            _state.value = State(phase = Phase.FAILED, error = e.message ?: tr("A mikrofon nem indítható."))
            return
        }
        startService(ctx, cfg.keepListeningWhenPlaced)
        startTicker()
    }

    fun startManual(context: Context) = resume(context, 0.0)

    /** Timer continuing from fromS seconds ("Még mostam – folytatás" after an early stop, or manual start). */
    fun resume(context: Context, fromS: Double) {
        val ctx = context.applicationContext
        appContext = ctx
        stopAudio()
        detector = null
        manualStartMs = System.currentTimeMillis() - (fromS * 1000).toLong()
        cueTracker = CueTracker(targetS).also { if (fromS > 0) it.update(fromS) }
        _state.value = State(phase = Phase.BRUSHING, manual = true)
        startService(ctx, false)
        startTicker()
    }

    /** Stop listening; an open session is closed and reported. */
    fun stop() {
        val ms = manualStartMs
        if (ms != null) {
            manualStartMs = null
            finish(Result(ms, (System.currentTimeMillis() - ms) / 1000.0, 0.0, "manual", null, true, "user"))
            return
        }
        userStop = true
        stopAudio()
        if (testMode) {
            // The tester ends the recording; report what the detector measured on its own.
            detector?.finish()
            detector = null
            testMode = false
            stopTicker()
            val r = testResult
            if (r != null) finish(r) else {
                closeRecording(null)
                _state.update { it.copy(phase = Phase.IDLE) }
            }
            return
        }
        val det = detector ?: run { if (_state.value.result == null) _state.update { it.copy(phase = Phase.IDLE) }; stopTicker(); return }
        det.finish()   // may emit SESSION_END -> finish()
        detector = null
        if (_state.value.result == null) closeRecording(null)
        if (_state.value.result == null) _state.update { it.copy(phase = Phase.IDLE) }
        stopTicker()
    }

    /** Back to idle after the result was shown. */
    fun reset() {
        if (_state.value.active) stop()
        _state.value = State()
    }

    fun appForeground() = policy.appForegrounded(now())
    fun appBackground() {
        policy.appBackgrounded(now())
        checkPolicy()
    }

    fun motion(gx: Double, gy: Double, gz: Double) {
        if (policyUsesMotion) policy.motion(now(), gx, gy, gz)
        // Face up: listen towards the screen side; face down: towards the back.
        if (directional) { if (gz > 0.6) audio?.setDirection(true) else if (gz < -0.6) audio?.setDirection(false) }
        if (policy.placed != _state.value.placed) _state.update { it.copy(placed = policy.placed) }
        checkPolicy()
    }

    private fun checkPolicy() {
        val s = _state.value
        if (!testMode && !policy.listening && s.active && !s.manual && s.phase != Phase.BRUSHING) {
            val note = policy.stopReason
            stop()
            _state.update { it.copy(stopNote = note) }
        }
    }

    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                delay(250)
                val ms = manualStartMs
                if (ms != null) {
                    val el = (System.currentTimeMillis() - ms) / 1000.0
                    _state.update { it.copy(elapsedS = el) }
                    fireCues(el)
                } else {
                    policy.tick(now())
                    checkPolicy()
                }
            }
        }
    }

    private fun stopTicker() { ticker?.cancel(); ticker = null }

    private fun stopAudio() { audio?.stop(); audio = null }

    private fun fireCues(elapsed: Double) {
        val ctx = appContext ?: return
        val tr = cueTracker ?: return
        if (!cuesOn) return
        for (c in tr.update(elapsed)) Haptics.play(ctx, c.haptic)
    }

    // Audio thread.
    private fun onRow(row: ScoreRow, det: StreamingDetector) {
        val s = det.session
        val cur = s.current
        if (s.state == SessionDetector.State.BRUSHING && row.sonic > 0.5 && row.sonicF0 > 0) synchronized(f0s) { f0s += row.sonicF0 }
        val elapsed = cur?.let { maxOf(det.audioTime - it.start, 0.0) } ?: 0.0
        val phase = when (s.state) {
            SessionDetector.State.LISTENING -> Phase.LISTENING
            SessionDetector.State.WATER -> Phase.WATER
            SessionDetector.State.ARMED -> Phase.ARMED
            SessionDetector.State.BRUSHING -> Phase.BRUSHING
            SessionDetector.State.RINSE -> Phase.RINSING
        }
        val f0 = synchronized(f0s) { if (f0s.isEmpty()) null else f0s.sorted()[f0s.size / 2] }
        val activity = row.water > 0.5 || row.brush > 0.5 || row.sonic > 0.5
        val waste = s.wasteIcon
        val water = cur?.waterRunningS ?: 0.0
        scope.launch {
            if (activity) policy.activity(now())
            if (_state.value.result != null) return@launch
            _state.update { it.copy(phase = phase, elapsedS = elapsed, waterRunningS = water, wasteIcon = waste, liveF0 = f0) }
            if (phase == Phase.BRUSHING || phase == Phase.RINSING) fireCues(elapsed)
        }
    }

    // Audio thread (or main thread from stop()).
    private fun testLabel(e: SessionEvent): String? = when (e) {
        SessionEvent.WATER_START -> tr("🚰 víz")
        SessionEvent.WATER_STOP -> tr("víz elzárva")
        SessionEvent.BRUSHING_DETECTED -> tr("🪥 fogmosás észlelve")
        SessionEvent.RINSE_START -> tr("💧 öblítés")
        SessionEvent.BRUSHING_RESUMED -> tr("🪥 folytatódik")
        SessionEvent.WASTE_ICON_ON -> tr("⚠️ folyik a csap")
        else -> null
    }

    private fun onEvent(t: Double, e: SessionEvent, det: StreamingDetector) {
        if (testMode) {
            val clock = Formatting.clock(t)
            if (e == SessionEvent.SESSION_END) {
                val session = det.session.sessions.last()
                val reason = if (session.endReason == "finish" && userStop) "user" else session.endReason
                val r = Result(listenStartMs + (session.start * 1000).toLong(), session.durationS, session.waterRunningS,
                    session.cue, null, false, reason)
                // Keep the longest session the detector found.
                if (testResult == null || r.durationS > testResult!!.durationS) testResult = r
                val line = "$clock " + tr("🏁 vége – mért idő: {0}", Formatting.clock(r.durationS))
                scope.launch {
                    appContext?.let { Haptics.play(it, "success") }
                    _state.update { it.copy(testLog = it.testLog + line, testDetected = testResult) }
                }
                return
            }
            testLabel(e)?.let { label ->
                scope.launch {
                    if (e == SessionEvent.BRUSHING_DETECTED) { cueTracker = CueTracker(targetS); appContext?.let { Haptics.play(it, "tap") } }
                    _state.update { it.copy(testLog = it.testLog + "$clock $label") }
                }
            }
            return
        }
        when (e) {
            SessionEvent.BRUSHING_DETECTED -> scope.launch { cueTracker = CueTracker(targetS) }
            SessionEvent.WASTE_ICON_ON -> scope.launch { appContext?.let { Haptics.warning(it) } }
            SessionEvent.SESSION_END -> {
                val session = det.session.sessions.last()
                val f0 = synchronized(f0s) { if (f0s.size >= 4) f0s.sorted()[f0s.size / 2] else null }
                val reason = if (session.endReason == "finish" && userStop) "user" else session.endReason
                val r = Result(listenStartMs + (session.start * 1000).toLong(), session.durationS, session.waterRunningS,
                    session.cue, f0, false, reason)
                scope.launch {
                    stopAudio()
                    detector = null
                    stopTicker()
                    finish(r)
                }
            }
            else -> Unit
        }
    }

    private fun finish(r: Result) {
        if (_state.value.result != null) return
        closeRecording(r)
        policy.sessionFinished(now())
        _state.update { it.copy(phase = Phase.FINISHED, result = r, elapsedS = r.durationS) }
        stopTicker()
        appContext?.let { Haptics.play(it, "success") }
        onFinished?.invoke(r)
    }

    private fun startService(ctx: Context, keepListening: Boolean) {
        val i = Intent(ctx, BrushingService::class.java).putExtra(BrushingService.EXTRA_KEEP_LISTENING, keepListening)
        runCatching { ContextCompat.startForegroundService(ctx, i) }
    }
}
