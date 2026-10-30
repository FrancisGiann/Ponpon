# Ponpon · Budget & Expenses

**Latest: [Ponpon 0.2.16](https://github.com/FrancisGiann/Ponpon/releases/tag/v0.2.16)** · ARM64 Android APK · version code 2018.

Ponpon is a personal Android budget tracker named after the owner’s dog, built for fast manual wallet recording. Cash and GCash are included; you can add your own named wallets. The whole interface uses a custom Cupertino-inspired design, offline Inter typography, compact navigation, rounded sheets, optional haptics and reduced motion.

## Watch the ad

**Before you walk away** · 21.5 seconds

<a href="https://raw.githubusercontent.com/FrancisGiann/Ponpon/main/docs/media/ads/Ponpon-before-you-walk-away.mp4">
  <img src="docs/media/ads/Ponpon-before-you-walk-away-cover.jpg" alt="Ponpon — Before you walk away. Open the 21.5-second ad (MP4)." width="280">
</a>

[Watch or download the ad (MP4)](https://raw.githubusercontent.com/FrancisGiann/Ponpon/main/docs/media/ads/Ponpon-before-you-walk-away.mp4) · [View file on GitHub](docs/media/ads/Ponpon-before-you-walk-away.mp4) · [Caption and credits](docs/media/ads/Ponpon-caption-and-credits.txt)

An illustrated purchase scene uses Ponpon 0.2.2 screens with synthetic records and the verified wallet icon. Cash and GCash are manually recorded wallets. This is staged product footage.

Music: [Happy Beats & Business Moves Vol. 12](https://ende.app/en/song/12881-happy-beats-business-moves-vol-12) by Sascha Ende, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Excerpted, faded, gain adjusted, normalized and mixed with sound accents. Full credits are linked above.

## First use

Install [Ponpon-0.2.16-arm64.apk](https://github.com/FrancisGiann/Ponpon/releases/download/v0.2.16/Ponpon-0.2.16-arm64.apk) on an ARM64 Android phone running Android 8.0 / API 26 or newer. Generated APKs stay outside Git; use the source build instructions below when working from a clone. The release uses the machine's existing development certificate; no new signing credentials were created. No account or wallet login is required. The app opens with empty records and zero opening balances.

Tap **Get started** to see **Total tracked balance** and named active-wallet balances at the top of Today. A fresh install shows ₱0.00 across Cash and GCash. **All N** opens the full active-wallet breakdown. Tap **Add an entry** below the balances to record money. Enter an amount, choose a category, and tap **Paid with Cash** or **Paid with GCash** for expenses (**Received in** for income). Each named wallet action saves with that explicit choice; the previous payment method is never selected for the next entry. Manage which actions appear in **Wallets → Direct entry buttons**. Select all, clear, select individual active wallets, or move them earlier/later; zero to twenty selections are valid. Entry adapts to the available space in that order: three short names share one equal row, four use a balanced 2 × 2 grid, and larger or constrained selections use a continuous rail with complete wrapped names and separate **All wallets** controls. An empty selection uses **Choose wallet to save**. The picker also opens the same button manager. Notes are optional. The local date is visible and editable. Close or Android Back keeps the unfinished draft.

Long-press the app icon for **Quick add**. Add **Quick entry (2 × 2)**, **Balance (2 × 2)**, or the existing larger category widget through Settings or your launcher's Widgets menu. A widget category opens the ready keypad directly, bypassing the welcome screen. Up to four widget categories can be selected in Settings → Categories. A stale category requires a new explicit choice. Category widgets contain icons and names, with no financial amounts or notes. The separate balance widget shows the total tracked active-wallet balance, with the amount hidden by default; enable **Show balance on widget** in Settings to show it. Tapping the balance opens Add entry and still requires an explicit named-wallet save. Widgets declare home-screen use only.

## Design and responsiveness

Today leads with the total tracked balance and up to three active-wallet balances, followed by recording, four category shortcuts and recent entries. Positive and negative wallet balances appear before zero balances, preserving order within each group. All three preview wallets remain visible; more wallets retain a counted **View all** for the full breakdown; long names and constrained rows stack the name above its balance. History groups records by day. Entry details align short dates, categories and wallet values at the trailing edge; long values and large text stack and wrap, with notes in their own multiline section. Entry opens as a rounded Cupertino sheet against opaque matte backing, with a ready tactile keypad and equal-strength wallet actions. Landscape shows amount/category and keypad/save side by side. Wallet selection, categories and date use consistent sheets; custom wallets have a live icon/name preview. There is no Liquid Glass or decorative backdrop blur.

Routes use a restrained spring, with local press feedback. System/app reduced motion disables authored motion. Saves never wait for animation. Ledger snapshots cache derived views; full save encoding, validation and disk flush run in a worker isolate. Rapid draft changes retain the newest pending write while disk is busy. These measures are verified in tests, including a 10,000-record synthetic round trip; hardware frame pacing still needs the POCO.

## Records and balances

- Expenses, income and recorded transfers are separate types. A transfer is one entry with two distinct wallets; it affects neither income nor spending totals.
- History supports type/wallet filters, search, editing and deletion. Edits immediately recalculate derived totals. Deleted entries remain recoverable in Settings → Recently deleted.
- The latest 30 transaction changes retain persistent undo. A save/delete/update also offers immediate Undo feedback.
- Plan contains one spending budget per local calendar month and a category breakdown. Only expenses count toward the budget.
- Wallet opening balances are optional and editable. A wallet's tracked balance is **opening + income − expenses + transfers in − transfers out + balance adjustments**, using all recorded entries.
- Home's **Total tracked balance** adds the existing balances of active wallets only. Hidden, archived and removed wallets are excluded from this total and its breakdown; their own balances, history and ledger-wide income/spending totals are preserved. Direct entry button choices do not change the balance scope. With no active wallets, Home shows **— / No active wallets** and a route to add or restore wallets.
- Add or rename up to twenty wallets, including hidden wallets, with a name, icon and color. **Remove wallet** asks for confirmation: an unused wallet is removed from active choices recoverably; a wallet referenced by transactions, undo history, a nonzero opening balance or allowance is archived with history and totals intact. **Hidden wallets → Restore** keeps the same ID and records. If its allowance is enabled, **Pause allowance and archive** pauses it in the same save; no funds are rerouted and restoration does not restart it. With no active wallets, entry offers **Add or restore a wallet**. Choose and order zero to twenty direct entry buttons centrally. Browsing the direct actions changes which wallets are visible; it never chooses a wallet or records money. There is no remembered last wallet.
- GCash is a manually tracked wallet, with no official integration. The app does not move real money. Tracked values can differ from actual wallets.

## Bills and balance checks

Settings → Upcoming bills supports once, weekly, monthly and yearly due dates, including month-end recurrence. Reminders are opt-in, quiet and inexact. They never create expenses. Record a payment only after explicitly choosing an active wallet and confirming it; each occurrence has one stable payment identity.

A wallet balance check compares an actual amount with the tracked balance. Review and confirm before recording a labeled adjustment. Opening balances and past entries stay intact. Adjustments change the wallet balance and appear in All History, separately from income and spending totals. The existing after-save Undo can reverse a payment or adjustment.

## Optional allowance

Settings → Scheduled allowance records income on eligible local dates when the app opens or resumes. No personal rule is configured by default. Enter an amount, explicitly choose a wallet, days and a start date, then enable when ready. It never moves real money or reloads GCash.

New rules start today or later. First enable for today asks for confirmation because manual receipts are not matched; start tomorrow if already logged. Enabled edits settle the old rule through today and apply tomorrow. Paused days are skipped. Gaps over 31 days pause for review. Stable occurrence IDs prevent repeat income after reopen, clock rollback, edits, deletion or undo. Newly imported allowance rules restore paused for review. An identical existing rule keeps its current enabled state during a backup merge. No background timer or permission is needed; this is not an exact-time background scheduler.

## Privacy, backup and recovery

The app has no backend, analytics, account, bank login, GCash login, SMS access or notification-reading service. The release manifest requests notification permission only for optional daily and bill reminders and normal boot permission for rescheduling. It requests no network or exact-alarm permission. AndroidX adds only an app-owned signature permission for private dynamic receivers, which produces no permission prompt. Records are readable JSON inside Android's private app storage; they are not separately encrypted. Cloud backup and device-transfer backup are disabled. Private app previews are enabled by default and also block screenshots; the saved preference is retained across the update. Rendered synthetic fixtures do not require changing this protection.

Export a complete JSON backup through Settings → Export backup. Android's document picker lets you choose the destination without broad storage access. Exports are readable, so keep them private. Uninstalling or clearing app data removes local records; export first.

Restore validates application, PHP currency, integer schema version, integer centavos, calendar dates, wallet/category references, limits and unique IDs before writing. Identical existing IDs are skipped. Changed IDs, wallet definitions, opening balances, budgets, categories or allowance rules are rejected rather than overwritten. Different IDs are treated as different records, even when their amounts match. A fresh empty ledger can adopt a valid backup. A snapshot before each restore is available through **Recover before last restore**. Preview shows the resulting tracked wallet balances.

Schema 5 preserves legacy wallet/category IDs and financial history while adding bill schedules and optional payment/adjustment origin metadata. Schema 1–4 backups remain accepted. Imported bill reminders stay off for review; merging the same bill preserves the local reminder choice. The backup application identifier remains `pocket_entry`. Each save stages and flushes bytes, then atomically renames the file. The previous valid ledger is kept. A damaged current file can recover the previous save with a visible notice; two damaged copies fail closed. Unreadable current bytes are preserved when restoring. A fixed draft ID prevents a committed entry from replaying after a crash between saving and clearing its draft. This is tested process/restart behavior, not a guarantee against hardware failure.

## Optional daily reminder

Settings → Daily reminder starts off with no selected time. Confirm your time before allowing notifications; cancelling the picker leaves it unchanged. The quiet local notification asks “Anything to log today? Add your expenses or income.” Tap to open Add entry and explicitly choose the wallet. Denial keeps it off with inline recovery; a system-blocked channel is shown in Settings. Clock/timezone changes, boot and app updates rearm the single inexact alarm. Switching off cancels it. These device-only preferences are outside financial backups; no import enables notifications. Android power management can delay delivery. See `docs/REMINDERS_024.md` for behavior, test scope and device limitations.

## Verification

Current 0.2.16 verification: **367 Flutter tests passed; Flutter analysis is clean**. The ARM64 APK uses version code 2018, retains package `dev.giann.pocket_entry` and the existing signing identity, and passed APK signature verification. Synthetic tests cover transfer previews, insufficient funds, exact centavo validation, edits, concurrent conflicts, cancellation/recovery and custom wallets. No emulator or physical-device check was performed for 0.2.16.

Flutter screenshots are real Flutter test-renderer output at phone dimensions, with simulated system insets. Native widget screenshots are Android RemoteViews rendered through Robolectric API 35 with native graphics. The motion clip is a timed Flutter transition fixture. These establish fixture behavior and layout, **not POCO installation, launcher, frame-rate or hardware haptic verification**.

## Build from source

Toolchain used: Flutter 3.47.2, Dart 3.13.2, Android compile/target SDK 36, JDK 21, Gradle 9.3.1, AGP 9.1.0. Only Flutter and Cupertino Icons are runtime dependencies; Android integration uses a Kotlin platform channel.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1 --reporter=expanded
cd android
./gradlew :app:testDebugUnitTest --no-daemon --max-workers=1 -Ptarget-platform=android-arm64
cd ..
flutter build apk --release --target-platform=android-arm64 --split-per-abi
```

Point Flutter at your installed Android SDK, and use JDK 21. `android/local.properties` is regenerated locally and is omitted from the source archive. Gradle is bounded to one worker, a 1 GB heap and an in-process Kotlin compiler. Robolectric tests use one fork with a 768 MB heap. Flutter's generated AGP compatibility flags are kept; AGP 10 migration is future work. First-time development dependency downloads require network access; the installed app runs offline.

## Known limits and device check

English UI and PHP only; up to twenty manually managed wallets and one optional allowance rule. No cloud sync, CSV import, bank reconciliation, exact-time background scheduler, automatic SMS capture, AI parsing, biometric lock or iOS build. Backups are limited to 5 MB, 20,000 ledger rows including deleted records, and 100 categories. Different versions of a changed backup are deliberately rejected during merge; there is no conflict editor. Entry uses two columns when available width is at least 620 logical pixels and available height is below 480; unusually narrow/short windows retain scrolling to preserve content. Widget dimensions and pin support vary by launcher.

Physical POCO checks are not completed. Two API35 emulator attempts installed the debug app with synthetic data but terminated before valid captures or update checks; those checks are unverified. Before treating this as your everyday ledger, perform the short synthetic POCO checklist in `docs/QA.md`, especially installation, cold widget launch, document-picker cancellation/restart, force-stop draft recovery, system Back, keyboard/font scaling, haptics and smoothness. No real financial data or credentials were used for testing.

## Public assets and references

Ponpon’s user-authorized wallet-led cream/plum icon, with a subtle folded-ear detail and one coin, supplies the app, launcher and widget identity. Native adaptive foreground and monochrome vectors plus all legacy density icons are updated consistently. Package `dev.giann.pocket_entry`, the existing signer, Dart package `pocket_entry` and backup application ID are preserved for update compatibility. Existing PocketEntry project folders remain for continuity; new deliverables use Ponpon names.

Inter is bundled under the SIL Open Font License from the [official Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/inter); its license is in `assets/fonts/OFL.txt`. Cupertino Icons is a public Flutter dependency. No private assets or source from other apps were reused.

Android implementation follows the official [pending-intent guidance](https://developer.android.com/privacy-and-security/risks/pending-intent), [widget documentation](https://developer.android.com/develop/ui/views/appwidgets/overview), and Flutter's [platform-channel documentation](https://docs.flutter.dev/platform-integration/platform-channels). Native unit tests use [Robolectric](https://robolectric.org/getting-started/).

Income automatically selects **General income** and shows only income categories: **Allowance**, **Salary**, **Gift**, **Other income**, plus custom income-icon categories. Expense shows Food, Bills, Travel and other expense categories. Type changes clear incompatible category choices. Old records and category IDs are preserved; missing income built-ins are created only when used to save a record.
