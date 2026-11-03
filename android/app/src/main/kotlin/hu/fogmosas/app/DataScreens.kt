package hu.fogmosas.app

import android.content.Context
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.BackupCrypto
import hu.fogmosas.core.BackupPayload
import hu.fogmosas.core.decodeBackup
import hu.fogmosas.core.encodeBackup
import hu.fogmosas.core.photoBase64
import hu.fogmosas.core.photoBytes
import hu.fogmosas.core.tr
import hu.fogmosas.shared.AppStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate

// Health data notice and consent, deleting everything, password-protected backup and family transfer.

object PrivacyText {
    val summary get() = tr("Az app egészségügyi adatokat kezel (fogmosás, tünetek, panaszok, fotók). Ezek csak ezen a telefonon tárolódnak, titkosított tárhelyen. Hangfelvétel nem készül (kivéve, ha a teszt módot bekapcsolod).")
    val points get() = listOf(
        tr("A rendelődnek csak akkor megy adat, ha te küldöd el (üzenet, e-mail, jelentés)."),
        tr("A webes megtekintés végponttól végpontig titkosított; a szerver nem tudja elolvasni."),
        tr("A fotókat csak te látod, amíg el nem küldöd őket."),
        tr("Bármikor letöltheted (titkosított mentés) vagy véglegesen törölheted az összes adatodat."),
        tr("A tanácsok általános tájékoztatások, nem helyettesítik az orvosi vizsgálatot."),
    )
}

/** Health data notice; the app can be used once the user agrees (new and existing users alike). */
@Composable
fun ConsentScreen(store: AppStore) {
    var ok by remember { mutableStateOf(false) }
    FormPage {
        Text(tr("🔒 Adataid védelme"), fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Text(PrivacyText.summary)
        PrivacyText.points.forEach { Text("• $it", fontSize = 15.sp, color = C.muted) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(ok, { ok = it })
            Text(tr("Elolvastam, és hozzájárulok, hogy az app ezeket az adatokat a telefonomon kezelje."))
        }
        Button(onClick = { store.update { it.copy(consentMs = System.currentTimeMillis()) } }, enabled = ok,
            modifier = Modifier.fillMaxWidth().height(52.dp)) { Text(tr("Tovább")) }
    }
}

private fun wipeFiles(ctx: Context) {
    listOf(File(ctx.filesDir, "photos"), File(ctx.cacheDir, "recordings"), File(ctx.cacheDir, "reports"),
        File(ctx.filesDir, "recordings"), ClinicFiles.logoFile(ctx)).forEach { it.deleteRecursively() }
}

/** Settings: privacy notice, consent date and "Minden adatom törlése". */
@Composable
fun PrivacyCard(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    var open by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(0) }
    InfoCard {
        Text(tr("🔒 Adatvédelem"), fontWeight = FontWeight.Bold)
        Text(PrivacyText.summary, fontSize = 13.sp, color = C.muted)
        if (open) PrivacyText.points.forEach { Text("• $it", fontSize = 13.sp, color = C.muted) }
        TextButton(onClick = { open = !open }) { Text(if (open) tr("Kevesebb") else tr("Adatkezelési tájékoztató")) }
        data.consentMs?.let { Text(tr("Hozzájárultál: {0}", hu.fogmosas.core.I18n.date(java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneId.systemDefault()).toLocalDate())), fontSize = 12.sp, color = C.muted) }
        OutlinedButton(onClick = { confirm = 1 }, colors = ButtonDefaults.outlinedButtonColors(contentColor = C.danger)) { Text(tr("Minden adatom törlése")) }
    }
    if (confirm > 0) AlertDialog(onDismissRequest = { confirm = 0 },
        title = { Text(if (confirm == 1) tr("Minden adatod törlődik") else tr("Biztosan? Ez nem vonható vissza.")) },
        text = { Text(tr("Fogmosások, napló, panaszok, fotók, emlékeztetők és beállítások – minden. Előtte érdemes titkosított mentést készíteni.")) },
        confirmButton = {
            TextButton(onClick = {
                if (confirm == 1) confirm = 2 else {
                    wipeFiles(ctx)
                    store.wipe()
                    ReminderScheduler.reschedule(ctx)
                    confirm = 0
                    Toast.makeText(ctx, tr("Minden adat törölve."), Toast.LENGTH_LONG).show()
                }
            }) { Text(if (confirm == 1) tr("Tovább") else tr("Végleges törlés"), color = C.danger) }
        },
        dismissButton = { TextButton(onClick = { confirm = 0 }) { Text(tr("Mégse")) } })
}

/** Password entry (twice when creating a backup). */
@Composable
private fun PasswordDialog(title: String, confirmTwice: Boolean, error: String?, onDone: (String) -> Unit, onCancel: () -> Unit) {
    var p1 by remember { mutableStateOf("") }
    var p2 by remember { mutableStateOf("") }
    val problem = if (confirmTwice) BackupCrypto.passwordProblem(p1) ?: (if (p1 != p2) tr("A két jelszó nem egyezik.") else null) else null
    AlertDialog(onDismissRequest = onCancel, title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (confirmTwice) Text(tr("Ezzel a jelszóval tudod majd visszaállítani. Ha elfelejted, a mentés nem nyitható meg."), fontSize = 13.sp, color = C.muted)
                OutlinedTextField(p1, { p1 = it }, label = { Text(tr("Jelszó")) }, singleLine = true, visualTransformation = PasswordVisualTransformation())
                if (confirmTwice) OutlinedTextField(p2, { p2 = it }, label = { Text(tr("Jelszó még egyszer")) }, singleLine = true, visualTransformation = PasswordVisualTransformation())
                (error ?: problem?.takeIf { p1.isNotEmpty() })?.let { Text(it, color = C.danger, fontSize = 13.sp) }
            }
        },
        confirmButton = { TextButton(enabled = p1.isNotEmpty() && problem == null, onClick = { onDone(p1) }) { Text(tr("OK")) } },
        dismissButton = { TextButton(onClick = onCancel) { Text(tr("Mégse")) } })
}

private fun photosOf(ctx: Context, names: Collection<String>): Map<String, String> =
    names.mapNotNull { n -> ClinicFiles.photo(ctx, n).takeIf { it.exists() }?.let { n to photoBase64(it.readBytes()) } }.toMap()

private fun writePhotos(ctx: Context, photos: Map<String, String>) {
    photos.forEach { (name, b64) ->
        // Only plain file names from a backup, never paths.
        if (name.matches(Regex("^[A-Za-z0-9._-]{1,80}$"))) runCatching { ClinicFiles.photo(ctx, name).writeBytes(photoBytes(b64)) }
    }
}

/** Settings: password-protected backup / restore, and handing one profile to another phone. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BackupCard(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    // What the next password / file step is for.
    var step by remember { mutableStateOf<String?>(null) }
    var password by remember { mutableStateOf("") }
    var exportProfileId by remember { mutableStateOf<String?>(null) }
    var pickedFile by remember { mutableStateOf<ByteArray?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var pendingRestore by remember { mutableStateOf<BackupPayload?>(null) }
    var pendingProfile by remember { mutableStateOf<BackupPayload?>(null) }

    fun toast(t: String) = Toast.makeText(ctx, t, Toast.LENGTH_LONG).show()

    val create = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri: Uri? ->
        val pw = password
        password = ""
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    val d = store.data.value
                    val payload = exportProfileId?.let { pid ->
                        BackupPayload(kind = "profile", platform = "android", createdMs = System.currentTimeMillis(), data = store.exportProfile(pid),
                            photos = photosOf(ctx, d.symptoms.filter { it.profileId == pid }.flatMap { it.photos }))
                    } ?: BackupPayload(platform = "android", createdMs = System.currentTimeMillis(), data = store.exportJson(),
                        photos = photosOf(ctx, d.symptoms.flatMap { it.photos }))
                    ctx.contentResolver.openOutputStream(uri)!!.use { it.write(encodeBackup(payload, pw)) }
                }.isSuccess
            }
            toast(if (ok) tr("Mentve ✔︎") else tr("A mentés nem sikerült."))
        }
    }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bytes = runCatching { ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes() } }.getOrNull()
        if (bytes == null || !BackupCrypto.isBackup(bytes)) { toast(tr("Ez nem DentHub-Brush mentés.")); return@rememberLauncherForActivityResult }
        pickedFile = bytes
        error = null
        step = if (step == "restore-pick") "restore-password" else "profile-password"
    }

    InfoCard {
        Text(tr("💾 Mentés és átvitel"), fontWeight = FontWeight.Bold)
        Text(tr("Jelszóval titkosított fájl: új telefonra vagy biztonsági másolatnak. A fotókat is tartalmazza."), fontSize = 13.sp, color = C.muted)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { exportProfileId = null; error = null; step = "backup-password" }) { Text(tr("Mentés fájlba")) }
            OutlinedButton(onClick = { step = "restore-pick"; pick.launch(arrayOf("*/*")) }) { Text(tr("Visszaállítás")) }
        }
        Text(tr("Családi átvitel: egy profil (pl. a gyereké) átadása egy másik családtag telefonjára."), fontSize = 13.sp, color = C.muted)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            data.profiles.forEach { p ->
                OutlinedButton(onClick = { exportProfileId = p.id; error = null; step = "backup-password" }) { Text(tr("{0} átadása", p.name)) }
            }
            OutlinedButton(onClick = { step = "profile-pick"; pick.launch(arrayOf("*/*")) }) { Text(tr("Profil fogadása")) }
        }
    }

    when (step) {
        "backup-password" -> PasswordDialog(tr("Jelszó a mentéshez"), true, null, { pw ->
            password = pw
            step = null
            val who = exportProfileId?.let { id -> data.profile(id)?.name?.let { "-" + it.filter { c -> c.isLetterOrDigit() } } } ?: ""
            create.launch("denthub-brush$who-${LocalDate.now()}.dhb")
        }, { step = null })
        "restore-password", "profile-password" -> PasswordDialog(tr("A mentés jelszava"), false, error, { pw ->
            val file = pickedFile ?: return@PasswordDialog
            val payload = runCatching { decodeBackup(file, pw) }.getOrNull()
            when {
                payload == null -> error = tr("Hibás jelszó, vagy sérült a fájl.")
                payload.platform != "android" -> { error = tr("Ez a mentés iPhone-ról készült; Androidon még nem nyitható meg."); }
                step == "restore-password" && payload.kind != "full" -> error = tr("Ez egy profil-átadás; a „Profil fogadása” gombbal nyisd meg.")
                step == "profile-password" && payload.kind != "profile" -> error = tr("Ez teljes mentés; a „Visszaállítás” gombbal nyisd meg.")
                step == "restore-password" -> { pendingRestore = payload; step = null }
                else -> { pendingProfile = payload; step = null }
            }
        }, { step = null })
        else -> Unit
    }

    pendingRestore?.let { p ->
        AlertDialog(onDismissRequest = { pendingRestore = null }, title = { Text(tr("Visszaállítod?")) },
            text = { Text(tr("A mentés ({0}) felülírja a jelenlegi adatokat ezen a telefonon.", hu.fogmosas.core.I18n.date(java.time.Instant.ofEpochMilli(p.createdMs).atZone(java.time.ZoneId.systemDefault()).toLocalDate()))) },
            confirmButton = {
                TextButton(onClick = {
                    val ok = runCatching { store.importJson(p.data); writePhotos(ctx, p.photos) }.isSuccess
                    pendingRestore = null
                    ReminderScheduler.reschedule(ctx)
                    toast(if (ok) tr("Visszaállítva ✔︎") else tr("A visszaállítás nem sikerült."))
                }) { Text(tr("Visszaállítás")) }
            },
            dismissButton = { TextButton(onClick = { pendingRestore = null }) { Text(tr("Mégse")) } })
    }
    pendingProfile?.let { p ->
        AlertDialog(onDismissRequest = { pendingProfile = null }, title = { Text(tr("Hova kerüljön a profil?")) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(tr("Új profilként, vagy egy meglévőhöz fűzve (a duplikátumokat kihagyjuk)."), fontSize = 13.sp, color = C.muted)
                    OutlinedButton(onClick = {
                        runCatching { store.importProfile(p.data, null); writePhotos(ctx, p.photos) }
                        pendingProfile = null
                        ReminderScheduler.reschedule(ctx)
                        toast(tr("Profil hozzáadva ✔︎"))
                    }, Modifier.fillMaxWidth()) { Text(tr("Új profilként")) }
                    data.profiles.forEach { target ->
                        OutlinedButton(onClick = {
                            runCatching { store.importProfile(p.data, target.id); writePhotos(ctx, p.photos) }
                            pendingProfile = null
                            ReminderScheduler.reschedule(ctx)
                            toast(tr("Hozzáfűzve: {0} ✔︎", target.name))
                        }, Modifier.fillMaxWidth()) { Text(tr("Hozzáfűzés: {0}", target.name)) }
                    }
                }
            },
            confirmButton = {}, dismissButton = { TextButton(onClick = { pendingProfile = null }) { Text(tr("Mégse")) } })
    }
}
