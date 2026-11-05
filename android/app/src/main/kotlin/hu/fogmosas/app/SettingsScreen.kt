package hu.fogmosas.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.Avatar
import hu.fogmosas.core.ClockTime
import hu.fogmosas.core.Formatting
import hu.fogmosas.core.OnboardingFlow
import hu.fogmosas.core.ReminderSettings
import hu.fogmosas.core.tapFlowFromMeasurement
import hu.fogmosas.shared.AppData
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.WearSync
import java.time.LocalDate
import java.util.UUID
import hu.fogmosas.core.tr

@Composable
fun SettingsScreen(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    var addingChild by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var tapStart by remember { mutableStateOf<Long?>(null) }
    var tapResult by remember { mutableStateOf<String?>(null) }
    var touring by remember { mutableStateOf(false) }

    if (touring) {
        TourScreen { touring = false }
        return
    }

    if (addingChild) {
        val flow = remember { OnboardingFlow().also { it.answer("family") } }
        QuestionFlow(flow, stopAtMore = true) {
            flow.profiles().drop(1).firstOrNull()?.let { child ->
                val taken = data.profiles.mapNotNull { it.avatar }.toSet()
                val avatar = if (child.avatar in taken) Avatar.all.firstOrNull { it.id !in taken }?.id else child.avatar
                store.update { it.copy(profiles = it.profiles + child.copy(id = "child-" + UUID.randomUUID().toString().take(8), avatar = avatar)) }
            }
            addingChild = false
        }
        return
    }

    fun rem(transform: (ReminderSettings) -> ReminderSettings) {
        store.update { it.copy(settings = it.settings.copy(reminders = transform(it.settings.reminders))) }
        ReminderScheduler.reschedule(activity)
    }

    if (data.settings.isOn("parent_lock", "android") && !activity.parentUnlocked.value) {
        LockScreen(tr("A beállítások szülői zárral védettek")) {
            DeviceAuth.authenticate(activity, tr("Szülői zár")) { ok -> if (ok) activity.parentUnlocked.value = true }
        }
        return
    }

    val p = data.activeProfile
    Column(Modifier.fillMaxSize().background(C.bg).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(tr("Beállítások"), fontSize = 28.sp, fontWeight = FontWeight.Bold)
        OutlinedButton(onClick = { touring = true }, modifier = Modifier.fillMaxWidth()) { Text(tr("✨ Mit tud az app? (bemutató)")) }

        Section("Nyelv / Language")
        InfoCard {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((code, label) in listOf("" to tr("Telefon nyelve"), "hu" to "Magyar", "en" to "English")) {
                    androidx.compose.material3.FilterChip(selected = data.settings.language == code, onClick = {
                        store.update { it.copy(settings = it.settings.copy(language = code)) }
                        ReminderScheduler.reschedule(activity)
                    }, label = { Text(label) })
                }
            }
        }

        Section(tr("Fogorvos"))
        ClinicLinkCard(activity, store)

        Section(tr("Adatok"))
        BackupCard(activity, store)
        PrivacyCard(activity, store)

        Section(tr("Profilok"))
        InfoCard {
            data.profiles.forEach { pr ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    AvatarCircle(pr.avatarEmoji, 36.dp, pr.id == p.id) { store.update { it.copy(activeProfileId = pr.id) } }
                    Spacer(Modifier.size(10.dp))
                    Text(pr.name + if (pr.child) (if (pr.canRead) tr(" · gyerek") else tr(" · gyerek, csak képek")) else "", Modifier.weight(1f))
                    if (pr.id != "me") TextButton(onClick = {
                        store.update { d -> d.copy(profiles = d.profiles.filter { it.id != pr.id }, activeProfileId = if (d.activeProfileId == pr.id) "me" else d.activeProfileId) }
                    }) { Text(tr("Törlés")) }
                }
            }
            OutlinedButton(onClick = { addingChild = true }) { Text(tr("Gyerek hozzáadása")) }
        }

        Section(tr("{0} beállításai", p.name))
        InfoCard {
            Stepper(tr("Naponta {0}×", p.goals.perDay), { updateGoals(store, activity, p.id, -1, 0.0) }, { updateGoals(store, activity, p.id, 1, 0.0) })
            Stepper(tr("Célidő: {0}", Formatting.clock(p.goals.targetS)), { updateGoals(store, activity, p.id, 0, -15.0) }, { updateGoals(store, activity, p.id, 0, 15.0) })
            p.goals.warnings.forEach { Text(it, color = C.warn, fontSize = 12.sp) }
            Text(tr("Fogkefe"), fontSize = 13.sp, color = C.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                hu.fogmosas.core.BrushTypes.all.forEach { k ->
                    androidx.compose.material3.FilterChip(selected = p.brushType == k.id, onClick = {
                        // A new brush type: the learned brush frequency no longer applies.
                        if (p.brushType != k.id) store.updateProfile(p.copy(brushType = k.id, calibration = hu.fogmosas.core.BrushCalibration()))
                    }, label = { Text(k.title.substringBefore(" ("), fontSize = 13.sp) })
                }
            }
            OutlinedButton(onClick = { store.updateProfile(p.copy(brushHeadInstalled = LocalDate.now().toString())) }) {
                Text(if (p.electric) tr("Új fogkefefejet tettem fel") else tr("Új fogkefét kezdtem"))
            }
            if (p.electric && data.settings.isOn("calibration")) Text(p.calibration.statusText, fontSize = 12.sp, color = C.muted)
            if (p.child) SwitchRow(tr("Tud olvasni"), "", p.canRead) { on -> store.updateProfile(p.copy(canRead = on)) }
            if (p.id == "me") HandSettings(store, p) {
                store.data.value.profile("me")?.let { WearSync.pushGoals(activity, it.goals, it.brushHand, it.watchWrist) }
            }
            ProfileCareSettings(store, p) {
                store.data.value.profile(p.id)?.let { if (it.id == "me") WearSync.pushGoals(activity, it.goals) }
                ReminderScheduler.reschedule(activity)
            }
        }

        Section(tr("Emlékeztetők"))
        val r = data.settings.reminders
        InfoCard {
            SwitchRow(tr("Reggel, ébredés után"), "", r.morningEnabled) { on -> rem { it.copy(morningEnabled = on) } }
            if (r.morningEnabled) TimeRow(tr("Ébredés"), r.wakeTime) { t -> rem { it.copy(wakeTime = t) } }
            SwitchRow(tr("Lefekvés előtt"), tr("{0} perccel előtte", r.bedtimeLeadMin), r.bedtimeEnabled) { on -> rem { it.copy(bedtimeEnabled = on) } }
            if (r.bedtimeEnabled) TimeRow(tr("Lefekvés"), r.bedtime) { t -> rem { it.copy(bedtime = t) } }
            SwitchRow(tr("Esti emlékeztető (pl. vacsora után)"), "", r.eveningEnabled) { on -> rem { it.copy(eveningEnabled = on) } }
            if (r.eveningEnabled) TimeRow(tr("Időpont"), r.eveningTime) { t -> rem { it.copy(eveningTime = t) } }
            SwitchRow(tr("Ismétlés, ha elmaradt"), tr("{0} perc múlva", r.followupAfterMin), r.followupEnabled) { on -> rem { it.copy(followupEnabled = on) } }
        }

        data.settings.groups("android").forEach { (group, features) ->
            Section(group)
            InfoCard {
                features.forEach { f ->
                    if (f.available) {
                        val lock = f.id == "app_lock" || f.id == "parent_lock"
                        val sub = if (lock && !DeviceAuth.available(activity)) tr("Ehhez képernyőzárat (ujjlenyomat, arc vagy PIN) kell beállítani a telefonon.") else f.description
                        SwitchRow(f.title, sub, data.settings.isOn(f.id)) { on ->
                            fun apply() {
                                store.update { it.copy(settings = it.settings.with(f.id, on)) }
                                if (f.id == "notifications" || f.id == "dentist_reminders") ReminderScheduler.reschedule(activity)
                                if (lock) { activity.unlocked.value = true; activity.parentUnlocked.value = true }
                            }
                            if (lock) DeviceAuth.authenticate(activity, f.title) { ok -> if (ok) apply() } else apply()
                        }
                    } else {
                        SwitchRow(f.title, "hamarosan", false, enabled = false) {}
                    }
                }
            }
        }

        if (data.settings.isOn("test_recording", "android")) InfoCard {
            Text(tr("Tesztfelvétel"), fontWeight = FontWeight.Bold)
            Text(tr("Minden felvételt és észrevételt megtartok (az észrevételt gépelés közben mentem). Egyben, ZIP-ként elküldheted Google Drive-ra vagy e-mailben."), fontSize = 13.sp, color = C.muted)
            TestRecordingShareButton()
            TestRecordingsSendAllButton()
        }

        Section(tr("Víz"))
        InfoCard {
            SwitchRow(tr("USA mértékegységek (gallon, \$)"), "", data.settings.locale == "us") { on ->
                store.update { it.copy(settings = it.settings.copy(locale = if (on) "us" else "hu")) }
            }
            Text(tr("Csap mérése: tegyél a csap alá egy 1 literes palackot, nyisd meg úgy, ahogy fogmosáskor szoktad, nyomd meg az Indítást, és amikor megtelt, a Stopot."), fontSize = 13.sp, color = C.muted)
            val st = tapStart
            if (st == null) Button(onClick = { tapStart = System.currentTimeMillis(); tapResult = null }) { Text(tr("Indítás")) }
            else Button(onClick = {
                val secs = (System.currentTimeMillis() - st) / 1000.0
                tapStart = null
                tapResult = try {
                    val f = tapFlowFromMeasurement(1.0, secs)
                    store.update { it.copy(settings = it.settings.copy(tapFlowLPerMin = f)) }
                    tr("%.1f l/perc – elmentve.").format(f)
                } catch (e: Exception) { tr("Ez nem tűnik reálisnak, próbáld újra.") }
            }) { Text(tr("Stop")) }
            tapResult?.let { Text(it) }
            data.settings.tapFlowLPerMin?.let { Text(tr("A te csapod: %.1f l/perc").format(it), fontSize = 12.sp, color = C.muted) }
        }

        Section(tr("Adatvédelem"))
        InfoCard {
            Text(tr("A hang csak ezen a készüléken, a memóriában dolgozódik fel. Hangfelvétel nem készül, és semmi nem kerül szerverre. A webes megtekintés csak akkor küld adatot, ha te olvasod be a QR-kódot, és akkor is titkosítva."), fontSize = 13.sp, color = C.muted)
            TextButton(onClick = { confirmDelete = true }) { Text(tr("Összes adat törlése"), color = C.danger) }
        }
    }

    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text(tr("Biztosan törölsz minden adatot?")) },
        confirmButton = { TextButton(onClick = { store.update { AppData() }; confirmDelete = false }) { Text(tr("Törlés"), color = C.danger) } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(tr("Mégse")) } },
    )
}

private fun updateGoals(store: AppStore, activity: MainActivity, id: String, dPerDay: Int, dTarget: Double) {
    val p = store.data.value.profile(id) ?: return
    val g = p.goals.copy(perDay = p.goals.perDay + dPerDay, targetS = p.goals.targetS + dTarget).clamped()
    store.updateProfile(p.copy(goals = g))
    if (id == "me") WearSync.pushGoals(activity, g)
    ReminderScheduler.reschedule(activity)
}

@Composable
private fun Section(title: String) = Text(title.uppercase(), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = C.muted)

@Composable
fun SwitchRow(title: String, sub: String, on: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title)
            if (sub.isNotEmpty()) Text(sub, fontSize = 12.sp, color = C.muted)
        }
        Switch(checked = on, onCheckedChange = onChange, enabled = enabled)
    }
}

@Composable
private fun TimeRow(label: String, t: ClockTime, onChange: (ClockTime) -> Unit) {
    Stepper("$label: ${t.text}", { onChange(t.plusMinutes(-15)) }, { onChange(t.plusMinutes(15)) })
}
