import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/entry_page.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show synthetic, configure, capture, loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Map<String, dynamic> state;
  late bool allowed;
  setUp(() {
    calls = [];
    state = {
      'enabled': false,
      'minuteOfDay': null,
      'permitted': true,
      'nextAtMilliseconds': null,
    };
    allowed = true;
    messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'reminderState':
          return state;
        case 'requestReminderPermission':
          return allowed;
        case 'setReminder':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          state = {
            'enabled': args['enabled'] == true && allowed,
            'minuteOfDay': args['minuteOfDay'] ?? state['minuteOfDay'],
            'permitted': allowed,
            'nextAtMilliseconds': args['enabled'] == true && allowed
                ? 1791914400000
                : null,
          };
          return state;
        default:
          return null;
      }
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(NativeBridge.channel, null),
  );

  AppController controller({String theme = 'light'}) {
    final ledger = synthetic(theme: theme);
    final app = AppController(
      store: MemoryLedgerStore(ledger),
      bridge: const NativeBridge(),
      clock: () => DateTime(2026, 10, 13, 18, 15),
    );
    app.ledger = ledger;
    addTearDown(app.dispose);
    return app;
  }

  Future<void> showSettings(
    WidgetTester tester,
    AppController app, {
    GlobalKey? key,
  }) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: PocketApp(
          controller: app,
          testHome: SettingsPage(app: app),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Remind me to log'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Finder toggle() => find
      .widgetWithText(GroupRow, 'Remind me to log')
      .findDescendant(find.byType(PocketSwitch));

  test('Reminder bridge validates state and keeps configuration out of ledger backups', () async {
    expect(ReminderState.fromMap({'minuteOfDay': 1440}).minuteOfDay, isNull);
    expect(ReminderState.fromMap(null).enabled, isFalse);
    final app = controller();
    final before = app.ledger.encode();
    expect((await const NativeBridge().reminderState()).enabled, isFalse);
    await const NativeBridge().setReminder(enabled: true, minuteOfDay: 1234);
    expect(calls.last.arguments, {'enabled': true, 'minuteOfDay': 1234});
    expect(app.ledger.encode(), before);
    expect(before.contains('reminder'), isFalse);
  });

  testWidgets(
    'Opt-in requires time confirmation; cancel never requests permission or schedules',
    (tester) async {
      configure(tester, const Size(390, 844));
      await showSettings(tester, controller());
      expect(calls.map((c) => c.method), ['reminderState']);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(find.text('Reminder time'), findsOneWidget);
      expect(
        calls.where((c) => c.method == 'requestReminderPermission'),
        isEmpty,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'setReminder'), isEmpty);
      expect(state['enabled'], isFalse);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(calls.takeLast(2).map((c) => c.method), [
        'requestReminderPermission',
        'setReminder',
      ]);
      expect(state['enabled'], isTrue);
      expect(state['minuteOfDay'], 18 * 60 + 15);
      expect(find.textContaining('6:15 PM'), findsOneWidget);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(state['enabled'], isFalse);
      expect(calls.last.method, 'setReminder');
    },
  );

  testWidgets(
    'Permission denial stays off and offers Android notification settings',
    (tester) async {
      configure(tester, const Size(390, 844));
      allowed = false;
      await showSettings(tester, controller());
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(state['enabled'], isFalse);
      expect(find.text('Allow notifications'), findsOneWidget);
      await tester.ensureVisible(find.text('Allow notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow notifications'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'openNotificationSettings');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Time can be chosen while off without permission or activation', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    await showSettings(tester, controller());
    await tester.ensureVisible(find.text('Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(state['enabled'], isFalse);
    expect(state['minuteOfDay'], 1095);
    expect(
      calls.where((c) => c.method == 'requestReminderPermission'),
      isEmpty,
    );
  });

  testWidgets(
    'Reload shows scheduling failure and resume clears it after recovery',
    (tester) async {
      configure(tester, const Size(390, 844));
      state = {
        'enabled': true,
        'minuteOfDay': 1200,
        'permitted': true,
        'nextAtMilliseconds': null,
      };
      final key = GlobalKey();
      await showSettings(tester, controller(), key: key);
      const error =
          'The reminder could not be scheduled. Turn it off and try again.';
      expect(find.text(error), findsOneWidget);
      await tester.ensureVisible(find.text(error));
      await tester.pumpAndSettle();
      await capture(tester, key, 'reminder-schedule-recovery-024');
      state['nextAtMilliseconds'] = 1791914400000;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(error), findsNothing);
      expect(calls.where((c) => c.method == 'reminderState').length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in ['light', 'dark']) {
    testWidgets(
      'Synthetic reminder settings $theme render with enlarged type and persisted time',
      (tester) async {
        configure(
          tester,
          const Size(390, 844),
          scale: theme == 'dark' ? 1.5 : 1,
        );
        state = {
          'enabled': true,
          'minuteOfDay': 1200,
          'permitted': true,
          'nextAtMilliseconds': 1791914400000,
        };
        final key = GlobalKey();
        await showSettings(tester, controller(theme: theme), key: key);
        await tester.drag(find.byType(ListView).first, const Offset(0, 240));
        await tester.pumpAndSettle();
        final headingY = tester.getTopLeft(find.text('Daily reminder')).dy;
        await tester.drag(
          find.byType(ListView).first,
          Offset(0, 105 - headingY),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('8:00 PM'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'reminder-settings-$theme-024');
      },
    );
  }

  testWidgets(
    'Reminder quick entry preserves history and explicit wallet actions',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = controller();
      final before = app.ledger.encode();
      await tester.pumpWidget(
        PocketApp(controller: app, initialEntry: const {'categoryId': null}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EntryPage), findsOneWidget);
      expect(find.byKey(const ValueKey('save-cash')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-gcash')), findsOneWidget);
      expect(app.draft!.amount, isEmpty);
      expect(app.ledger.encode(), before);
      expect(tester.takeException(), isNull);
    },
  );
}

extension _Find on Finder {
  Finder findDescendant(Finder child) =>
      find.descendant(of: this, matching: child);
}

extension _Tail<T> on List<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}
