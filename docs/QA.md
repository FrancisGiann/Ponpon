# Ponpon 0.2.5 verification

Completed scope: Direct Entry wallet actions now show three short names in one equal row and four in a balanced 2 × 2 grid on a roomy portrait phone. One/two actions keep bounded, equal prominence. Larger selections or limited label space use a continuous rail with consistent widths and complete wrapped names; no final single wallet grows to fill a page. The separate All wallets row and 48dp rail controls remain reachable. Landscape keeps two working columns with a visible Swipe/count cue. Four-button grids use the existing compact keypad density; small/enlarged composers scroll to preserve the amount/date and touch targets. Explicit wallet saves remain immediate. A real synthetic fling exposed a disposed press-feedback callback; mounted guards now cover that lifecycle case without changing animation values.

The saved 0.2.4 source was copied intact before editing and hashed for guarded synchronization. App changes are limited to entry presentation/space adaptation, shared press lifecycle guards, related manager help copy/product brief, displayed version and meaningful UI tests. Domain/controller, Home ordering, integer-centavo arithmetic, schema 4/history, income categories, native widgets/icon, reminders, screenshot protection, package and signer are unchanged. The separate public README/ad worker's files are excluded from writeback. No push, publication or release was made.

## Automated checks

- **165 Flutter tests passed**, including the new 11 Direct Entry checks and existing ledger totals, transfers, migrations, edits/delete/undo/restore, persistence/failure/restart, Home sorting, direct button selection/order, income category transitions, privacy, reminders, light/dark, enlarged type, landscape and route motion. Evidence: `025-flutter-tests.log`.
- New synthetic fixtures cover **1/2/3/4/6/7 wallets**, 320 × 568, 360 × 640 at 1.5×, near-identical long names and 844 × 390 landscape. They check equal minimum 48dp action bounds; visible third/fourth named saves; exact chosen wallet and amount; income/expense totals; unchanged selected/stored order and privacy; disabled rail ends; and the actual landscape fling with no exception. Existing 19-wallet reachability and dynamic Income-save tests exercise the real navigation/scroll controls.
- **27 native Android tests passed**, zero failures/errors/skips. Evidence: `025-native-tests.log`, `native-test-results-025/`. Native code is unchanged in this update. Tests retain actual Robolectric API 35 RemoteViews inflation/rendering for original larger widgets and new compact/balance widgets, 128/148/180/240dp sizes, 1.5× type, light/dark, hidden/negative/empty/unsynced/large/theoretical-bound balances, 48dp compact targets, no injected wallet/amount, and native reminder scheduling/permission/cancellation/recovery/duplicate behavior at API 26/35.
- Flutter analysis: **no issues**, `025-analysis.log`.
- Fresh visual review approved the main three/four action geometry and requested two control fixes. Its verdict scored both **resolved**: landscape continuation/count and visibly inactive rail-end arrows. The real-fling lifecycle recovery passed. Disposition **ship** applies to the two scored fixes at synthetic Flutter renderer scope, not hardware/launcher approval. Evidence: `025-direct-review.md`, `025-direct-verdict.md`, `025-design-documentation.md`.

## Preserved behavior

Native Quick entry (2 × 2) and separate Balance (2 × 2) remain installed components alongside the original larger widget. Balance shows the tracked active-wallet sum, hidden by default with optional reveal; archived/removed wallets are excluded. Snapshot refresh follows successful writes and initialization/resume. Widget taps open quick Add entry with no wallet/amount injection and require an explicit named wallet action.

Home display groups nonzero balances, including negative ones, before zero balances, retaining source order within both groups. It shows all three wallets and View all/count for more. Saved wallet and Direct Entry order are not changed.

Income automatically selects General income, with General income/Allowance/Salary/Gift/Other income and eligible custom income categories. Expense alone exposes Food/Bills/Travel. Type changes clear incompatible selection. Older category IDs and financial history remain intact; missing built-ins are inserted atomically only when used for a save. Legacy historical categories, edits, undo, restart, backup/restore and category caps retain their regression coverage.

The optional quiet daily reminder starts off with no selected time, asks for permission only after time selection and Done, recovers from denial, and keeps settings outside ledger backups. It uses silent inexact local alarms, local-calendar duplicate guards and cancellation/rescheduling/reload recovery. Native adaptive/monochrome/legacy wallet-led plum/cream icon is retained. Details: `WIDGETS_INCOME_023.md`, `REMINDERS_024.md`, `QA_024.md`.

## Inspected release APK

- File: `Ponpon-0.2.5-arm64.apk`; **version 0.2.5, code 2007**.
- Package `dev.giann.pocket_entry`; ARM64 ABI; min SDK 26; target SDK 36.
- Release/non-debuggable, backup disabled. POST_NOTIFICATIONS runtime and RECEIVE_BOOT_COMPLETED normal permissions; private receiver signature permission retained. No network or exact-alarm permission. Debug-only WidgetProofActivity absent.
- Existing development certificate SHA-256: `b33178ae6305c6776f3971fda246c7f4738200830e5ad1d1709983b3c855ab63`. APK v2 signature and 16 KiB/4-byte alignment verified.
- Size: **17936552 bytes**.
- APK SHA-256: `bee0ca4a3ce5004a7ffefefcaab5ae32bd12e40a88129e64306607b143cac5f1`.
- Evidence: `025-apk-build.log`, `025-apk-signing.txt`, `025-apk-badging.txt`, `025-apk-permissions.txt`, `025-apk-manifest.txt`, `025-apk-alignment.txt`, `build-manifest.json`.

## Proof provenance and remaining device checks

The two supplied private JPEG references were materialized and actually inspected internally before design decisions. Their bytes and contents stay outside project/source/proof/advertising deliverables. No private balances were used in fixtures.

All delivered PNG/motion proof uses artificial data. The 23 Direct Entry PNGs are actual Flutter test-engine renders with bundled Inter, 2× pixels and simulated insets: 0.2.4 before edits, current 0.2.5 after edits. Small/enlarged first-view and scrolled action captures are separate and clearly named. Native images are actual RemoteViews rendered by Robolectric, not launcher screenshots. The 36-frame motion clip samples the app route at nominal 16.667ms test steps and establishes no measured hardware frame rate. Proof filenames and embedded origin metadata identify the renderer scope.

**Physical POCO installation/update preservation, launcher 2 × 2 assignment/insets/resizing, cold/warm widget launch, TalkBack, document-picker cancellation/restart, haptics, predictive Back, hardware frame pacing, notification drawer/overnight timing, physical reboot and POCO power-management behavior remain not performed.** No live-device reminder was enabled. No installed 0.2.5 update or device UI is claimed. Earlier synthetic API 35 debug installs terminated before valid emulator capture/update checks; no empty emulator capture is delivered.

Previous QA, APKs and versioned source archives are preserved. Library delivery is reported only from confirmed write results in the final delivery manifest/handoff.
