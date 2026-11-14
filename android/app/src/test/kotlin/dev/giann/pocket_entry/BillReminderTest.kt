package dev.giann.pocket_entry

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
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
import org.json.JSONObject

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BillReminderTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val zone = ZoneId.of("Asia/Manila")
    private val morning = Instant.parse("2026-10-19T00:00:00Z") // 08:00 local
    private val prefs get() = context.getSharedPreferences(BillReminder.PREFS, Context.MODE_PRIVATE)
    private val alarms get() = Shadows.shadowOf(context.getSystemService(AlarmManager::class.java))
    private val manager get() = context.getSystemService(NotificationManager::class.java)
    private fun item(
        date: String = "2026-10-19",
        frequency: String = "once",
        paid: List<String> = emptyList(),
        paymentCount: Int? = null,
    ): Map<String, Any> = buildMap {
        put("id", "synthetic")
        put("startDate", date)
        put("frequency", frequency)
        put("paidDates", paid)
        if (paymentCount != null) put("paymentCount", paymentCount)
    }
    @Before fun reset() {
        prefs.edit().clear().commit()
        Shadows.shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    @Test fun payloadValidationRejectsForgedDatesDuplicatesAndUnboundedLists() {
        assertTrue(BillReminder.valid(listOf(item())))
        assertFalse(BillReminder.valid(listOf(item("2026-02-30"))))
        assertFalse(BillReminder.valid(listOf(item("2201-01-01"))))
        assertFalse(BillReminder.valid(listOf(item(), item())))
        assertFalse(BillReminder.valid(listOf(item(frequency = "unknown"))))
        assertFalse(BillReminder.valid(listOf(item(frequency = "weekly", paymentCount = 0))))
        assertFalse(BillReminder.valid(listOf(item(frequency = "once", paymentCount = 2))))
        assertFalse(BillReminder.valid(listOf(item(
            date = "2026-10-31",
            frequency = "monthly",
            paid = listOf("2027-01-31"),
            paymentCount = 3,
        ))))
        assertFalse(BillReminder.valid((0..100).map { item() + mapOf("id" to "bill$it") }))
    }

    @Test fun finiteInstallmentRemindersIncludeTheLastDateAndThenStop() {
        val schedule = item(frequency = "weekly", paymentCount = 2)
        BillReminder.configure(context, listOf(schedule), morning, zone)
        val first = prefs.getLong("due", 0)
        assertEquals(Instant.parse("2026-10-19T01:00:00Z").toEpochMilli(), first)

        BillReminder.deliver(context, first, Instant.ofEpochMilli(first + 60000), zone)
        val final = prefs.getLong("due", 0)
        assertEquals(Instant.parse("2026-10-26T01:00:00Z").toEpochMilli(), final)
        BillReminder.deliver(context, final, Instant.ofEpochMilli(final + 60000), zone)

        assertFalse(prefs.contains("due"))
        assertTrue(alarms.scheduledAlarms.isEmpty())
    }

    @Test fun addingNullCountToALegacyInfiniteRuleKeepsItsReminderIdentity() {
        BillReminder.configure(context, listOf(item(frequency = "weekly")), morning, zone)
        val before = JSONObject(prefs.getString("definitions", "{}")).getString("synthetic")
        val withNullCount = item(frequency = "weekly") +
            mapOf("paymentCount" to org.json.JSONObject.NULL)
        BillReminder.configure(context, listOf(withNullCount), morning, zone)
        val after = JSONObject(prefs.getString("definitions", "{}")).getString("synthetic")
        assertEquals("2026-10-19|weekly", before)
        assertEquals(before, after)
    }

    @Test fun defaultAndDeniedPermissionScheduleNothing() {
        BillReminder.reconcile(context, morning, zone)
        assertTrue(alarms.scheduledAlarms.isEmpty())
        Shadows.shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        BillReminder.configure(context, listOf(item()), morning, zone)
        assertTrue(alarms.scheduledAlarms.isEmpty())
        assertFalse(prefs.contains("due"))
        assertTrue(Shadows.shadowOf(manager).allNotifications.isEmpty())
    }

    @Test fun oneInexactAlarmUsesLocalDueDateAndSurvivesPreferenceReload() {
        BillReminder.configure(context, listOf(item()), morning, zone)
        val alarm = alarms.scheduledAlarms.single()
        assertEquals(Instant.parse("2026-10-19T01:00:00Z").toEpochMilli(), alarm.triggerAtTime)
        assertEquals(AlarmManager.RTC_WAKEUP, alarm.type)
        assertTrue(alarm.allowWhileIdle)
        assertNotEquals(0L, alarm.windowLengthMs)
        assertTrue(alarm.operation!!.isImmutable)
        BillReminder.reconcile(context, morning, ZoneId.of("America/New_York"))
        assertEquals(1, alarms.scheduledAlarms.size)
        assertEquals(Instant.parse("2026-10-19T13:00:00Z").toEpochMilli(), alarms.scheduledAlarms.single().triggerAtTime)
    }

    @Test fun deliveryIsPrivateQuietIdempotentAndOnlyOpensBills() {
        BillReminder.configure(context, listOf(item()), morning, zone)
        val due = prefs.getLong("due", 0)
        BillReminder.deliver(context, due, Instant.ofEpochMilli(due + 60000), zone)
        val notice = requireNotNull(Shadows.shadowOf(manager).getNotification(BillReminder.NOTIFICATION_ID))
        assertEquals(Notification.VISIBILITY_PRIVATE, notice.visibility)
        val channel = requireNotNull(manager.getNotificationChannel(BillReminder.CHANNEL))
        assertEquals(NotificationManager.IMPORTANCE_LOW, channel.importance)
        assertNull(channel.sound); assertFalse(channel.shouldVibrate())
        val intent = Shadows.shadowOf(notice.contentIntent).savedIntent
        assertEquals(BillReminder.OPEN, intent.action)
        assertEquals(BillReminder.URI, intent.dataString)
        assertFalse(intent.hasExtra("wallet")); assertFalse(intent.hasExtra("amount"))
        assertNull(QuickEntryPolicy.parse(intent.action, intent.dataString))
        assertTrue(notice.contentIntent.isImmutable)
        assertEquals("2026-10-19", JSONObject(prefs.getString("lastDates", "{}")).getString("synthetic"))
        BillReminder.deliver(context, due, Instant.ofEpochMilli(due + 120000), zone)
        assertEquals(1, Shadows.shadowOf(manager).allNotifications.size)
        BillReminder.reconcile(context, Instant.ofEpochMilli(due + 180000), zone)
        assertTrue(alarms.scheduledAlarms.isEmpty())
    }

    @Test fun paidOrPausedBillCancelsPendingReminderAndStaleBroadcastCannotPost() {
        BillReminder.configure(context, listOf(item()), morning, zone)
        val old = prefs.getLong("due", 0)
        BillReminder.configure(context, listOf(item("2026-11-19")), morning, zone)
        val next = prefs.getLong("due", 0)
        assertTrue(next > old)
        BillReminder.deliver(context, old, Instant.ofEpochMilli(old + 60000), zone)
        assertTrue(Shadows.shadowOf(manager).allNotifications.isEmpty())
        assertEquals(next, prefs.getLong("due", 0))
        BillReminder.configure(context, emptyList(), morning, zone)
        assertTrue(alarms.scheduledAlarms.isEmpty())
    }

    @Test fun monthlyRemindersContinueWhileAnOlderOccurrenceIsUnpaid() {
        BillReminder.configure(context, listOf(item("2026-10-31", "monthly")), morning, zone)
        var due = prefs.getLong("due", 0)
        assertEquals(Instant.parse("2026-10-31T01:00:00Z").toEpochMilli(), due)
        BillReminder.deliver(context, due, Instant.ofEpochMilli(due + 60000), zone)
        due = prefs.getLong("due", 0)
        assertEquals(Instant.parse("2026-11-30T01:00:00Z").toEpochMilli(), due)
        BillReminder.deliver(context, due, Instant.ofEpochMilli(due + 60000), zone)
        assertEquals(Instant.parse("2026-12-31T01:00:00Z").toEpochMilli(), prefs.getLong("due", 0))
        assertEquals("2026-11-30", JSONObject(prefs.getString("lastDates", "{}")).getString("synthetic"))
    }

    @Test fun earlyPaymentSkipsItsReminderWithoutBlockingTheFollowingRecurrence() {
        BillReminder.configure(context, listOf(item("2026-10-31", "monthly", listOf("2026-10-31"))), morning, zone)
        assertEquals(Instant.parse("2026-11-30T01:00:00Z").toEpochMilli(), prefs.getLong("due", 0))
        assertFalse(BillReminder.valid(listOf(item("2026-10-31", "monthly", listOf("2026-11-29")))))
    }

    @Test fun editingRecurrenceAfterDeliveryResetsOnlyThatScheduleHistory() {
        BillReminder.configure(context, listOf(item(), item() + mapOf("id" to "synthetic_kept")), morning, zone)
        val oldDue = prefs.getLong("due", 0)
        val after = Instant.ofEpochMilli(oldDue + 60000)
        BillReminder.deliver(context, oldDue, after, zone)
        BillReminder.configure(context, listOf(item("2026-10-18"), item() + mapOf("id" to "synthetic_kept")), after, zone)
        val editedDue = prefs.getLong("due", 0)
        assertEquals(after.toEpochMilli() + 1000, editedDue)
        BillReminder.deliver(context, editedDue, Instant.ofEpochMilli(editedDue + 1000), zone)
        val history = JSONObject(prefs.getString("lastDates", "{}"))
        assertEquals("2026-10-18", history.getString("synthetic"))
        assertEquals("2026-10-19", history.getString("synthetic_kept"))
    }

    @Test fun unchangedSyncAndPauseResumeDoNotReplayDeliveredOccurrence() {
        BillReminder.configure(context, listOf(item()), morning, zone)
        val due = prefs.getLong("due", 0)
        val after = Instant.ofEpochMilli(due + 60000)
        BillReminder.deliver(context, due, after, zone)
        BillReminder.configure(context, listOf(item()), after, zone)
        assertTrue(alarms.scheduledAlarms.isEmpty())
        BillReminder.configure(context, emptyList(), after, zone)
        BillReminder.configure(context, listOf(item()), after, zone)
        assertTrue(alarms.scheduledAlarms.isEmpty())
        assertEquals("2026-10-19", JSONObject(prefs.getString("lastDates", "{}")).getString("synthetic"))
    }

    @Test fun billRemindersDoNotReplaceTheExistingDailyLogReminder() {
        DailyReminder.configure(context, true, 1200, morning, zone)
        BillReminder.configure(context, listOf(item()), morning, zone)
        assertEquals(2, alarms.scheduledAlarms.size)
        BillReminder.configure(context, emptyList(), morning, zone)
        assertEquals(1, alarms.scheduledAlarms.size)
        assertEquals(true, DailyReminder.state(context)["enabled"])
    }
}
