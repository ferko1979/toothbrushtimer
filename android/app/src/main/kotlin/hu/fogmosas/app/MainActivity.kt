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
    /** App lock / parent lock state; locks again when the app goes to the background (not while brushing). */
    val unlocked = mutableStateOf(false)
    val parentUnlocked = mutableStateOf(false)
    lateinit var speaker: Speaker

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        speaker = Speaker(this)
        val store = AppStore.get(this)
        BrushingEngine.onFinished = { r ->
            if (r.durationS >= 5) {
                val d = store.data.value
                val rec = BrushRecord(profileId = d.activeProfileId, startMs = r.startMs, durationS = r.durationS,
                    waterRunningS = r.waterRunningS, source = if (r.manual) "manual" else "phone", brushF0 = r.brushF0)
                newAchievements.value = store.addRecord(rec)
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
        if (i?.getBooleanExtra(EXTRA_ARM, false) == true) armRequest.value = true
    }

    override fun onStart() {
        super.onStart()
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
