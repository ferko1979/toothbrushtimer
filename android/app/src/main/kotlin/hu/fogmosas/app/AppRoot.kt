package hu.fogmosas.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.SonicConfig
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.BrushingEngine

@Composable
fun AppRoot(activity: MainActivity, store: AppStore) {
    FogmosasTheme {
        val data by store.data.collectAsStateWithLifecycle()
        val engine by BrushingEngine.state.collectAsStateWithLifecycle()
        var showBrushing by rememberSaveable { mutableStateOf(false) }
        val heads = remember { runCatching { hu.fogmosas.core.ModelHeads.bundled() }.getOrNull() }

        fun startBrushing(armed: Boolean) {
            val d = store.data.value
            val p = d.activeProfile
            val s = d.settings
            activity.newAchievements.value = emptyList()
            BrushingEngine.start(activity, BrushingEngine.Config(
                heads = heads,
                autoDetect = s.isOn("auto_detect"),
                armed = armed,
                sonicConfig = if (s.isOn("calibration")) p.calibration.sonicConfig() else SonicConfig(),
                useSonic = p.electric,
                batterySaver = s.isOn("battery_saver"),
                targetS = p.goals.targetS,
                cues = s.isOn("quadrant_cues"),
                keepListeningWhenPlaced = s.isOn("keep_listening_when_placed", "android"),
            ))
            showBrushing = true
        }

        LaunchedEffect(activity.armRequest.value, data.onboarded) {
            if (activity.armRequest.value && data.onboarded) {
                activity.armRequest.value = false
                if (!engine.active) startBrushing(true)
            }
        }

        when {
            !data.onboarded -> OnboardingScreen(activity, store)
            showBrushing || engine.active || engine.result != null -> BrushingScreen(activity, store) {
                BrushingEngine.reset()
                showBrushing = false
            }
            else -> {
                var tab by rememberSaveable { mutableIntStateOf(0) }
                Scaffold(bottomBar = {
                    NavigationBar {
                        NavigationBarItem(tab == 0, { tab = 0 }, { Icon(Icons.Filled.Home, null) }, label = { Text("Főoldal") })
                        NavigationBarItem(tab == 1, { tab = 1 }, { Icon(Icons.Filled.Info, null) }, label = { Text("Statisztika") })
                        NavigationBarItem(tab == 2, { tab = 2 }, { Icon(Icons.Filled.Star, null) }, label = { Text("Kitüntetések") })
                        NavigationBarItem(tab == 3, { tab = 3 }, { Icon(Icons.Filled.Settings, null) }, label = { Text("Beállítások") })
                    }
                }) { pad ->
                    Box(Modifier.padding(pad)) {
                        when (tab) {
                            0 -> HomeScreen(store) { activity.requestPermissions(); startBrushing(false) }
                            1 -> StatsScreen(activity, store)
                            2 -> AchievementsScreen(store)
                            else -> SettingsScreen(activity, store)
                        }
                    }
                }
            }
        }
    }
}
