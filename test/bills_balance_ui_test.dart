import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/entry_page.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'bills_balance_test.dart' as data;
import 'ui_test.dart' show configure, loadFonts;

Widget launch(AppController app, Widget page) => PocketApp(
  controller: app,
  testHome: Builder(
    builder: (context) => CupertinoPageScaffold(
      child: Center(
        child: CupertinoButton(
          onPressed: () => pushPocket<void>(context, page),
          child: const Text('Open feature'),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'Bill reminder route opens bills and preserves an unfinished entry',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = data.controller(data.fixture().copy(bills: [data.bill]));
      app.startDraft(categoryId: 'food');
      app.draft!.amount = '9';
      await tester.pumpWidget(
        PocketApp(controller: app, initialEntry: const {'bills': true}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BillsPage), findsOneWidget);
      expect(find.byType(EntryPage), findsNothing);
      expect(app.draft!.amount, '9');
      expect(app.ledger.entries, isEmpty);
    },
  );

  testWidgets(
    'Balance comparison and cancelled confirmation never save an adjustment',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = data.controller(data.fixture());
      final before = app.ledger.encode();
      await tester.pumpWidget(
        launch(app, BalanceCheckPage(app: app, wallet: Wallet.cash)),
      );
      await tester.tap(find.text('Open feature'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('balance-check-actual')),
        '90.00',
      );
      await tester.tap(find.text('Compare balance'));
      await tester.pumpAndSettle();
      expect(app.ledger.encode(), before);
      await tester.ensureVisible(find.text('Review adjustment'));
      await tester.tap(find.text('Review adjustment'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(app.ledger.encode(), before);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.ledger.encode(), before);
      await tester.tap(find.text('Review adjustment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record adjustment'));
      await tester.pumpAndSettle();
      expect(app.ledger.calculate(Wallet.cash).balance, 9000);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.ledger.calculate(Wallet.cash).balance, 10000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bill payment starts with no wallet; review and Undo preserve explicit choice',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = data.controller(data.fixture().copy(bills: [data.bill]));
      await tester.pumpWidget(
        launch(
          app,
          BillPaymentPage(
            app: app,
            bill: data.bill,
            dueDate: data.bill.startDate,
          ),
        ),
      );
      await tester.tap(find.text('Open feature'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Review payment'), 300);
      await tester.tap(find.text('Review payment'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a wallet and expense category.'),
        findsOneWidget,
      );
      expect(app.ledger.entries, isEmpty);
      await tester.scrollUntilVisible(find.text('GCash'), -300);
      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Review payment'), 300);
      await tester.tap(find.text('Review payment'));
      await tester.pumpAndSettle();
      expect(app.ledger.entries, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('Record payment'),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.ledger.active.single.wallet, Wallet.gcash);
      expect(app.ledger.calculate(Wallet.gcash).balance, 15000);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.ledger.calculate(Wallet.gcash).balance, 20000);
      expect(data.bill.nextDue(app.ledger), data.bill.startDate);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Existing Undo ignores rapid or stale taps instead of reversing an older entry',
    (tester) async {
      configure(tester, const Size(390, 844));
      final ledger = data.fixture().put(data.expense('older', 1000));
      final store = MemoryLedgerStore(ledger);
      final app = data.controller(ledger, store: store);
      app.startDraft(categoryId: 'food');
      app.draft!.amount = '5';
      expect(await app.saveDraft(Wallet.cash), isTrue);
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      final press = tester.widget<Press>(
        find
            .ancestor(of: find.text('Undo'), matching: find.byType(Press))
            .first,
      );
      final staleTap = press.onPressed!;
      store.delay = const Duration(milliseconds: 20);
      await tester.tap(find.text('Undo'));
      staleTap();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(app.ledger.active.map((e) => e.id), ['older']);
      expect(app.ledger.calculate(Wallet.cash).balance, 9000);
      staleTap();
      await tester.pumpAndSettle();
      expect(app.ledger.active.map((e) => e.id), ['older']);
      expect(find.text('Undo'), findsNothing);
    },
  );

  testWidgets(
    'Denied bill notification permission stays off and records no bill',
    (tester) async {
      configure(tester, const Size(390, 844));
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
        calls.add(call.method);
        return false;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeBridge.channel, null),
      );
      final ledger = data.fixture();
      final app = AppController(
        store: MemoryLedgerStore(ledger),
        bridge: const NativeBridge(),
      );
      app.ledger = ledger;
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: BillEditorPage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.ensureVisible(find.bySemanticsLabel('Bill reminder'));
      await tester.tap(find.bySemanticsLabel('Bill reminder'));
      await tester.pumpAndSettle();
      expect(calls, ['requestBillReminderPermission']);
      expect(app.ledger.bills, isEmpty);
      expect(app.ledger.entries, isEmpty);
      expect(
        find.text(
          'Allow Ponpon bill notifications in Android settings to enable reminders.',
        ),
        findsOneWidget,
      );
    },
  );

  for (final theme in ['light', 'dark']) {
    testWidgets('Bill and balance screens fit $theme with enlarged type', (
      tester,
    ) async {
      configure(tester, const Size(320, 568), scale: 1.5);
      final app = data.controller(
        data.fixture().copy(
          bills: [data.bill],
          preferences: data.fixture().preferences.copy(theme: theme),
        ),
      );
      for (final page in <Widget>[
        BillsPage(app: app),
        BillEditorPage(app: app, bill: data.bill),
        BillPaymentPage(
          app: app,
          bill: data.bill,
          dueDate: data.bill.startDate,
        ),
        BalanceCheckPage(app: app, wallet: Wallet.cash),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(PocketApp(controller: app, testHome: page));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
