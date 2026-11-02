package hu.fogmosas.shared

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import hu.fogmosas.core.CueTracker
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
    )

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
        _state.value = State(phase = Phase.LISTENING, armed = cfg.armed)
        val heads = cfg.heads
        if (!cfg.autoDetect || heads == null) {
            startManual(ctx)
            return
        }
        // Until the goal is reached, stop only after a long silence or a clear rinse.
        val sc = policy.sessionConfig.let {
            it.copy(holdUntilS = cfg.targetS, endQuietS = it.endQuietS + cfg.quietExtraS, holdQuietS = it.holdQuietS + cfg.quietExtraS)
        }
        userStop = false
        val det = StreamingDetector(heads, sc, cfg.sonicConfig, cfg.useSonic, cfg.batterySaver)
        det.onRow = { row -> onRow(row, det) }
        det.session.onEvent = { _, e -> onEvent(e, det) }
        detector = det
        listenStartMs = System.currentTimeMillis()
        try {
            audio = AudioEngine { buf, n -> det.append(buf, n) }.also { it.start(ctx) }
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
        val det = detector ?: run { if (_state.value.result == null) _state.update { it.copy(phase = Phase.IDLE) }; stopTicker(); return }
        det.finish()   // may emit SESSION_END -> finish()
        detector = null
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
        policy.motion(now(), gx, gy, gz)
        if (policy.placed != _state.value.placed) _state.update { it.copy(placed = policy.placed) }
        checkPolicy()
    }

    private fun checkPolicy() {
        val s = _state.value
        if (!policy.listening && s.active && !s.manual && s.phase != Phase.BRUSHING) {
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
    private fun onEvent(e: SessionEvent, det: StreamingDetector) {
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
