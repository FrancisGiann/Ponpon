package dev.giann.pocket_entry

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DailyReminderTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val zone = ZoneId.of("Asia/Manila")
    private val now = Instant.parse("2026-10-13T10:00:00Z") // 18:00 local
    private val alarm get() = Shadows.shadowOf(context.getSystemService(AlarmManager::class.java))
    private val notifications get() = context.getSystemService(NotificationManager::class.java)
    private val prefs get() = context.getSharedPreferences(DailyReminder.PREFS, Context.MODE_PRIVATE)
    @Before fun reset() {
        prefs.edit().clear().commit()
        Shadows.shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    @Test fun defaultIsOffAndPermissionDenialCannotEnable() {
        DailyReminder.reconcile(context, now, zone)
        assertEquals(false, DailyReminder.state(context)["enabled"])
        assertNull(DailyReminder.state(context)["minuteOfDay"])
        assertTrue(alarm.scheduledAlarms.isEmpty())
        Shadows.shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val state = DailyReminder.configure(context, true, 1200, now, zone)
        assertEquals(false, state["enabled"])
        assertEquals(false, state["permitted"])
        assertEquals(1200, state["minuteOfDay"])
        assertTrue(alarm.scheduledAlarms.isEmpty())
    }

    @Test fun oneInexactImmutableAlarmReplacesAndCancelsAcrossRestart() {
        DailyReminder.configure(context, true, 1200, now, zone)
        val first = alarm.scheduledAlarms.single()
        assertEquals(AlarmManager.RTC_WAKEUP, first.type)
        assertTrue(first.allowWhileIdle)
        assertNotEquals(0L, first.windowLengthMs)
        assertEquals(Instant.parse("2026-10-13T12:00:00Z").toEpochMilli(), first.triggerAtTime)
        assertTrue(first.operation!!.isImmutable)
        val intent = Shadows.shadowOf(first.operation!!).savedIntent
        assertEquals(ComponentName(context, DailyReminderReceiver::class.java), intent.component)
        assertEquals(DailyReminder.FIRE, intent.action)
        DailyReminder.configure(context, true, 1260, now, zone)
        DailyReminder.reconcile(context, now, zone) // Process-independent preference reload.
        assertEquals(1, alarm.scheduledAlarms.size)
        assertEquals(Instant.parse("2026-10-13T13:00:00Z").toEpochMilli(), alarm.scheduledAlarms.single().triggerAtTime)
        DailyReminder.configure(context, false, null, now, zone)
        assertTrue(alarm.scheduledAlarms.isEmpty())
        assertEquals(1260, DailyReminder.state(context)["minuteOfDay"])
        DailyReminder.reconcile(context, now, zone)
        assertTrue(alarm.scheduledAlarms.isEmpty())
    }

    @Test fun deliveryIsQuietOncePerLocalDayAndTapSelectsNoWallet() {
        DailyReminder.configure(context, true, 1200, now, zone)
        val due = prefs.getLong("due", 0)
        DailyReminder.deliver(context, due, Instant.ofEpochMilli(due + 60_000), zone)
        val notification = requireNotNull(Shadows.shadowOf(notifications).getNotification(DailyReminder.NOTIFICATION_ID))
        assertEquals("Anything to log today?", notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Add your expenses or income.", notification.extras.getString(Notification.EXTRA_TEXT))
        val channel = requireNotNull(notifications.getNotificationChannel(DailyReminder.CHANNEL))
        assertEquals(NotificationManager.IMPORTANCE_LOW, channel.importance)
        assertNull(channel.sound)
        assertFalse(channel.shouldVibrate())
        val tap = Shadows.shadowOf(notification.contentIntent).savedIntent
        assertEquals(ComponentName(context, MainActivity::class.java), tap.component)
        assertEquals(QuickEntryPolicy.Route(null, null), QuickEntryPolicy.parse(tap.action, tap.dataString))
        assertFalse(tap.hasExtra("wallet")); assertFalse(tap.hasExtra("amount"))
        assertTrue(notification.contentIntent.isImmutable)
        assertEquals("2026-10-13", prefs.getString("lastDay", null))
        val next = prefs.getLong("due", 0)
        assertEquals(Instant.parse("2026-10-14T12:00:00Z").toEpochMilli(), next)
        DailyReminder.deliver(context, due, Instant.ofEpochMilli(due + 120_000), zone)
        assertEquals(next, prefs.getLong("due", 0))
        assertEquals(1, Shadows.shadowOf(notifications).allNotifications.size)
        assertEquals(1, alarm.scheduledAlarms.size)
        DailyReminder.configure(context, false, null, now, zone)
        assertTrue(Shadows.shadowOf(notifications).allNotifications.isEmpty())
    }

    @Test fun appResumeKeepsTodaysPendingInexactWindowAndLateDaySkips() {
        DailyReminder.configure(context, true, 1200, now, zone)
        val due = prefs.getLong("due", 0)
        DailyReminder.reconcile(context, Instant.ofEpochMilli(due + 60_000), zone)
        assertEquals(due, prefs.getLong("due", 0))
        DailyReminder.deliver(context, due, Instant.parse("2026-10-13T17:00:00Z"), zone) // next local day
        assertTrue(Shadows.shadowOf(notifications).allNotifications.isEmpty())
        assertEquals(Instant.parse("2026-10-14T12:00:00Z").toEpochMilli(), prefs.getLong("due", 0))
    }

    @Test fun replacedOrDisabledBroadcastCannotPostAndRevocationCancels() {
        DailyReminder.configure(context, true, 1200, now, zone)
        val old = prefs.getLong("due", 0)
        DailyReminder.configure(context, true, 1260, now, zone)
        DailyReminder.deliver(context, old, Instant.ofEpochMilli(old), zone)
        assertTrue(Shadows.shadowOf(notifications).allNotifications.isEmpty())
        Shadows.shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        DailyReminder.reconcile(context, now, zone)
        assertTrue(alarm.scheduledAlarms.isEmpty())
        assertNull(DailyReminder.state(context)["nextAtMilliseconds"])
        assertEquals(false, DailyReminder.state(context)["permitted"])
        DailyReminder.configure(context, false, null, now, zone)
        DailyReminder.deliver(context, old, Instant.ofEpochMilli(old), zone)
        assertTrue(Shadows.shadowOf(notifications).allNotifications.isEmpty())
    }

    @Test fun daylightSavingGapsOverlapsAndClockReversalRemainCalendarBased() {
        val ny = ZoneId.of("America/New_York")
        assertEquals(Instant.parse("2026-03-08T07:30:00Z"), DailyReminderPolicy.next(Instant.parse("2026-03-08T05:00:00Z"), ny, 150, null))
        assertEquals(Instant.parse("2026-11-01T05:30:00Z"), DailyReminderPolicy.next(Instant.parse("2026-11-01T04:00:00Z"), ny, 90, null))
        assertEquals(Instant.parse("2026-11-02T06:30:00Z"), DailyReminderPolicy.next(Instant.parse("2026-11-01T06:15:00Z"), ny, 90, "2026-11-01"))
        assertEquals(Instant.parse("2026-10-14T12:00:00Z"), DailyReminderPolicy.next(now.minusSeconds(86400), zone, 1200, "2026-10-13"))
    }

    @Test fun timezoneTimeRebootAndPackageEventsRearmOnlyOptedIn() {
        val oldZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Manila"))
            DailyReminder.configure(context, true, 1200, Instant.now(), zone)
            val oldDue = prefs.getLong("due", 0)
            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            val receiver = DailyReminderReceiver()
            for (action in listOf(Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
                receiver.onReceive(context, Intent(action))
                assertEquals(1, alarm.scheduledAlarms.size)
                assertEquals(20, Instant.ofEpochMilli(prefs.getLong("due", 0)).atZone(ZoneId.systemDefault()).hour)
            }
            assertNotEquals(oldDue, prefs.getLong("due", 0))
            DailyReminder.configure(context, false, null)
            receiver.onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))
            assertTrue(alarm.scheduledAlarms.isEmpty())
        } finally { TimeZone.setDefault(oldZone) }
    }

    @Test fun manifestUsesNotificationAndBootPermissionsWithoutExactAlarmOrInternet() {
        val receiver = context.packageManager.getReceiverInfo(ComponentName(context, DailyReminderReceiver::class.java), 0)
        assertFalse(receiver.exported)
        val permissions = requireNotNull(context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions).toList()
        assertTrue(Manifest.permission.POST_NOTIFICATIONS in permissions)
        assertTrue(Manifest.permission.RECEIVE_BOOT_COMPLETED in permissions)
        assertFalse(Manifest.permission.SCHEDULE_EXACT_ALARM in permissions)
        assertFalse(Manifest.permission.USE_EXACT_ALARM in permissions)
        // Flutter debug tooling has INTERNET; only the release source manifest is authoritative here.
        val manifest = File(requireNotNull(System.getProperty("pocket.previewDir"))).parentFile.resolve("android/app/src/main/AndroidManifest.xml").readText()
        assertFalse(manifest.contains("android.permission.INTERNET"))
    }

    @Test @Config(sdk = [26]) fun android26NeedsNoRuntimeNotificationPermission() {
        Shadows.shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertEquals(true, DailyReminder.configure(context, true, 1200, now, zone)["enabled"])
        assertEquals(1, alarm.scheduledAlarms.size)
    }
}
