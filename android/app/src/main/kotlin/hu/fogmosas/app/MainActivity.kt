package hu.fogmosas.app

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.compose.runtime.mutableStateOf
import androidx.fragment.app.FragmentActivity
import hu.fogmosas.core.BrushRecord
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.BrushingEngine
import hu.fogmosas.shared.WearSync

class MainActivity : FragmentActivity() {
    companion object { const val EXTRA_ARM = "arm" }

    /** Set when opened from a reminder: start listening right away, brushing is expected. */
    val armRequest = mutableStateOf(false)
    val newAchievements = mutableStateOf<List<String>>(emptyList())
    /** Record saved for the last result (replaced when the user resumes an early-stopped brushing). */
    var lastRecordId: String? = null
    /** App lock / parent lock state; locks again when the app goes to the background (not while brushing). */
    val unlocked = mutableStateOf(false)
    val parentUnlocked = mutableStateOf(false)
    /** "Not linked to DentHub yet" banner: shown again every time the app is opened. */
    val linkReminder = mutableStateOf(true)
    /** Bumped on every return to the app, at midnight and on pull-to-refresh: the pages are rebuilt for "today". */
    val refreshTick = androidx.compose.runtime.mutableIntStateOf(0)
    /** Pull-to-refresh / back to the app: reread today's numbers and replan the reminders. */
    fun refresh() {
        refreshTick.intValue++
        ReminderScheduler.reschedule(this)
    }
    /** Full-screen page over the tabs: "symptom", "visit", "visit:<symptomId>" (null: none). */
    val overlay = mutableStateOf<String?>(null)
    /** A clinic link code opened from a QR / link, waiting for the user's confirmation. */
    val pendingClinic = mutableStateOf<hu.fogmosas.core.ClinicInfo?>(null)
    /** The clinic logo screen is shown once per app start. */
    val splashShown = mutableStateOf(false)
    /** Care instructions from the clinic (denthub://care link / QR), waiting for confirmation. */
    val pendingCare = mutableStateOf<hu.fogmosas.core.CareInstruction?>(null)
    lateinit var speaker: Speaker

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        speaker = Speaker(this)
        val store = AppStore.get(this)
        BrushingEngine.onFinished = { r ->
            if (r.durationS >= 5) {
                val d = store.data.value
                val rec = BrushRecord(profileId = d.activeProfileId, startMs = r.startMs, durationS = r.durationS,
                    waterRunningS = r.waterRunningS, source = if (r.manual) "manual" else "phone", brushF0 = r.brushF0, brushDb = r.brushDb)
                lastRecordId = rec.id
                newAchievements.value = store.addRecord(rec)
                // Battery running low: remember it and suggest charging until the user charges it
                // (or a later brushing hums normally).
                store.data.value.activeProfile.let { p ->
                    if (r.notes.isNotEmpty()) store.updateProfile(p.copy(chargeReminderMs = System.currentTimeMillis()))
                    else if (p.chargeReminderMs != null && !r.manual && r.brushF0 != null) store.updateProfile(p.copy(chargeReminderMs = null))
                }
                ReminderScheduler.reschedule(this)
            }
        }
        handleIntent(intent)
        ReminderScheduler.reschedule(this)
        store.data.value.profile("me")?.let { WearSync.pushGoals(this, it.goals) }
        setContent { AppRoot(this, store) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(i: Intent?) {
        // Reminder notification or the "Fogmosás indítása" launcher shortcut: brushing is expected right away.
        if (i?.getBooleanExtra(EXTRA_ARM, false) == true || i?.action == "hu.fogmosas.action.START_BRUSHING") armRequest.value = true
        // DentHub clinic link (QR code or link from the clinic).
        if (i?.action == Intent.ACTION_VIEW) i.dataString?.let { s ->
            hu.fogmosas.core.parseClinicLink(s)?.let { pendingClinic.value = it }
            hu.fogmosas.core.parseCareLink(s)?.let { pendingCare.value = it }
        }
        // "Panaszom van" launcher shortcut.
        if (i?.action == "hu.fogmosas.action.COMPLAINT") overlay.value = "symptom"
    }

    override fun onStart() {
        super.onStart()
        linkReminder.value = true
        refresh()
        BrushingEngine.appForeground()
    }

    override fun onStop() {
        if (!BrushingEngine.state.value.active && !isChangingConfigurations) {
            unlocked.value = false
            parentUnlocked.value = false
        }
        BrushingEngine.appBackground()
        super.onStop()
    }

    override fun onDestroy() {
        speaker.shutdown()
        super.onDestroy()
    }

    fun requestPermissions(onResult: () -> Unit = {}) {
        val perms = buildList {
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        requestPermissions(perms.toTypedArray(), 1)
        onResult()
    }
}
