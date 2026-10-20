# Optional daily local reminder — Ponpon 0.2.4

Daily reminder is off by default, with no saved time on a fresh install. Settings → Daily reminder lets the user choose a time without activating it, or turn it on. Turning it on opens the time wheel; Cancel changes nothing. Done confirms the user’s time before Android 13+ notification permission is requested. Denial keeps the reminder off, preserves the chosen time, explains recovery inline, and offers Android notification settings. Later system/channel revocation cancels pending delivery and shows blocked status; the user’s prior opt-in remains visible until switched off.

The quiet notification reads **Anything to log today?** / **Add your expenses or income.** It uses a low-importance silent channel without vibration, sound, full-screen alarm UI, or exact-alarm special access. Notification preferences are device-local Android private SharedPreferences, outside schema-4 ledger files and exported backups. Restoring or importing financial records cannot opt a device in. No network, accounts, tracking, or added package dependencies are used.

## Scheduling and entry behavior

One immutable explicit PendingIntent and one notification ID are used. `AlarmManager.setAndAllowWhileIdle(RTC_WAKEUP, …)` is an inexact alarm. Each occurrence is calculated from the selected local hour/minute and current zone; it is not a fixed 24-hour repeat. Spring daylight-saving gaps shift to the next valid local time; autumn overlaps choose the first occurrence. A persisted local-day high-water mark prevents repeated or backward-clock delivery. A persisted due value rejects cancelled/replaced broadcasts. The next occurrence replaces the one pending alarm. Opening the app during today’s pending delivery window does not skip it.

The private receiver rearms on boot, package replacement, clock changes, and timezone changes. The app also reconciles on resume and when Settings reloads. Calendar days are recomputed after delivery, so midnight and daylight-saving transitions retain local wall-clock intent. A delayed alarm reaching another local day is skipped and rearmed rather than posting an obsolete prompt. Switching off cancels the alarm, PendingIntent, and any existing reminder notification while retaining the user’s chosen time.

Tapping the notification opens existing Quick add with no category, amount, or wallet supplied. The existing dirty-draft protection remains; named wallet save buttons require an explicit choice. Notification delivery reads no ledger and writes no entries.

## Android limits and device verification

Android inexact delivery can arrive later than the chosen time; Doze, battery saver, manufacturer restrictions, channel settings, and force-stop can delay or suppress it. After a force-stop, open Ponpon to rearm. No exact minute or overnight physical-device reliability is promised. Android permission denial and channel disablement are respected; the app never silently changes system notification settings.

Automated evidence: `daily_reminder_test.dart` covers configuration bridges, ledger isolation, explicit time confirmation/cancel, permission denial/settings recovery, choosing a time while off, light/dark/enlarged type, explicit-wallet quick entry, and scheduling-failure reload/resume recovery. `DailyReminderTest.kt` covers default/denied state, one inexact immutable alarm, replacement/cancellation/persistence, quiet payload and route, one delivery per local day, pending-window preservation, stale-day handling, permission revocation, DST and backward-clock policy, reboot/clock/timezone/update events, private receiver and permissions, and API26 behavior. Synthetic previews are `reminder-settings-light-024.png`, `reminder-settings-dark-024.png`, and `reminder-schedule-recovery-024.png`.

No reminders were enabled on a live user device. Physical notification drawer appearance, actual overnight/reboot delivery, POCO power management, TalkBack and hardware haptics were not checked. Prior emulator failures are described in `023-emulator-status.md`.

Platform references: [Android inexact alarms](https://developer.android.com/develop/background-work/services/alarms), [notification permission](https://developer.android.com/develop/ui/views/notifications/notification-permission), and [notification channels](https://developer.android.com/develop/ui/views/notifications/channels).
