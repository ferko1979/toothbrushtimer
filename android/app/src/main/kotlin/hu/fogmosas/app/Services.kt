package hu.fogmosas.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import hu.fogmosas.core.ReminderPlanner
import hu.fogmosas.core.dentistStatus
import hu.fogmosas.core.nextDentistReminder
import java.time.LocalDate
import java.time.LocalTime
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.WearSync
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale

/** Rolling 7-day plan of reminder alarms (same planner as iOS). */
object ReminderScheduler {
    private const val CHANNEL = "reminders"
    private const val MAX = 40

    fun reschedule(ctx: Context) {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return
        for (i in 0 until MAX) {
            PendingIntent.getBroadcast(ctx, 1000 + i, Intent(ctx, ReminderReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)?.let { am.cancel(it) }
        }
        PendingIntent.getBroadcast(ctx, DENTIST_CODE, Intent(ctx, ReminderReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)?.let { am.cancel(it) }
        val d = AppStore.get(ctx).data.value
        if (d.onboarded) scheduleDentist(ctx, am, d)
        if (!d.onboarded || !d.settings.isOn("notifications")) return
        val me = d.profile("me") ?: d.activeProfile
        val zone = ZoneId.systemDefault()
        val plan = ReminderPlanner.plan(LocalDateTime.now(), d.records(me.id), me.goals, d.settings.reminders, zone, 7)
        plan.take(MAX).forEachIndexed { i, r ->
            val intent = Intent(ctx, ReminderReceiver::class.java).putExtra("text", r.text).putExtra("key", r.key)
            val pi = PendingIntent.getBroadcast(ctx, 1000 + i, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val at = r.fireAt.atZone(zone).toInstant().toEpochMilli()
            am.setWindow(AlarmManager.RTC_WAKEUP, at, 60_000L, pi)
        }
    }

    private const val DENTIST_CODE = 1100

    /** One alarm at 10:00 on the day the next checkup / cleaning of the main profile is due. */
    private fun scheduleDentist(ctx: Context, am: AlarmManager, d: hu.fogmosas.shared.AppData) {
        if (!d.settings.isOn("dentist_reminders")) return
        val me = d.profile("me") ?: return
        val today = LocalDate.now()
        val day = nextDentistReminder(me.lastCheckup?.let(LocalDate::parse), me.lastCleaning?.let(LocalDate::parse), today) ?: return
        val st = dentistStatus(me.lastCheckup?.let(LocalDate::parse), me.lastCleaning?.let(LocalDate::parse), day)
        val text = (st.message ?: "Esedékes a fogorvosi kontroll.") + " Foglalj időpontot! 🦷"
        val intent = Intent(ctx, ReminderReceiver::class.java).putExtra("text", text).putExtra("arm", false)
        val pi = PendingIntent.getBroadcast(ctx, DENTIST_CODE, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val at = day.atTime(LocalTime.of(10, 0)).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        am.setWindow(AlarmManager.RTC_WAKEUP, at, 30 * 60_000L, pi)
    }

    fun show(ctx: Context, text: String, arm: Boolean = true) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Emlékeztetők", NotificationManager.IMPORTANCE_DEFAULT))
        val open = Intent(ctx, MainActivity::class.java).putExtra(MainActivity.EXTRA_ARM, arm)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(ctx, if (arm) 7 else 8, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(hu.fogmosas.shared.R.drawable.ic_stat_brush)
            .setContentTitle("🪥 Fogmosás")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        runCatching { nm.notify(text.hashCode(), n) }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        ReminderScheduler.show(ctx, intent.getStringExtra("text") ?: "Ideje fogat mosni! 🪥", intent.getBooleanExtra("arm", true))
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) ReminderScheduler.reschedule(ctx)
    }
}

/** Receives brushings measured on the Wear OS watch. */
class PhoneListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != WearSync.PATH_RECORD) return
        val rec = WearSync.decodeRecord(event.data) ?: return
        AppStore.get(this).addRecord(rec)
        ReminderScheduler.reschedule(this)
    }
}

/** Reads feedback aloud for children who cannot read yet. */
class Speaker(ctx: Context) : TextToSpeech.OnInitListener {
    private val tts = TextToSpeech(ctx.applicationContext, this)
    private var ready = false
    private var pending: String? = null

    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        if (ready) {
            tts.language = Locale("hu", "HU")
            pending?.let { say(it) }
        }
    }

    fun say(text: String) {
        val clean = text.filter { Character.getType(it) != Character.SURROGATE.toInt() && Character.getType(it) != Character.OTHER_SYMBOL.toInt() }
        if (!ready) { pending = clean; return }
        tts.speak(clean, TextToSpeech.QUEUE_FLUSH, null, "fb")
    }

    fun shutdown() = tts.shutdown()
}
