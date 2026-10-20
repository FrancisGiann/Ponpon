import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';

const bill = Bill(
  id: 'synthetic_internet',
  name: 'Synthetic Internet',
  centavos: 5000,
  startDate: '2026-10-31',
  remind: true,
);

Ledger fixture() => Ledger.empty().copy(
  openings: {Wallet.cash: 10000, Wallet.gcash: 20000},
  preferences: const Preferences(welcomed: true, haptics: false),
);

AppController controller(Ledger ledger, {MemoryLedgerStore? store}) {
  final app = AppController(
    store: store ?? MemoryLedgerStore(ledger),
    clock: () => DateTime(2026, 10, 19, 12),
  );
  app.ledger = ledger;
  addTearDown(app.dispose);
  return app;
}

Entry expense(String id, int cents) => Entry(
  id: id,
  kind: EntryKind.expense,
  centavos: cents,
  date: '2026-10-18',
  wallet: Wallet.cash,
  categoryId: 'food',
  note: 'Synthetic expense',
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Schema 4 loads without bills and keeps original receipt fields', () {
    final original = fixture().put(expense('old', 1234));
    final old = original.toJson()
      ..['schemaVersion'] = 4
      ..remove('bills');
    final loaded = Ledger.decode(jsonEncode(old));
    expect(loaded.bills, isEmpty);
    expect(loaded.entry('old')!.toJson(), original.entry('old')!.toJson());
    expect(loaded.calculate(Wallet.cash).balance, 8766);
    expect(loaded.toJson()['schemaVersion'], schemaVersion);
  });

  test('Monthly bills clamp to month end without drifting from the anchor', () {
    expect(
      [
        for (var i = 0; i < 5; i++)
          bill.copy(startDate: '2028-01-31').occurrence(i),
      ],
      ['2028-01-31', '2028-02-29', '2028-03-31', '2028-04-30', '2028-05-31'],
    );
    expect(bill.copy(startDate: '2027-01-31').occurrence(1), '2027-02-28');
  });

  test('Weekly, yearly and one-time dates preserve calendar recurrence', () {
    expect(
      bill
          .copy(startDate: '2026-12-28', frequency: BillFrequency.weekly)
          .occurrence(1),
      '2027-01-04',
    );
    final leap = bill.copy(
      startDate: '2028-02-29',
      frequency: BillFrequency.yearly,
    );
    expect(leap.occurrence(1), '2029-02-28');
    expect(leap.occurrence(4), '2032-02-29');
    expect(bill.copy(frequency: BillFrequency.once).occurrence(1), isNull);
    expect(bill.copy(startDate: '2200-12-31').occurrence(1), isNull);
  });

  test('Adding and pausing overdue bills never inserts expenses', () async {
    final app = controller(fixture());
    final opening = app.ledger.activeWalletBalance;
    final overdue = bill.copy(startDate: '2026-01-31');
    expect(await app.setBill(overdue), isTrue);
    expect(overdue.nextDue(app.ledger), '2026-01-31');
    expect(app.ledger.entries, isEmpty);
    expect(app.ledger.activeWalletBalance, opening);
    expect(await app.setBill(overdue.copy(enabled: false)), isTrue);
    expect(app.ledger.bills.single.nextDue(app.ledger), isNull);
  });

  test('Balance preview, refusal and matching balance do not write', () async {
    final ledger = fixture();
    final store = MemoryLedgerStore(ledger);
    final app = controller(ledger, store: store);
    final before = ledger.encode();
    final check = app.checkBalance(Wallet.cash, 9000);
    expect(check.difference, -1000);
    expect(await app.confirmBalanceCheck(check, confirmed: false), isFalse);
    expect(
      await app.confirmBalanceCheck(
        app.checkBalance(Wallet.cash, 10000),
        confirmed: true,
      ),
      isFalse,
    );
    expect(app.ledger.encode(), before);
    expect(store.writes, 0);
  });

  for (final actual in [12550, 7750, -1234, 0]) {
    test(
      'Confirmed actual $actual creates one labeled adjustment, not spending',
      () async {
        final ledger = fixture().put(expense('preserved', 1500));
        final original = ledger.entry('preserved')!.toJson();
        final app = controller(ledger);
        final check = app.checkBalance(Wallet.cash, actual);
        expect(await app.confirmBalanceCheck(check, confirmed: true), isTrue);
        final adjustment = app.ledger.entry(check.id)!;
        expect(adjustment.note, 'Balance adjustment');
        expect(adjustment.adjustment!.expected, 8500);
        expect(adjustment.adjustment!.actual, actual);
        expect(adjustment.categoryId, isNull);
        expect(app.ledger.calculate(Wallet.cash).balance, actual);
        expect(app.ledger.calculate(Wallet.cash).adjustments, actual - 8500);
        expect(app.ledger.total(EntryKind.expense), 1500);
        expect(app.ledger.total(EntryKind.income), 0);
        expect(app.ledger.openings, ledger.openings);
        expect(app.ledger.entry('preserved')!.toJson(), original);
        expect(
          Ledger.decode(app.ledger.encode()).calculate(Wallet.cash).balance,
          actual,
        );
        expect(await app.confirmBalanceCheck(check, confirmed: true), isFalse);
        expect(app.ledger.entries.length, 2);
      },
    );
  }

  test(
    'A stale or archived wallet check is rejected without rewriting history',
    () async {
      final app = controller(fixture());
      final check = app.checkBalance(Wallet.cash, 9000);
      app.ledger = app.ledger.put(expense('intervening', 500));
      final before = app.ledger.encode();
      expect(await app.confirmBalanceCheck(check, confirmed: true), isFalse);
      expect(app.ledger.encode(), before);
      app.ledger = app.ledger.copy(
        wallets: [
          for (final w in app.ledger.wallets)
            if (w == Wallet.cash) w.copy(archived: true) else w,
        ],
        preferences: app.ledger.preferences.copy(quickWallets: ['gcash']),
      );
      expect(
        () => app.checkBalance(Wallet.cash, 10000),
        throwsA(isA<LedgerException>()),
      );
    },
  );

  test(
    'Adjustment save failure retries once; existing Undo restores exact totals',
    () async {
      final ledger = fixture().put(expense('kept', 1000));
      final store = MemoryLedgerStore(ledger)..failWrites = true;
      final app = controller(ledger, store: store);
      final check = app.checkBalance(Wallet.cash, 8000);
      expect(await app.confirmBalanceCheck(check, confirmed: true), isFalse);
      expect(app.ledger.encode(), ledger.encode());
      expect(store.writes, 0);
      store.failWrites = false;
      expect(await app.confirmBalanceCheck(check, confirmed: true), isTrue);
      expect(app.feedbackUndo, isTrue);
      expect(await app.undo(), isTrue);
      expect(app.ledger.calculate(Wallet.cash).balance, 9000);
      expect(app.ledger.entry(check.id)!.deleted, isTrue);
      expect(
        app.ledger.entry('kept')!.toJson(),
        ledger.entry('kept')!.toJson(),
      );
      expect(store.value.calculate(Wallet.cash).balance, 9000);
      expect(await app.restoreDeleted(app.ledger.entry(check.id)!), isTrue);
      expect(app.ledger.calculate(Wallet.cash).balance, 8000);
    },
  );

  test('Payment needs confirmation and an explicit active wallet; repeats are rejected', () async {
    final ledger = fixture().copy(bills: [bill]);
    final store = MemoryLedgerStore(ledger);
    final app = controller(ledger, store: store);
    final category = ledger.category('bills')!;
    expect(
      await app.recordBillPayment(
        bill,
        bill.startDate,
        Wallet.gcash,
        category,
        confirmed: false,
      ),
      isFalse,
    );
    expect(store.writes, 0);
    expect(
      await app.recordBillPayment(
        bill,
        bill.startDate,
        Wallet.gcash,
        category,
        confirmed: true,
      ),
      isTrue,
    );
    final saved = app.ledger.active.single;
    expect(saved.id, bill.paymentId(bill.startDate));
    expect(saved.wallet, Wallet.gcash);
    expect(saved.date, '2026-10-19');
    expect(saved.billDueDate, '2026-10-31');
    expect(app.ledger.calculate(Wallet.gcash).balance, 15000);
    expect(app.ledger.calculate(Wallet.cash).balance, 10000);
    expect(bill.nextDue(app.ledger), '2026-11-30');
    expect(
      await app.recordBillPayment(
        bill,
        bill.startDate,
        Wallet.cash,
        category,
        confirmed: true,
      ),
      isFalse,
    );
    expect(app.ledger.entries.length, 1);
    expect(store.writes, 1);
  });

  test(
    'Payment disk failure and simultaneous taps cannot advance or double-log',
    () async {
      final ledger = fixture().copy(bills: [bill]);
      final store = MemoryLedgerStore(ledger)..failWrites = true;
      final app = controller(ledger, store: store);
      final category = ledger.category('bills')!;
      expect(
        await app.recordBillPayment(
          bill,
          bill.startDate,
          Wallet.cash,
          category,
          confirmed: true,
        ),
        isFalse,
      );
      expect(bill.nextDue(app.ledger), bill.startDate);
      store.failWrites = false;
      final one = app.recordBillPayment(
        bill,
        bill.startDate,
        Wallet.cash,
        category,
        confirmed: true,
      );
      final two = app.recordBillPayment(
        bill,
        bill.startDate,
        Wallet.cash,
        category,
        confirmed: true,
      );
      expect(await one, isTrue);
      expect(await two, isFalse);
      expect(store.writes, 1);
      expect(app.ledger.active.length, 1);
      expect(await app.undo(), isTrue);
      expect(app.ledger.calculate(Wallet.cash).balance, 10000);
      expect(bill.nextDue(app.ledger), bill.startDate);
      expect(
        await app.recordBillPayment(
          bill,
          bill.startDate,
          Wallet.gcash,
          category,
          confirmed: true,
        ),
        isTrue,
      );
      expect(app.ledger.entries.length, 1);
      expect(app.ledger.active.single.wallet, Wallet.gcash);
      expect(await app.undo(), isTrue);
      expect(app.ledger.active, isEmpty);
    },
  );

  test('Edited payment keeps occurrence identity and schedule changes retain history', () async {
    final ledger = fixture().copy(bills: [bill]);
    final app = controller(ledger);
    await app.recordBillPayment(
      bill,
      bill.startDate,
      Wallet.cash,
      ledger.category('bills')!,
      confirmed: true,
    );
    final original = app.ledger.active.single;
    app.startDraft(editing: original);
    app.draft!.amount = '40';
    expect(await app.saveDraft(Wallet.gcash), isTrue);
    expect(app.ledger.active.single.billId, bill.id);
    expect(app.ledger.active.single.billDueDate, bill.startDate);
    expect(bill.nextDue(app.ledger), '2026-11-30');
    expect(
      await app.setBill(bill.copy(frequency: BillFrequency.weekly)),
      isFalse,
    );
    final before = app.ledger.active.single.toJson();
    expect(await app.setBill(bill.copy(centavos: 6500)), isTrue);
    expect(app.ledger.active.single.toJson(), before);
  });

  test('Restart and backup retain payment/adjustment origins and pause imported reminders', () async {
    final ledger = fixture().copy(bills: [bill]);
    final app = controller(ledger);
    await app.recordBillPayment(
      bill,
      bill.startDate,
      Wallet.cash,
      ledger.category('bills')!,
      confirmed: true,
    );
    await app.confirmBalanceCheck(
      app.checkBalance(Wallet.gcash, 19999),
      confirmed: true,
    );
    final directory = await Directory.systemTemp.createTemp(
      'ponpon_synthetic_bills_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileLedgerStore(directory);
    await store.save(app.ledger);
    final loaded = (await store.load()).ledger;
    expect(loaded.encode(), app.ledger.encode());
    final restored = previewRestore(Ledger.empty(), loaded).ledger;
    expect(restored.bills.single.remind, isFalse);
    expect(
      restored.active.map((e) => e.toJson()),
      loaded.active.map((e) => e.toJson()),
    );
    expect(restored.calculate(Wallet.gcash).balance, 19999);
    expect(restored.bills.single.nextDue(restored), '2026-11-30');
  });

  test('Repeated bill backup merge ignores reminder differences and preserves local opt-in', () {
    final backup = fixture()
        .copy(bills: [bill])
        .put(expense('backup_one', 1000));
    final first = previewRestore(Ledger.empty(), backup).ledger;
    expect(first.bills.single.remind, isFalse);
    final second = previewRestore(first, backup);
    expect(second.added, 0);
    expect(second.skipped, 1);
    expect(second.ledger.bills.single.remind, isFalse);
    final newer = backup.put(expense('backup_two', 2000));
    final merged = previewRestore(second.ledger, newer);
    expect(merged.added, 1);
    expect(merged.ledger.bills.single.remind, isFalse);
    expect(
      merged.ledger.entry('backup_one')!.toJson(),
      backup.entry('backup_one')!.toJson(),
    );
    final localOptIn = first.copy(bills: [bill]);
    final reminderOffBackup = backup.copy(bills: [bill.copy(remind: false)]);
    expect(
      previewRestore(localOptIn, reminderOffBackup).ledger.bills.single.remind,
      isTrue,
    );
    expect(
      () => previewRestore(
        first,
        backup.copy(bills: [bill.copy(centavos: 6000)]),
      ),
      throwsA(isA<LedgerException>()),
    );
  });

  test('Forged adjustment and payment metadata is rejected', () async {
    final app = controller(fixture().copy(bills: [bill]));
    await app.confirmBalanceCheck(
      app.checkBalance(Wallet.cash, 9000),
      confirmed: true,
    );
    final bad = app.ledger.toJson();
    final entries = bad['entries'] as List<dynamic>;
    entries.single['centavos'] = 2000;
    expect(
      () => Ledger.decode(jsonEncode(bad)),
      throwsA(isA<LedgerException>()),
    );
    final payment = Entry(
      id: 'bad',
      kind: EntryKind.expense,
      centavos: 5000,
      date: '2026-10-19',
      wallet: Wallet.cash,
      categoryId: 'bills',
      note: '',
      createdAt: 1,
      updatedAt: 1,
      billId: bill.id,
      billDueDate: bill.startDate,
    );
    expect(
      () => Entry.fromJson(payment.toJson()),
      throwsA(isA<LedgerException>()),
    );
  });

  test('Native reminder payload is opt-in, contains no amount or wallet, and records nothing', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeBridge.channel, null),
    );
    final valid = fixture().copy(
      bills: [
        bill,
        const Bill(
          id: 'not_opted_in',
          name: 'No reminder',
          centavos: 7000,
          startDate: '2026-10-20',
        ),
      ],
    );
    final before = valid.encode();
    await const NativeBridge().sync(valid);
    final payload = calls.single.arguments as Map<dynamic, dynamic>;
    expect(payload['billReminders'], [
      {
        'id': bill.id,
        'startDate': bill.startDate,
        'frequency': 'monthly',
        'paidDates': <String>[],
      },
    ]);
    expect(valid.encode(), before);
    expect(valid.entries, isEmpty);
  });
}
