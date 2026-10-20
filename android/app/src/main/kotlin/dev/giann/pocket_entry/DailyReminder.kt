package dev.giann.pocket_entry

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** One local calendar occurrence at a time; never a fixed 24-hour repeat. */
object DailyReminderPolicy {
    fun next(now: Instant, zone: ZoneId, minute: Int, lastDay: String?): Instant {
        require(minute in 0..1439)
        val localNow = now.atZone(zone)
        val last = try { lastDay?.let(LocalDate::parse) } catch (_: Exception) { null }
        var day = localNow.toLocalDate()
        if (last != null && !day.isAfter(last)) day = last.plusDays(1)
        var candidate = day.atTime(LocalTime.of(minute / 60, minute % 60)).atZone(zone).toInstant()
        if (!candidate.isAfter(now)) {
            day = day.plusDays(1)
            candidate = day.atTime(LocalTime.of(minute / 60, minute % 60)).atZone(zone).toInstant()
        }
        return candidate
    }
}

/** Device-only opt-in. It deliberately lives outside the ledger and JSON backups. */
object DailyReminder {
    const val PREFS = "ponpon_daily_reminder"
    const val FIRE = "dev.giann.pocket_entry.DAILY_REMINDER"
    const val CHANNEL = "daily_log_reminder"
    const val NOTIFICATION_ID = 5101
    private const val REQUEST = 5102
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)

    fun permitted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = manager(context)
        return manager.areNotificationsEnabled() && manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun state(context: Context): Map<String, Any?> {
        val p = prefs(context)
        return mapOf("enabled" to p.getBoolean("enabled", false),
            "minuteOfDay" to p.getInt("minute", -1).takeIf { it in 0..1439 },
            "permitted" to permitted(context),
            "nextAtMilliseconds" to p.getLong("due", 0L).takeIf { it > 0L })
    }

    private fun alarmIntent(context: Context, due: Long) = PendingIntent.getBroadcast(context, REQUEST,
        Intent(context, DailyReminderReceiver::class.java).setAction(FIRE).putExtra("due", due),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun cancel(context: Context) {
        val pending = PendingIntent.getBroadcast(context, REQUEST,
            Intent(context, DailyReminderReceiver::class.java).setAction(FIRE),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (pending != null) { alarms(context).cancel(pending); pending.cancel() }
        prefs(context).edit().remove("due").commit()
        manager(context).cancel(NOTIFICATION_ID)
    }

    private fun createChannel(context: Context) {
        val channel = NotificationChannel(CHANNEL, "Daily log reminder", NotificationManager.IMPORTANCE_LOW)
        channel.description = "A quiet daily invitation to record expenses or income."
        channel.setSound(null, null)
        channel.enableVibration(false)
        channel.setShowBadge(false)
        manager(context).createNotificationChannel(channel)
    }

    @Synchronized fun configure(context: Context, enabled: Boolean, minute: Int?, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Map<String, Any?> {
        require(!enabled || minute != null && minute in 0..1439)
        require(minute == null || minute in 0..1439)
        if (enabled) createChannel(context)
        val allowed = !enabled || permitted(context)
        val edit = prefs(context).edit().putBoolean("enabled", enabled && allowed)
        if (minute != null) edit.putInt("minute", minute)
        check(edit.commit()) { "Reminder settings could not be saved" }
        if (!enabled || !allowed) cancel(context) else reconcile(context, now, zone)
        return state(context)
    }

    @Synchronized fun reconcile(context: Context, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Map<String, Any?> {
        val p = prefs(context)
        val minute = p.getInt("minute", -1)
        if (!p.getBoolean("enabled", false) || minute !in 0..1439 || !permitted(context)) {
            cancel(context)
            return state(context)
        }
        createChannel(context)
        val today = now.atZone(zone).toLocalDate()
        val last = p.getString("lastDay", null)
        val todayTarget = today.atTime(LocalTime.of(minute / 60, minute % 60)).atZone(zone).toInstant().toEpochMilli()
        val pendingDue = p.getLong("due", 0L)
        // Opening the app inside an inexact delivery window must not skip today's reminder.
        val due = if (pendingDue == todayTarget && p.getString("zone", null) == zone.id && (last == null || today.toString() > last)) pendingDue
            else DailyReminderPolicy.next(now, zone, minute, last).toEpochMilli()
        try {
            check(p.edit().putLong("due", due).putString("zone", zone.id).commit()) { "Reminder schedule could not be saved" }
            // Inexact, including during idle. No exact-alarm permission or loud alarm UI.
            alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, alarmIntent(context, due))
        } catch (e: RuntimeException) {
            cancel(context)
            throw e
        }
        return state(context)
    }

    fun entryIntent(context: Context): PendingIntent = PendingIntent.getActivity(context, NOTIFICATION_ID,
        Intent(context, MainActivity::class.java).setAction(QuickEntryPolicy.ACTION)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    @Synchronized fun deliver(context: Context, expectedDue: Long, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
        val p = prefs(context)
        val due = p.getLong("due", 0L)
        if (!p.getBoolean("enabled", false) || !permitted(context)) { cancel(context); return }
        if (expectedDue <= 0L || expectedDue != due) return // Cancelled or replaced occurrence.
        val today = now.atZone(zone).toLocalDate()
        val dueDay = Instant.ofEpochMilli(due).atZone(zone).toLocalDate()
        val last = p.getString("lastDay", null)
        if (now.toEpochMilli() < due || today != dueDay || last != null && today.toString() <= last) {
            reconcile(context, now, zone)
            return
        }
        // Commit before posting, so restarts and repeated broadcasts cannot post twice.
        if (!p.edit().putString("lastDay", today.toString()).commit()) return
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ponpon_wallet_monochrome)
            .setContentTitle("Anything to log today?")
            .setContentText("Add your expenses or income.")
            .setContentIntent(entryIntent(context))
            .setAutoCancel(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setShowWhen(false).build()
        try { manager(context).notify(NOTIFICATION_ID, notification) } catch (_: SecurityException) { }
        // Replace the single occurrence without removing today's notification.
        reconcile(context, now, zone)
    }
}

class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action == DailyReminder.FIRE) DailyReminder.deliver(context, intent.getLongExtra("due", 0L))
            else if (intent.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) DailyReminder.reconcile(context)
        } catch (_: RuntimeException) { /* App settings show a retry state; a receiver never crashes the ledger. */ }
    }
}
