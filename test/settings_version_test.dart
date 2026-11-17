import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show configure, loadFonts, synthetic;

void main() {
  setUpAll(loadFonts);

  testWidgets('Settings shows the installed Android package version', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'appVersion') return '0.2.18';
      if (call.method == 'reminderState') {
        return {'enabled': false, 'permitted': true};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeBridge.channel, null),
    );

    final app = AppController(
      store: MemoryLedgerStore(synthetic(populated: false)),
      bridge: const NativeBridge(),
    );
    await app.initialize();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: SettingsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, contains('appVersion'));
    final versionLabel = find.textContaining(
      'Ponpon 0.2.18 · Budget & Expenses',
    );
    await tester.scrollUntilVisible(
      versionLabel,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(versionLabel, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Settings keeps its app-name-only fallback without Android', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = AppController(
      store: MemoryLedgerStore(synthetic(populated: false)),
    );
    await app.initialize();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: SettingsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();

    final versionLabel = find.textContaining('Ponpon · Budget & Expenses');
    await tester.scrollUntilVisible(
      versionLabel,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(versionLabel, findsOneWidget);
    expect(find.textContaining('0.2.15'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
