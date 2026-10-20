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
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Reminders only: no amounts, wallet choices, or financial writes live here. */
object BillReminder {
    const val PREFS = "ponpon_bill_reminders"
    const val FIRE = "dev.giann.pocket_entry.BILL_REMINDER"
    const val OPEN = "dev.giann.pocket_entry.OPEN_BILLS"
    const val URI = "pocketentry://bills"
    const val CHANNEL = "bill_reminders"
    const val NOTIFICATION_ID = 5201
    private const val ALARM_REQUEST = 5203
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)

    private data class Rule(val id: String, val anchor: LocalDate, val frequency: String, val paid: Set<LocalDate>) {
        fun occurrence(index: Int): LocalDate? {
            if (index < 0 || index > 20000 || frequency == "once" && index > 0) return null
            val date = when (frequency) {
                "once" -> anchor
                "weekly" -> anchor.plusWeeks(index.toLong())
                "monthly" -> YearMonth.from(anchor).plusMonths(index.toLong()).let { it.atDay(minOf(anchor.dayOfMonth, it.lengthOfMonth())) }
                "yearly" -> YearMonth.of(anchor.year + index, anchor.month).let { it.atDay(minOf(anchor.dayOfMonth, it.lengthOfMonth())) }
                else -> error("Invalid bill recurrence")
            }
            return date.takeIf { it.year <= 2200 }
        }
        fun indexOnOrBefore(day: LocalDate): Int {
            if (day.isBefore(anchor)) return -1
            var index = when (frequency) {
                "once" -> 0
                "weekly" -> (ChronoUnit.DAYS.between(anchor, day) / 7).toInt()
                "monthly" -> ChronoUnit.MONTHS.between(YearMonth.from(anchor), YearMonth.from(day)).toInt()
                "yearly" -> day.year - anchor.year
                else -> error("Invalid bill recurrence")
            }
            if (occurrence(index)?.isAfter(day) == true) index--
            return index
        }
    }
    private data class Candidate(val billId: String, val date: LocalDate) {
        val key get() = "bill_${billId}_${date.toString().replace("-", "")}"
    }

    private fun decode(row: JSONObject): Rule {
        val id = row.getString("id"); require(id.matches(Regex("[a-zA-Z0-9_-]{1,32}")))
        val anchor = LocalDate.parse(row.getString("startDate")); require(anchor.year in 1900..2200)
        val frequency = row.getString("frequency"); require(frequency in listOf("once", "weekly", "monthly", "yearly"))
        val raw = row.getJSONArray("paidDates"); require(raw.length() <= 20000)
        val dates = (0 until raw.length()).map { LocalDate.parse(raw.getString(it)) }
        require(dates.distinct().size == dates.size && dates.all { it.year in 1900..2200 })
        val rule = Rule(id, anchor, frequency, dates.toSet())
        require(dates.all { rule.occurrence(rule.indexOnOrBefore(it)) == it })
        return rule
    }
    fun valid(items: List<Map<String, Any>>): Boolean = try {
        require(items.size <= 100)
        val rules = items.map { decode(JSONObject(it)) }
        rules.map { it.id }.distinct().size == rules.size && rules.sumOf { it.paid.size } <= 20000
    } catch (_: Exception) { false }

    fun permitted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        return manager(context).areNotificationsEnabled() &&
            manager(context).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }
    private fun channel(context: Context) {
        val channel = NotificationChannel(CHANNEL, "Bill reminders", NotificationManager.IMPORTANCE_LOW)
        channel.description = "A quiet reminder to review upcoming bills. Payments are always recorded manually."
        channel.setSound(null, null); channel.enableVibration(false); channel.setShowBadge(false)
        manager(context).createNotificationChannel(channel)
    }
    private fun pending(context: Context, due: Long) = PendingIntent.getBroadcast(context, ALARM_REQUEST,
        Intent(context, BillReminderReceiver::class.java).setAction(FIRE).putExtra("due", due),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancel(context: Context) {
        val intent = PendingIntent.getBroadcast(context, ALARM_REQUEST,
            Intent(context, BillReminderReceiver::class.java).setAction(FIRE),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (intent != null) { alarms(context).cancel(intent); intent.cancel() }
        check(prefs(context).edit().remove("due").commit())
    }
    private fun candidates(context: Context, now: Instant, zone: ZoneId): List<Candidate> {
        val json = JSONArray(prefs(context).getString("items", "[]")); require(json.length() <= 100)
        val latest = JSONObject(prefs(context).getString("lastDates", "{}"))
        val today = now.atZone(zone).toLocalDate()
        val result = mutableListOf<Candidate>()
        for (i in 0 until json.length()) {
            val rule = decode(json.getJSONObject(i))
            val last = latest.optString(rule.id).takeIf { it.isNotEmpty() }?.let(LocalDate::parse)
            fun add(date: LocalDate?) {
                if (date != null && date !in rule.paid && (last == null || date.isAfter(last))) result.add(Candidate(rule.id, date))
            }
            // Catch an outstanding bill once, without replaying every old period.
            for (index in 0..rule.paid.size) {
                val date = rule.occurrence(index) ?: break
                if (date !in rule.paid) { add(date); break }
            }
            add(rule.occurrence(rule.indexOnOrBefore(today)))
            val lower = if (last != null && last.isAfter(today)) last else today
            val first = maxOf(0, rule.indexOnOrBefore(lower) + 1)
            for (index in first..first + rule.paid.size) {
                val date = rule.occurrence(index) ?: break
                if (date !in rule.paid) { add(date); break }
            }
        }
        return result.distinctBy { it.key }
    }
    private fun atNine(date: LocalDate, zone: ZoneId) = date.atTime(LocalTime.of(9, 0)).atZone(zone).toInstant()

    @Synchronized fun configure(context: Context, items: List<Map<String, Any>>,
        now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
        require(valid(items)) { "Invalid bill reminders" }
        val json = JSONArray(); items.forEach { json.put(JSONObject(it)) }
        val definitions = JSONObject(prefs(context).getString("definitions", "{}"))
        val latest = JSONObject(prefs(context).getString("lastDates", "{}"))
        for (item in items) {
            val id = item["id"] as String
            val definition = "${item["startDate"]}|${item["frequency"]}"
            if (definitions.has(id) && definitions.getString(id) != definition) latest.remove(id)
            definitions.put(id, definition)
        }
        // Keep definitions while paused/off, so toggling never replays a reminder.
        check(prefs(context).edit().putString("items", json.toString())
            .putString("definitions", definitions.toString()).putString("lastDates", latest.toString()).commit()) {
            "Bill reminders could not be saved"
        }
        manager(context).cancel(NOTIFICATION_ID)
        reconcile(context, now, zone)
    }
    @Synchronized fun reconcile(context: Context, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
        val candidates = candidates(context, now, zone)
        if (candidates.isEmpty() || !permitted(context)) { cancel(context); return }
        channel(context)
        val first = candidates.minOf { atNine(it.date, zone).toEpochMilli() }
        val due = maxOf(first, now.toEpochMilli() + 1000L)
        check(prefs(context).edit().putLong("due", due).commit())
        alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, pending(context, due))
    }
    @Synchronized fun deliver(context: Context, expectedDue: Long,
        now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
        if (expectedDue <= 0L || prefs(context).getLong("due", 0L) != expectedDue) return
        if (!permitted(context) || now.toEpochMilli() < expectedDue) { reconcile(context, now, zone); return }
        val due = candidates(context, now, zone).filter { !atNine(it.date, zone).isAfter(now) }
        if (due.isEmpty()) { reconcile(context, now, zone); return }
        val latest = JSONObject(prefs(context).getString("lastDates", "{}"))
        for (candidate in due) {
            val old = latest.optString(candidate.billId)
            if (candidate.date.toString() > old) latest.put(candidate.billId, candidate.date.toString())
        }
        check(prefs(context).edit().putString("lastDates", latest.toString()).commit())
        channel(context)
        val open = PendingIntent.getActivity(context, 5202,
            Intent(context, MainActivity::class.java).setAction(OPEN).setData(Uri.parse(URI))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val count = due.map { it.billId }.distinct().size
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ponpon_wallet_monochrome)
            .setContentTitle(if (count == 1) "A bill to check" else "$count bills to check")
            .setContentText("Review due dates and record payments when ready.")
            .setContentIntent(open).setAutoCancel(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_REMINDER).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setShowWhen(false).build()
        reconcile(context, now, zone)
        try { manager(context).notify(NOTIFICATION_ID, notification) } catch (_: SecurityException) { }
    }
}

class BillReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action == BillReminder.FIRE) BillReminder.deliver(context, intent.getLongExtra("due", 0L))
            else if (intent.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                    Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) BillReminder.reconcile(context)
        } catch (_: RuntimeException) { /* Retry on resume without changing financial records. */ }
    }
}
