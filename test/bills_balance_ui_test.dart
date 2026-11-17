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
    'Safe to spend shows reserved dates, breakdown, and direct routes',
    (tester) async {
      configure(tester, const Size(320, 640), scale: 1.5);
      final weekly = data.bill.copy(
        startDate: '2026-10-05',
        frequency: BillFrequency.weekly,
      );
      final app = data.controller(data.fixture().copy(bills: [weekly]));
      await tester.pumpWidget(launch(app, SafeToSpendCard(app: app)));
      await tester.tap(find.text('Open feature'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('safe-to-spend-card')), findsOneWidget);
      expect(find.text('₱100.00'), findsOneWidget);
      expect(
        find.textContaining('₱200.00 set aside for 4 due or overdue'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('safe-to-spend-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('safe-to-spend-breakdown')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ListView>(
              find.byKey(const ValueKey('safe-to-spend-breakdown')),
            )
            .childrenDelegate
            .estimatedChildCount,
        4,
      );
      await tester.tap(find.text('View all bills'));
      await tester.pumpAndSettle();
      expect(find.byType(BillsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bill deletion confirms wallet credits and one Undo restores it',
    (tester) async {
      configure(tester, const Size(390, 844));
      final plan = data.bill.copy(paymentCount: 2);
      final ledger = data
          .fixture()
          .copy(bills: [plan])
          .put(data.billPayment(plan, plan.startDate, Wallet.cash))
          .put(data.billPayment(plan, plan.occurrence(1)!, Wallet.gcash));
      final app = data.controller(ledger);
      await tester.pumpWidget(
        launch(app, BillEditorPage(app: app, bill: plan)),
      );
      await tester.tap(find.text('Open feature'));
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 6 &&
            find.byKey(const ValueKey('bill-delete')).evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -420));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('bill-delete')), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bill-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cash: +₱50.00'), findsOneWidget);
      expect(find.textContaining('GCash: +₱50.00'), findsOneWidget);
      await tester.tap(find.text('Delete bill and reverse payments'));
      await tester.pumpAndSettle();

      expect(app.ledger.bill(plan.id)!.deleted, isTrue);
      expect(app.ledger.calculate(Wallet.cash).balance, 10000);
      expect(app.ledger.calculate(Wallet.gcash).balance, 20000);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.ledger.bill(plan.id)!.deleted, isFalse);
      expect(app.ledger.calculate(Wallet.cash).balance, 5000);
      expect(app.ledger.calculate(Wallet.gcash).balance, 15000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'No-due Safe to spend card stays compact and has no fake amount',
    (tester) async {
      configure(tester, const Size(320, 640), scale: 1.5);
      final app = data.controller(data.fixture());
      await tester.pumpWidget(launch(app, SafeToSpendCard(app: app)));
      await tester.tap(find.text('Open feature'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('safe-to-spend-details')), findsNothing);
      expect(find.text('₱300.00'), findsOneWidget);
      expect(
        find.textContaining('No unpaid bill payments due'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('safe-to-spend-add-bill')));
      await tester.pumpAndSettle();
      expect(find.byType(BillEditorPage), findsOneWidget);
      expect(find.text('Add bill'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      expect(find.text('Payment recorded'), findsOneWidget);
      final paidBurst = tester.widget<CustomPaint>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('bill-celebration-paid')),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(paidBurst.painter, isNotNull);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.ledger.calculate(Wallet.gcash).balance, 20000);
      expect(data.bill.nextDue(app.ledger), data.bill.startDate);
      expect(find.text('Payment recorded'), findsNothing);
      await tester.scrollUntilVisible(find.text('Review payment'), 300);
      expect(find.text('Review payment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Installment schedule shows dates and payment status', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final plan = data.bill.copy(paymentCount: 2);
    final app = data.controller(data.fixture().copy(bills: [plan]));
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: BillsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('0/2 installments paid · ₱100.00 remaining'));
    await tester.pumpAndSettle();
    expect(find.text('Payment schedule'), findsOneWidget);
    expect(find.text('Payment 1'), findsOneWidget);
    expect(find.text('Payment 2'), findsOneWidget);
    expect(find.text('Next due'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Final installment celebrates completion and Undo returns to payment',
    (tester) async {
      configure(tester, const Size(390, 844));
      final plan = data.bill.copy(paymentCount: 2);
      final ledger = data.fixture().copy(bills: [plan]);
      final app = data.controller(ledger);
      final category = ledger.category('bills')!;
      expect(
        await app.recordBillPayment(
          plan,
          plan.startDate,
          Wallet.cash,
          category,
          confirmed: true,
        ),
        isTrue,
      );
      await tester.pumpWidget(
        launch(
          app,
          BillPaymentPage(app: app, bill: plan, dueDate: plan.occurrence(1)!),
        ),
      );
      await tester.tap(find.text('Open feature'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Cash'), -300);
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Review payment'), 300);
      await tester.tap(find.text('Review payment'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('Record payment'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All installments paid'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bill-celebration-completed')),
        findsOneWidget,
      );
      expect(app.ledger.bill(plan.id)!.nextDue(app.ledger), isNull);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('All installments paid'), findsNothing);
      expect(app.ledger.bill(plan.id)!.nextDue(app.ledger), plan.occurrence(1));
      await tester.scrollUntilVisible(find.text('Review payment'), 300);
      expect(find.text('Review payment'), findsOneWidget);
      app.clearFeedback();
      expect(
        await app.preferences(app.ledger.preferences.copy(reduceMotion: true)),
        isTrue,
      );
      await tester.scrollUntilVisible(find.text('Review payment'), 300);
      await tester.tap(find.text('Review payment'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('Record payment'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('All installments paid'), findsOneWidget);
      final reducedBurst = tester.widget<CustomPaint>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('bill-celebration-completed')),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(reducedBurst.painter, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Bill progress bar fills and recomputes after save and Undo', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final plan = data.bill.copy(paymentCount: 2);
    final ledger = data
        .fixture()
        .copy(bills: [plan])
        .put(data.billPayment(plan, plan.occurrence(0)!, Wallet.cash));
    final app = data.controller(ledger);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: BillsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();

    final track = find.byKey(ValueKey('bill-progress-track-${plan.id}'));
    final fill = find.byKey(ValueKey('bill-progress-fill-${plan.id}'));
    expect(track, findsOneWidget);
    expect(fill, findsOneWidget);
    expect(
      tester.getSize(fill).width,
      closeTo(tester.getSize(track).width / 2, 1),
    );

    expect(
      await app.recordBillPayment(
        plan,
        plan.occurrence(1)!,
        Wallet.cash,
        app.ledger.category('bills')!,
        confirmed: true,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(fill).width, closeTo(tester.getSize(track).width, 1));

    expect(await app.undo(), isTrue);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(fill).width,
      closeTo(tester.getSize(track).width / 2, 1),
    );
    expect(tester.takeException(), isNull);
  });

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
      const reminderSwitch = ValueKey('bill-reminder-switch');
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(reminderSwitch));
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
