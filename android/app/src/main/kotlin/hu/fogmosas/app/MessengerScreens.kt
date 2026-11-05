package hu.fogmosas.app

import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.Appointment
import hu.fogmosas.core.ClinicMessage
import hu.fogmosas.core.Messaging
import hu.fogmosas.core.Recipients
import hu.fogmosas.core.VisitReasons
import hu.fogmosas.core.tr
import hu.fogmosas.shared.AppStore
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId

// Messenger with the linked clinic, appointment offers / confirmations, calendar and reminders.
// Delivery through DentHub needs its server (docs/DENTHUB-API.md): until then app messages wait
// ("queued"), e-mails go out right away, and every e-mail is also kept here as a message.

/** Device calendar (Google Calendar, Samsung …): an event with the appointment, edited and saved by the user. */
object CalendarAdd {
    fun open(ctx: Context, a: Appointment) {
        val (begin, end) = Messaging.epochRange(a, ZoneId.systemDefault()) ?: return
        val i = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
            .putExtra(CalendarContract.Events.TITLE, Messaging.title(a))
            .putExtra(CalendarContract.Events.DESCRIPTION, listOfNotNull(a.clinicName, a.doctor, a.note.ifBlank { null }).joinToString("\n"))
            .putExtra(CalendarContract.Events.EVENT_LOCATION, a.address ?: a.clinicName ?: "")
            .putExtra(CalendarContract.Events.AVAILABILITY, CalendarContract.Events.AVAILABILITY_BUSY)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { ctx.startActivity(i) }.onFailure { Toast.makeText(ctx, tr("Nem találtam naptár alkalmazást."), Toast.LENGTH_LONG).show() }
    }
}

/** Sends a message to the clinic: in the app (when both sides allow it) and/or by e-mail; always kept here. */
fun sendClinicMessage(ctx: Context, store: AppStore, text: String, to: String, alsoEmail: Boolean,
                      appointmentId: String? = null, photos: List<String> = emptyList()): ClinicMessage {
    val d = store.data.value
    val p = d.activeProfile
    val via = Messaging.channels(d.clinic, d.settings.isOn("app_messaging", "android"), alsoEmail)
    val m = ClinicMessage(profileId = p.id, dateMs = System.currentTimeMillis(), text = text, photos = photos, to = to,
        via = via, status = Messaging.statusAfterSend(via), appointmentId = appointmentId)
    store.addMessage(m)
    if ("email" in via) {
        val subject = tr("DentHub-Brush: üzenet – {0}", p.name) + if (to == "admin") " (" + Recipients.title(to) + ")" else ""
        ClinicSend.email(ctx, d.clinic, subject, text + "\n\n" + tr("(A DentHub-Brush appból küldve.)"), photos)
    }
    return m
}

/** Home / top bar: 💬 with the number of unread clinic messages; shown once there is a conversation or a linked clinic. */
@Composable
fun MessagesButton(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val unread = Messaging.unread(data.messages, p.id)
    Box {
        TextButton(onClick = { activity.overlay.value = "messages" }) { Text("💬 " + tr("Üzenetek"), fontSize = 15.sp) }
        if (unread > 0) Box(Modifier.align(Alignment.TopEnd).size(20.dp).clip(CircleShape).background(C.danger), contentAlignment = Alignment.Center) {
            Text("$unread", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
    }
}

/** Home: the next appointment, with calendar and the offer's answer. */
@Composable
fun UpcomingAppointmentCard(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val a = Messaging.upcoming(data.appointments, p.id, LocalDateTime.now()).firstOrNull() ?: return
    AppointmentCard(store, a, compact = true) { activity.overlay.value = "messages" }
}

@Composable
fun AppointmentCard(store: AppStore, a: Appointment, compact: Boolean = false, onOpen: (() -> Unit)? = null) {
    val ctx = LocalContext.current
    InfoCard {
        Text(when (a.status) {
            "offered" -> tr("📅 Időpont-ajánlat")
            "requested" -> tr("📅 Időpontkérés elküldve")
            "cancelled" -> tr("📅 Lemondott időpont")
            else -> tr("📅 Fogorvosi időpont")
        }, fontWeight = FontWeight.Bold, color = if (a.status == "offered") C.warn else C.brand)
        Text(Messaging.when_(a), fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        Text(listOfNotNull(VisitReasons.title(a.reason), a.doctor, a.clinicName).joinToString(" · "), fontSize = 13.sp, color = C.muted)
        if (a.note.isNotBlank() && !compact) Text(a.note, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (a.status == "offered") {
                Button(onClick = {
                    val ok = a.copy(status = "confirmed", calendarAdded = true)
                    store.putAppointment(ok)
                    sendClinicMessage(ctx, store, Messaging.acceptText(ok), "admin", alsoEmail = false, appointmentId = ok.id)
                    ReminderScheduler.reschedule(ctx)
                    CalendarAdd.open(ctx, ok)
                }) { Text(tr("Elfogadom")) }
                OutlinedButton(onClick = {
                    store.putAppointment(a.copy(status = "cancelled"))
                    sendClinicMessage(ctx, store, Messaging.declineText(a), "admin", alsoEmail = false, appointmentId = a.id)
                }) { Text(tr("Másikat kérek")) }
            } else if (a.status == "confirmed") {
                OutlinedButton(onClick = { CalendarAdd.open(ctx, a); store.putAppointment(a.copy(calendarAdded = true)) }) {
                    Text(if (a.calendarAdded) tr("📅 Újra a naptárba") else tr("📅 Naptárba"))
                }
                if (!compact) TextButton(onClick = {
                    store.putAppointment(a.copy(status = "cancelled"))
                    sendClinicMessage(ctx, store, tr("❌ Le kell mondanom az időpontot: {0}", Messaging.when_(a)), "admin", alsoEmail = true, appointmentId = a.id)
                    ReminderScheduler.reschedule(ctx)
                }) { Text(tr("Lemondás")) }
            }
            if (onOpen != null) TextButton(onClick = onOpen) { Text(tr("Üzenetek ›")) }
        }
        if (a.status == "confirmed" && store.data.value.settings.isOn("appointment_reminders", "android"))
            Text(tr("Emlékeztető előtte egy nappal és két órával."), fontSize = 12.sp, color = C.muted)
    }
}

/** The conversation with the clinic: bubbles, delivery state, appointment cards, composer. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MessengerScreen(activity: MainActivity, store: AppStore, onClose: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val clinic = data.clinic
    val ctx = LocalContext.current
    var to by remember { mutableStateOf("doctor") }
    var text by remember { mutableStateOf("") }
    var alsoEmail by remember { mutableStateOf(false) }
    var gotAppointment by remember { mutableStateOf(false) }
    val thread = Messaging.thread(data.messages, p.id)
    val list = rememberLazyListState()
    LaunchedEffect(thread.size) {
        store.markRead(p.id)
        if (thread.isNotEmpty()) list.scrollToItem(thread.size)
    }
    val appToApp = clinic?.messaging == true && data.settings.isOn("app_messaging", "android")

    Column(Modifier.fillMaxSize().background(C.bg).imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(start = 8.dp)) {
                Text(clinic?.name ?: tr("Üzenetek"), fontWeight = FontWeight.Bold, fontSize = 17.sp)
                Text(when {
                    clinic == null -> tr("Nincs összekötött rendelő")
                    appToApp -> tr("DentHub üzenetküldő · e-mail")
                    clinic.email != null -> tr("E-mailben megy, itt is megmarad")
                    else -> tr("A rendelő még nem fogad üzenetet")
                }, fontSize = 12.sp, color = C.muted)
            }
            TextButton(onClick = onClose) { Text("✕", fontSize = 20.sp) }
        }
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp)) {
            item {
                if (clinic == null) InfoCard {
                    Text(tr("Még nincs összekötött rendelő"), fontWeight = FontWeight.Bold)
                    Text(tr("A rendelőd a DentHubon ad egy összekötő QR-kódot vagy linket (Beállítások › Rendelőm). Utána itt írhatsz az orvosnak vagy a recepciónak, és itt jönnek az időpont-ajánlatok. A telefonon kapott időpontot már most felveheted: „Időpontot kaptam”."), fontSize = 13.sp, color = C.muted)
                } else if (thread.isEmpty()) InfoCard {
                    Text(tr("Írj a rendelődnek"), fontWeight = FontWeight.Bold)
                    Text(tr("Kérdés, panasz vagy időpontkérés – az orvosnak vagy a recepciónak. A sürgős panaszt a „Panaszom van” kérdéseivel küldd, fotóval."), fontSize = 13.sp, color = C.muted)
                }
            }
            items(thread, key = { it.id }) { m -> Bubble(m, data.appointments.firstOrNull { it.id == m.appointmentId }, store) }
        }
        // Appointments that are still ahead (offers first).
        Messaging.upcoming(data.appointments, p.id, LocalDateTime.now()).firstOrNull()?.let { a ->
            Box(Modifier.padding(horizontal = 12.dp)) { AppointmentCard(store, a) }
        }
        Column(Modifier.fillMaxWidth().background(Color.White).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Recipients.all.forEach { (id, label) -> FilterChip(selected = to == id, onClick = { to = id }, label = { Text(label, fontSize = 13.sp) }) }
                FilterChip(selected = false, onClick = { activity.overlay.value = "visit" }, label = { Text(tr("📅 Időpont kérése"), fontSize = 13.sp) })
                FilterChip(selected = false, onClick = { gotAppointment = true }, label = { Text(tr("Időpontot kaptam"), fontSize = 13.sp) })
                FilterChip(selected = false, onClick = { activity.overlay.value = "symptom" }, label = { Text(tr("🩺 Panasz"), fontSize = 13.sp) })
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(text, { text = it }, Modifier.weight(1f), placeholder = { Text(tr("Üzenet…")) }, maxLines = 5)
                Button(onClick = {
                    if (clinic?.email == null && !appToApp) { Toast.makeText(ctx, tr("A rendelőnek nincs e-mail címe, és még nem fogad üzenetet az appban."), Toast.LENGTH_LONG).show(); return@Button }
                    sendClinicMessage(ctx, store, text.trim(), to, alsoEmail)
                    text = ""
                }, enabled = text.isNotBlank() && clinic != null) { Text(tr("Küldés")) }
            }
            if (appToApp && clinic?.email != null) Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(alsoEmail, { alsoEmail = it })
                Text(tr("E-mailben is"), Modifier.padding(start = 8.dp), fontSize = 13.sp)
            }
        }
    }
    if (gotAppointment) AppointmentEntryDialog(store, p.id, clinic?.name, clinic?.address) { gotAppointment = false }
}

@Composable
private fun Bubble(m: ClinicMessage, appointment: Appointment?, store: AppStore) {
    val mine = m.fromPatient
    Column(Modifier.fillMaxWidth(), horizontalAlignment = if (mine) Alignment.End else Alignment.Start) {
        Column(Modifier.widthIn(max = 300.dp).clip(RoundedCornerShape(16.dp)).background(if (mine) C.brand else Color.White).padding(10.dp)) {
            if (!mine || m.to == "admin") Text(Recipients.title(m.to), fontSize = 11.sp, color = if (mine) Color.White.copy(alpha = 0.8f) else C.muted)
            Text(m.text, color = if (mine) Color.White else Color(0xFF1B2B34), fontSize = 15.sp)
            if (m.photos.isNotEmpty()) Text(tr("📷 {0} fotó", m.photos.size), fontSize = 12.sp, color = if (mine) Color.White else C.muted)
        }
        val time = java.text.SimpleDateFormat("MM.dd. HH:mm", java.util.Locale.getDefault()).format(java.util.Date(m.dateMs))
        Text(if (mine) "$time · ${Messaging.statusText(m)}" else time, fontSize = 11.sp, color = C.muted, textAlign = if (mine) TextAlign.End else TextAlign.Start)
        if (!mine && appointment != null && appointment.status == "offered") AppointmentCard(store, appointment)
    }
}

/** "Időpontot kaptam": the patient enters an appointment they got by phone or at the desk. */
@Composable
fun AppointmentEntryDialog(store: AppStore, profileId: String, clinicName: String?, address: String?, onDone: () -> Unit) {
    val ctx = LocalContext.current
    var day by remember { mutableStateOf(LocalDate.now().plusDays(1).toString()) }
    var time by remember { mutableStateOf("10:00") }
    var reason by remember { mutableStateOf("checkup") }
    var doctor by remember { mutableStateOf("") }
    val start = runCatching { LocalDateTime.of(LocalDate.parse(day.trim()), LocalTime.parse(time.trim())) }.getOrNull()
    AlertDialog(onDismissRequest = onDone, title = { Text(tr("Időpontot kaptam")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(day, { day = it }, label = { Text(tr("Nap (ÉÉÉÉ-HH-NN)")) }, singleLine = true)
                OutlinedTextField(time, { time = it }, label = { Text(tr("Időpont (ÓÓ:PP)")) }, singleLine = true)
                OutlinedTextField(doctor, { doctor = it }, label = { Text(tr("Orvos (nem kötelező)")) }, singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("checkup", "cleaning", "pain").forEach { id -> FilterChip(reason == id, { reason = id }, { Text(VisitReasons.title(id), fontSize = 12.sp) }) }
                }
                if (start == null) Text(tr("Add meg a napot és az időt."), color = C.danger, fontSize = 12.sp)
            }
        },
        confirmButton = {
            TextButton(enabled = start != null, onClick = {
                val a = Appointment(profileId = profileId, start = Messaging.format(start!!), reason = reason, clinicName = clinicName,
                    address = address, doctor = doctor.trim().ifEmpty { null }, status = "confirmed", calendarAdded = true)
                store.putAppointment(a)
                ReminderScheduler.reschedule(ctx)
                CalendarAdd.open(ctx, a)
                onDone()
            }) { Text(tr("Mentés és naptárba")) }
        },
        dismissButton = { TextButton(onClick = onDone) { Text(tr("Mégse")) } })
}

/** A clinic's appointment offer from a QR code or link (denthub://appt?d=…): kept as a clinic message with the offer. */
fun receiveAppointmentOffer(store: AppStore, a: Appointment) {
    if (store.data.value.appointments.any { it.id == a.id }) return
    store.putAppointment(a)
    store.addMessage(ClinicMessage(profileId = a.profileId, dateMs = System.currentTimeMillis(),
        text = tr("Időpontot ajánlunk: {0}", Messaging.when_(a)) + (a.doctor?.let { " – $it" } ?: ""),
        fromPatient = false, status = "received", to = "admin", appointmentId = a.id))
}
