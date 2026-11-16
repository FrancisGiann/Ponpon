import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show capture, configure, loadFonts, synthetic;

Entry entry({
  String id = 'repeat_source',
  EntryKind kind = EntryKind.expense,
  int centavos = 12345,
  String date = '2026-09-01',
  Wallet wallet = Wallet.cash,
  String? categoryId = 'food',
  String note = 'Sample note',
  String? scheduleId,
  String? occurrenceDate,
  String? billId,
  String? billDueDate,
  BalanceAdjustment? adjustment,
  Wallet? toWallet,
  int? deletedAt,
}) => Entry(
  id: id,
  kind: kind,
  centavos: centavos,
  date: date,
  wallet: wallet,
  toWallet: toWallet,
  categoryId: categoryId,
  note: note,
  createdAt: 1000,
  updatedAt: 2000,
  scheduleId: scheduleId,
  occurrenceDate: occurrenceDate,
  billId: billId,
  billDueDate: billDueDate,
  adjustment: adjustment,
  deletedAt: deletedAt,
);

Ledger withEntries(
  Iterable<Entry> entries, {
  AllowanceSchedule? allowance,
  List<Bill> bills = const [],
}) {
  var ledger = synthetic(populated: false).copy(
    allowance: allowance,
    bills: bills,
    preferences: const Preferences(haptics: false),
  );
  for (final value in entries) {
    ledger = ledger.put(value);
  }
  return ledger;
}

class CountingBridge extends NativeBridge {
  int syncCalls = 0;

  @override
  Future<void> sync(
    Ledger ledger, {
    String? revision,
    bool foreground = true,
  }) async {
    syncCalls++;
  }
}

Future<AppController> initializedController(
  Ledger ledger, {
  DateTime Function()? clock,
  NativeBridge? bridge,
}) async {
  final app = AppController(
    store: MemoryLedgerStore(ledger),
    clock: clock,
    bridge: bridge,
  );
  await app.initialize();
  return app;
}

void main() {
  setUpAll(loadFonts);

  test(
    'repeat makes a fresh draft and saves exact centavos only on request',
    () async {
      for (final original in [
        entry(centavos: 1, note: 'One cent'),
        entry(
          id: 'income_source',
          kind: EntryKind.income,
          centavos: 12345,
          wallet: Wallet.gcash,
          categoryId: 'income_salary',
          note: 'Monthly pay',
        ),
      ]) {
        var now = DateTime.utc(2026, 10, 12, 1);
        final ledger = withEntries([original]);
        final app = await initializedController(ledger, clock: () => now);
        addTearDown(app.dispose);
        final store = app.store as MemoryLedgerStore;
        final originalLedger = app.ledger.encode();
        final sourceJson = app.ledger.entry(original.id)!.toJson();

        expect(app.startRepeatDraft(original.id), isTrue);
        final repeatedId = app.draft!.id;
        expect(repeatedId, isNot(original.id));
        expect(app.draft!.editingId, isNull);
        expect(app.draft!.repeatEntry, isTrue);
        expect(app.draft!.amount, moneyInput(original.centavos));
        expect(parseMoney(app.draft!.amount), original.centavos);
        expect(app.draft!.date, dayKey(now.toLocal()));
        expect(app.draft!.categoryId, original.categoryId);
        expect(app.draft!.note, original.note);
        expect(app.draft!.preferredWallet, original.wallet);
        expect(app.ledger.encode(), originalLedger);
        expect(store.writes, 0);

        final openedDate = app.draft!.date;
        now = DateTime.utc(2026, 10, 13, 2);
        expect(await app.saveDraft(original.wallet), isTrue);
        expect(store.writes, 1);
        expect(app.ledger.entry(original.id)!.toJson(), sourceJson);
        final repeated = app.ledger.entry(repeatedId)!;
        expect(repeated.id, isNot(original.id));
        expect(repeated.centavos, original.centavos);
        expect(repeated.kind, original.kind);
        expect(repeated.categoryId, original.categoryId);
        expect(repeated.wallet, original.wallet);
        expect(repeated.note, original.note);
        expect(repeated.date, openedDate);
        expect(repeated.createdAt, now.millisecondsSinceEpoch);
        expect(repeated.updatedAt, now.millisecondsSinceEpoch);
        expect(repeated.scheduleId, isNull);
        expect(repeated.occurrenceDate, isNull);
        expect(repeated.billId, isNull);
        expect(repeated.billDueDate, isNull);
      }
    },
  );

  test(
    'allowance and bill sources repeat as ordinary entries without origins',
    () async {
      final schedule = AllowanceSchedule(
        id: 'schedule_monthly',
        centavos: 40000,
        wallet: Wallet.gcash,
        days: [1],
        startDate: '2026-10-01',
        processedThrough: '2026-10-05',
        enabled: false,
      );
      final occurrenceDate = '2026-10-05';
      final allowance = entry(
        id: schedule.occurrenceId(occurrenceDate),
        kind: EntryKind.income,
        centavos: 40000,
        date: occurrenceDate,
        wallet: Wallet.gcash,
        categoryId: 'income_allowance',
        scheduleId: schedule.id,
        occurrenceDate: occurrenceDate,
      );
      const bill = Bill(
        id: 'rent',
        name: 'Rent',
        centavos: 90000,
        startDate: '2026-10-06',
        frequency: BillFrequency.once,
      );
      final payment = entry(
        id: bill.paymentId(bill.startDate),
        kind: EntryKind.expense,
        centavos: bill.centavos,
        date: bill.startDate,
        categoryId: 'bills',
        note: 'Rent',
        billId: bill.id,
        billDueDate: bill.startDate,
      );
      final app = await initializedController(
        withEntries([allowance, payment], allowance: schedule, bills: [bill]),
      );
      addTearDown(app.dispose);

      for (final source in [allowance, payment]) {
        expect(app.startRepeatDraft(source.id), isTrue);
        final newId = app.draft!.id;
        expect(await app.saveDraft(app.draft!.preferredWallet!), isTrue);
        final repeated = app.ledger.entry(newId)!;
        expect(repeated.kind, source.kind);
        expect(repeated.centavos, source.centavos);
        expect(repeated.scheduleId, isNull);
        expect(repeated.occurrenceDate, isNull);
        expect(repeated.billId, isNull);
        expect(repeated.billDueDate, isNull);
      }
    },
  );

  test(
    'unsupported, deleted, busy, and dirty sources cannot be repeated',
    () async {
      final normal = entry();
      final transfer = entry(
        id: 'transfer_source',
        kind: EntryKind.transfer,
        categoryId: null,
        toWallet: Wallet.gcash,
      );
      final adjustment = entry(
        id: 'adjustment_source',
        kind: EntryKind.income,
        categoryId: null,
        centavos: 200,
        adjustment: const BalanceAdjustment(expected: 1000, actual: 1200),
      );
      final ledger = withEntries([normal, transfer, adjustment])
          .delete(normal.id, 3000);
      final app = await initializedController(ledger);
      addTearDown(app.dispose);

      expect(app.repeatableEntry('missing'), isNull);
      expect(app.repeatableEntry(normal.id), isNull);
      expect(app.repeatableEntry(transfer.id), isNull);
      expect(app.repeatableEntry(adjustment.id), isNull);
      expect(app.startRepeatDraft(normal.id), isFalse);
      expect(app.startRepeatDraft(transfer.id), isFalse);
      expect(app.startRepeatDraft(adjustment.id), isFalse);

      final liveLedger = withEntries([entry()]);
      final dirtyApp = await initializedController(liveLedger);
      addTearDown(dirtyApp.dispose);
      dirtyApp.startDraft(categoryId: 'travel');
      dirtyApp.draft!.amount = '8.25';
      expect(dirtyApp.startRepeatDraft(normal.id), isFalse);
      expect(dirtyApp.draft!.amount, '8.25');
      await dirtyApp.discardDraft();
      dirtyApp.busy = true;
      expect(dirtyApp.startRepeatDraft('repeat_source'), isFalse);
    },
  );

  test(
    'malformed repeat draft cannot edit or overwrite an existing entry',
    () async {
      final source = entry();
      final app = await initializedController(withEntries([source]));
      addTearDown(app.dispose);
      final original = app.ledger.encode();
      app.draft = Draft(
        id: source.id,
        amount: moneyInput(source.centavos),
        kind: source.kind,
        date: source.date,
        categoryId: source.categoryId,
        preferredWallet: source.wallet,
        editingId: source.id,
        repeatEntry: true,
      );
      expect(await app.saveDraft(source.wallet), isFalse);
      expect(app.ledger.encode(), original);
      expect((app.store as MemoryLedgerStore).writes, 0);
    },
  );

  test(
    'archived or missing references stay unselected across draft restart',
    () async {
      final source = entry();
      final complete = withEntries([source]);
      final initial = complete.copy(
        categories: [
          for (final category in complete.categories)
            if (category.id == 'food')
              category.copy(archived: true)
            else
              category,
        ],
        wallets: [
          for (final wallet in Wallet.values)
            if (wallet == Wallet.cash) wallet.copy(archived: true) else wallet,
        ],
      );
      final store = MemoryLedgerStore(initial);
      final app = AppController(store: store);
      await app.initialize();
      addTearDown(app.dispose);
      expect(app.startRepeatDraft(source.id), isTrue);
      expect(app.draft!.categoryId, isNull);
      expect(app.draft!.preferredWallet, isNull);
      await store.saveDraft(jsonEncode(app.draft!.toJson()));

      final restarted = AppController(store: store);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.draft!.repeatEntry, isTrue);
      expect(restarted.draft!.categoryId, isNull);
      expect(restarted.draft!.preferredWallet, isNull);
      expect(await restarted.saveDraft(Wallet.cash), isFalse);
      expect(restarted.ledger.entries, hasLength(1));
      expect(store.writes, 0);

      final missingWallet = initial.copy(
        wallets: initial.wallets
            .where((wallet) => wallet != Wallet.cash)
            .toList(),
      );
      final missingWalletApp = await initializedController(missingWallet);
      addTearDown(missingWalletApp.dispose);
      expect(missingWalletApp.startRepeatDraft(source.id), isTrue);
      expect(missingWalletApp.draft!.preferredWallet, isNull);

      final missingCategory = complete.copy(
        categories: complete.categories
            .where((category) => category.id != 'food')
            .toList(),
      );
      final missingCategoryApp = await initializedController(missingCategory);
      addTearDown(missingCategoryApp.dispose);
      expect(missingCategoryApp.startRepeatDraft(source.id), isTrue);
      expect(missingCategoryApp.draft!.categoryId, isNull);
    },
  );

  test(
    'an explicitly chosen missing built-in category survives repeat restart',
    () async {
      final source = entry(
        id: 'salary_source',
        kind: EntryKind.income,
        categoryId: 'income_salary',
      );
      final complete = withEntries([source]);
      final initial = complete.copy(
        categories: complete.categories
            .where((category) => category.id != 'income_salary')
            .toList(),
      );
      final store = MemoryLedgerStore(initial);
      final app = AppController(store: store);
      await app.initialize();
      addTearDown(app.dispose);
      expect(app.startRepeatDraft(source.id), isTrue);
      expect(app.draft!.categoryId, isNull);
      app.draft!.categoryId = 'income_salary';
      app.draft!.repeatCategoryExplicit = true;
      app.updateDraft();
      await Future<void>.delayed(Duration.zero);
      await store.saveDraft(jsonEncode(app.draft!.toJson()));

      final restarted = AppController(store: store);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.draft!.categoryId, 'income_salary');
      final newId = restarted.draft!.id;
      expect(await restarted.saveDraft(Wallet.cash), isTrue);
      expect(restarted.ledger.category('income_salary')!.isIncome, isTrue);
      expect(restarted.ledger.entry(newId)!.categoryId, 'income_salary');
    },
  );

  test('mismatched source category is cleared and changing repeat kind never auto-selects', () async {
    final mismatched = entry(
      id: 'mismatched_source',
      kind: EntryKind.income,
      categoryId: 'food',
    );
    final app = await initializedController(withEntries([mismatched]));
    addTearDown(app.dispose);
    expect(app.startRepeatDraft(mismatched.id), isTrue);
    expect(app.draft!.categoryId, isNull);
    app.changeDraftKind(EntryKind.expense);
    expect(app.draft!.categoryId, isNull);
    app.changeDraftKind(EntryKind.income);
    expect(app.draft!.categoryId, isNull);
  });

  test('repeated concurrent saves produce one new posting', () async {
    final bridge = CountingBridge();
    final app = await initializedController(
      withEntries([entry()]),
      bridge: bridge,
    );
    addTearDown(app.dispose);
    final store = (app.store as MemoryLedgerStore)
      ..delay = const Duration(milliseconds: 10);
    final syncsBefore = bridge.syncCalls;
    final changesBefore = app.ledger.changes.length;
    expect(app.startRepeatDraft('repeat_source'), isTrue);
    final repeatedId = app.draft!.id;
    final results = await Future.wait([
      app.saveDraft(Wallet.cash),
      app.saveDraft(Wallet.cash),
      app.saveDraft(Wallet.cash),
    ]);
    expect(results.where((saved) => saved), hasLength(1));
    expect(store.writes, 1);
    expect(bridge.syncCalls, syncsBefore + 1);
    expect(app.ledger.changes, hasLength(changesBefore + 1));
    expect(app.ledger.active.map((value) => value.id), contains(repeatedId));
    expect(app.ledger.active, hasLength(2));
  });

  testWidgets(
    'repeat requires an explicit active wallet and separate Record tap',
    (tester) async {
      configure(tester, const Size(390, 844));
      final source = entry();
      final captureKey = GlobalKey();
      final bridge = CountingBridge();
      final app = await initializedController(
        withEntries([source]),
        bridge: bridge,
      );
      addTearDown(app.dispose);
      final store = app.store as MemoryLedgerStore;
      final before = app.ledger.encode();
      final syncsBefore = bridge.syncCalls;
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: PocketApp(
            controller: app,
            testHome: EntryDetailPage(app: app, id: source.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('repeat-entry')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('repeat-entry')));
      await tester.tap(find.byKey(const ValueKey('repeat-entry')));
      await tester.pumpAndSettle();

      expect(app.entryVisible, isTrue);
      expect(app.draft!.repeatEntry, isTrue);
      expect(app.draft!.editingId, isNull);
      expect(app.ledger.encode(), before);
      expect(store.writes, 0);
      expect(
        find.byKey(const ValueKey('repeat-select-wallet')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('repeat-save-entry')), findsOneWidget);
      await capture(tester, captureKey, 'repeat-entry-standard-390');

      await tester.tap(find.byKey(const ValueKey('repeat-select-wallet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wallet-choice-gcash')));
      await tester.pumpAndSettle();
      expect(app.draft!.preferredWallet, Wallet.gcash);
      expect(app.ledger.encode(), before);
      expect(store.writes, 0);

      store.delay = const Duration(milliseconds: 20);
      final record = tester.widget<PrimaryButton>(
        find.byKey(const ValueKey('repeat-save-entry')),
      );
      record.onPressed!();
      record.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      await tester.pumpAndSettle();
      expect(app.ledger.active, hasLength(2));
      expect(store.writes, 1);
      expect(bridge.syncCalls, syncsBefore + 1);
      expect(app.ledger.changes, hasLength(2));
      expect(app.ledger.entry(source.id)!.toJson(), source.toJson());
      final repeat = app.ledger.active.firstWhere(
        (value) => value.id != source.id,
      );
      expect(repeat.wallet, Wallet.gcash);
      expect(repeat.centavos, source.centavos);
    },
  );

  testWidgets('repeat form stays reachable at narrow large text', (
    tester,
  ) async {
    configure(tester, const Size(320, 700), scale: 1.5);
    const mariBank = Wallet(id: 'maribank', label: 'MariBank');
    final source = entry(id: 'narrow_source', wallet: mariBank);
    final initial = withEntries([])
        .copy(wallets: [...Wallet.values, mariBank])
        .put(source);
    final app = await initializedController(initial);
    addTearDown(app.dispose);
    final store = app.store as MemoryLedgerStore;
    final before = app.ledger.encode();
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: PocketApp(
          controller: app,
          testHome: EntryDetailPage(app: app, id: source.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, captureKey, 'repeat-entry-large-type-320-detail');
    await tester.dragFrom(const Offset(160, 600), const Offset(0, -420));
    await tester.pumpAndSettle();
    final repeatButton = find.byKey(const ValueKey('repeat-entry'));
    expect(repeatButton, findsOneWidget);
    await tester.ensureVisible(repeatButton);
    await tester.tap(repeatButton);
    await tester.pumpAndSettle();

    expect(app.draft!.repeatEntry, isTrue);
    expect(app.draft!.preferredWallet, mariBank);
    expect(app.ledger.encode(), before);
    expect(store.writes, 0);
    expect(find.text('MariBank'), findsWidgets);
    await capture(tester, captureKey, 'repeat-entry-large-type-320-top');

    final record = find.byKey(const ValueKey('repeat-save-entry'));
    await tester.ensureVisible(record);
    await tester.pumpAndSettle();
    expect(record.hitTestable(), findsOneWidget);
    await capture(tester, captureKey, 'repeat-entry-large-type-320-bottom');
    await tester.tap(record);
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(app.ledger.active, hasLength(2));
    expect(app.ledger.entry(source.id)!.toJson(), source.toJson());
    expect(
      app.ledger.active.firstWhere((value) => value.id != source.id).wallet,
      mariBank,
    );
  });

  testWidgets('missing source wallet is shown safely and must be reselected', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final source = entry();
    final complete = withEntries([source]);
    final missingWallet = complete.copy(
      wallets: complete.wallets
          .where((wallet) => wallet != Wallet.cash)
          .toList(),
    );
    final app = await initializedController(missingWallet);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: EntryDetailPage(app: app, id: source.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unavailable wallet'), findsOneWidget);
    final repeatButton = find.byKey(const ValueKey('repeat-entry'));
    await tester.ensureVisible(repeatButton);
    await tester.tap(repeatButton);
    await tester.pumpAndSettle();

    expect(app.draft!.preferredWallet, isNull);
    final record = tester.widget<PrimaryButton>(
      find.byKey(const ValueKey('repeat-save-entry')),
    );
    expect(record.onPressed, isNull);
    expect(find.byKey(const ValueKey('repeat-select-wallet')), findsOneWidget);
    expect(app.ledger.entries, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'cancel keeps an unfinished draft; approval replaces it only once',
    (tester) async {
      configure(tester, const Size(390, 844));
      final source = entry();
      final app = await initializedController(withEntries([source]));
      addTearDown(app.dispose);
      final originalLedger = app.ledger.encode();
      app.startDraft(categoryId: 'travel');
      app.draft!.amount = '8.25';
      app.updateDraft();
      final originalDraftId = app.draft!.id;
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: EntryDetailPage(app: app, id: source.id),
        ),
      );
      await tester.pumpAndSettle();
      final repeatButton = find.byKey(const ValueKey('repeat-entry'));
      await tester.ensureVisible(repeatButton);
      await tester.tap(repeatButton);
      await tester.pumpAndSettle();
      expect(app.repeatOpening, isTrue);
      expect(find.text('An entry is unfinished'), findsOneWidget);

      await openRepeatEntry(
        tester.element(repeatButton),
        app,
        sourceId: source.id,
      );
      expect(find.text('An entry is unfinished'), findsOneWidget);
      expect(app.repeatOpening, isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.repeatOpening, isFalse);
      expect(app.draft!.id, originalDraftId);
      expect(app.draft!.amount, '8.25');
      expect(app.ledger.encode(), originalLedger);
      expect(find.byKey(const ValueKey('repeat-save-entry')), findsNothing);

      await tester.tap(repeatButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard entry'));
      await tester.pumpAndSettle();
      expect(app.draft!.repeatEntry, isTrue);
      expect(app.draft!.id, isNot(originalDraftId));
      expect(app.draft!.amount, moneyInput(source.centavos));
      expect(app.ledger.encode(), originalLedger);
      expect(app.store is MemoryLedgerStore, isTrue);
      expect((app.store as MemoryLedgerStore).writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('source is re-resolved before a confirmed draft discard', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final source = entry();
    final app = await initializedController(withEntries([source]));
    addTearDown(app.dispose);
    app.startDraft(categoryId: 'travel');
    app.draft!.amount = '8.25';
    app.updateDraft();
    final oldDraftId = app.draft!.id;
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: EntryDetailPage(app: app, id: source.id),
      ),
    );
    await tester.pumpAndSettle();
    final repeatButton = find.byKey(const ValueKey('repeat-entry'));
    await tester.ensureVisible(repeatButton);
    await tester.tap(repeatButton);
    await tester.pumpAndSettle();
    expect(find.text('An entry is unfinished'), findsOneWidget);

    app.ledger = app.ledger.delete(source.id, 3000);
    app.publish();
    await tester.tap(find.text('Discard entry'));
    await tester.pumpAndSettle();
    expect(app.repeatOpening, isFalse);
    expect(app.draft!.id, oldDraftId);
    expect(app.draft!.amount, '8.25');
    expect(find.byKey(const ValueKey('repeat-save-entry')), findsNothing);
    expect((app.store as MemoryLedgerStore).writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Repeat entry is hidden for transfers, adjustments, and deleted entries',
    (tester) async {
      configure(tester, const Size(390, 844));
      final transfer = entry(
        id: 'transfer_source',
        kind: EntryKind.transfer,
        categoryId: null,
        toWallet: Wallet.gcash,
      );
      final adjustment = entry(
        id: 'adjustment_source',
        kind: EntryKind.income,
        categoryId: null,
        centavos: 200,
        adjustment: const BalanceAdjustment(expected: 1000, actual: 1200),
      );
      final deleted = entry(id: 'deleted_source');
      final ledger = withEntries([transfer, adjustment, deleted])
          .delete(deleted.id, 3000);

      for (final source in [transfer, adjustment, deleted]) {
        final app = await initializedController(ledger);
        await tester.pumpWidget(
          PocketApp(
            controller: app,
            testHome: EntryDetailPage(app: app, id: source.id),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('repeat-entry')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        app.dispose();
      }
    },
  );
}
