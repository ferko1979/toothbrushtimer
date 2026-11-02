package hu.fogmosas.shared

import android.content.Context
import hu.fogmosas.core.AppSettings
import hu.fogmosas.core.BrushRecord
import hu.fogmosas.core.Coach
import hu.fogmosas.core.ExtraRecord
import hu.fogmosas.core.Profile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDate

/** Everything the app stores, on the device only (JSON in the app's private files). */
@Serializable
data class AppData(
    val onboarded: Boolean = false,
    val settings: AppSettings = AppSettings(),
    val profiles: List<Profile> = listOf(Profile("me", "Én")),
    val activeProfileId: String = "me",
    val records: List<BrushRecord> = emptyList(),
    val extras: List<ExtraRecord> = emptyList(),
) {
    val activeProfile get() = profiles.firstOrNull { it.id == activeProfileId } ?: profiles.first()
    fun profile(id: String) = profiles.firstOrNull { it.id == id }
    fun records(profileId: String) = records.filter { it.profileId == profileId }
    fun extras(profileId: String) = extras.filter { it.profileId == profileId }
}

class AppStore private constructor(context: Context) {
    companion object {
        @Volatile private var instance: AppStore? = null
        fun get(context: Context): AppStore = instance ?: synchronized(this) {
            instance ?: AppStore(context.applicationContext).also { instance = it }
        }
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }

    private val file = File(context.filesDir, "toothbrushtimer.json")
    private val _data = MutableStateFlow(load())
    val data: StateFlow<AppData> = _data
    val coach = Coach()

    private fun load(): AppData = try {
        if (file.exists()) json.decodeFromString(AppData.serializer(), file.readText()) else AppData()
    } catch (e: Exception) {
        AppData()
    }

    @Synchronized
    fun update(transform: (AppData) -> AppData) {
        val next = transform(_data.value)
        _data.value = next
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(json.encodeToString(AppData.serializer(), next))
        tmp.renameTo(file)
    }

    fun updateProfile(p: Profile) = update { d -> d.copy(profiles = d.profiles.map { if (it.id == p.id) p else it }) }

    /** Saves a brushing; returns the ids of newly earned achievements. */
    fun addRecord(record: BrushRecord): List<String> {
        val d = _data.value
        if (d.records.any { it.id == record.id }) return emptyList()
        val p = d.profile(record.profileId) ?: d.activeProfile
        val today = LocalDate.now()
        val before = coach.earnedAchievements(d.records(p.id), p.goals, today)
        update { data ->
            var profiles = data.profiles
            if (data.settings.isOn("calibration") && p.electric) {
                profiles = profiles.map { if (it.id == p.id) it.copy(calibration = it.calibration.add(record.brushF0)) else it }
            }
            data.copy(records = data.records + record, profiles = profiles)
        }
        val after = coach.earnedAchievements(_data.value.records(p.id), p.goals, today)
        return (after - before).sorted()
    }

    fun addExtra(kind: String) = update { d ->
        d.copy(extras = d.extras + ExtraRecord(profileId = d.activeProfileId, dateMs = System.currentTimeMillis(), kind = kind))
    }
}
