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

Entry billPayment(
  Bill bill,
  String dueDate,
  Wallet wallet, {
  int updatedAt = 10,
}) => Entry(
  id: bill.paymentId(dueDate),
  kind: EntryKind.expense,
  centavos: bill.centavos,
  date: dueDate,
  wallet: wallet,
  categoryId: 'bills',
  note: '${bill.name} · due ${shortDate(dueDate)}',
  createdAt: 1,
  updatedAt: updatedAt,
  billId: bill.id,
  billDueDate: dueDate,
);

Bill billWithId(Bill bill, String id, {bool? enabled, int? paymentCount}) =>
    Bill(
      id: id,
      name: bill.name,
      centavos: bill.centavos,
      startDate: bill.startDate,
      frequency: bill.frequency,
      paymentCount: paymentCount ?? bill.paymentCount,
      enabled: enabled ?? bill.enabled,
      remind: bill.remind,
      deletedAt: bill.deletedAt,
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

  test(
    'Safe to spend counts overdue and horizon occurrences in local dates',
    () {
      final weekly = billWithId(
        bill.copy(
          name: 'Weekly',
          centavos: 1000,
          startDate: '2026-10-05',
          frequency: BillFrequency.weekly,
          remind: false,
        ),
        'weekly',
      );
      final dueToday = billWithId(
        bill.copy(
          name: 'Today',
          centavos: 5000,
          startDate: '2026-10-19',
          frequency: BillFrequency.monthly,
          remind: false,
        ),
        'today',
      );
      final limited = billWithId(
        bill.copy(
          name: 'Limited',
          centavos: 2000,
          startDate: '2026-10-20',
          frequency: BillFrequency.weekly,
          remind: false,
        ),
        'limited',
        paymentCount: 2,
      );
      final paused = billWithId(weekly, 'paused', enabled: false);
      final removed = Bill(
        id: 'removed',
        name: weekly.name,
        centavos: weekly.centavos,
        startDate: weekly.startDate,
        frequency: weekly.frequency,
        enabled: false,
        deletedAt: 2,
      );
      final completed = billWithId(weekly, 'completed', paymentCount: 2);
      var ledger = fixture().copy(
        bills: [weekly, dueToday, limited, paused, removed, completed],
      );
      ledger = ledger.put(billPayment(weekly, '2026-10-12', Wallet.cash));
      ledger = ledger.put(billPayment(completed, '2026-10-05', Wallet.cash));
      ledger = ledger.put(billPayment(completed, '2026-10-12', Wallet.cash));

      final summary = ledger.safeToSpend(DateTime(2026, 10, 19, 23, 59));
      expect(dayKey(summary.throughDate), '2026-10-26');
      expect(summary.activeWalletCount, 2);
      expect(summary.walletBalanceCentavos, 27000);
      expect(summary.duePaymentCount, 5);
      expect(summary.dueCentavos, 10000);
      expect(summary.safeCentavos, 17000);
      expect(
        {
          for (var i = 0; i < summary.duePaymentCount; i++)
            summary.occurrenceAt(i).dueDate,
        },
        {'2026-10-05', '2026-10-19', '2026-10-20', '2026-10-26'},
      );
      expect(
        summary.dueBills.map((group) => group.bill.id),
        isNot(contains('paused')),
      );
      expect(
        summary.dueBills.map((group) => group.bill.id),
        isNot(contains('removed')),
      );
      expect(
        summary.dueBills.map((group) => group.bill.id),
        isNot(contains('completed')),
      );
    },
  );

  test(
    'Safe to spend uses calendar-day horizon and reports missing wallets',
    () {
      final bill = const Bill(
        id: 'dst_weekly',
        name: 'Weekly',
        centavos: 1,
        startDate: '2026-03-07',
        frequency: BillFrequency.weekly,
      );
      final ledger = Ledger.empty().copy(
        wallets: [
          for (final wallet in Wallet.values) wallet.copy(archived: true),
        ],
        bills: [bill],
      );
      final summary = ledger.safeToSpend(DateTime(2026, 3, 7, 23, 59));
      expect(dayKey(summary.throughDate), '2026-03-14');
      expect(summary.duePaymentCount, 2);
      expect(summary.dueCentavos, 2);
      expect(summary.safeCentavos, isNull);
      expect(summary.activeWalletCount, 0);
    },
  );

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

  test('Fixed installment plans preview and cap weekly or monthly dates', () {
    final monthly = bill.copy(
      startDate: '2026-10-31',
      frequency: BillFrequency.monthly,
      paymentCount: 3,
    );
    expect(monthly.lastDueDate, '2026-12-31');
    expect(monthly.occurrence(2), '2026-12-31');
    expect(monthly.occurrence(3), isNull);
    expect(monthly.containsDue('2026-12-31'), isTrue);
    expect(monthly.containsDue('2027-01-31'), isFalse);
    expect(
      bill
          .copy(
            startDate: '2026-10-19',
            frequency: BillFrequency.weekly,
            paymentCount: 2,
          )
          .lastDueDate,
      '2026-10-26',
    );

    final legacy = bill.toJson()..remove('paymentCount');
    expect(Bill.fromJson(legacy).paymentCount, isNull);
    for (final invalid in [0, maxBillPayments + 1]) {
      expect(
        () => Bill.fromJson(monthly.copy(paymentCount: invalid).toJson()),
        throwsA(isA<LedgerException>()),
      );
    }
    expect(
      () =>
          Bill.fromJson(monthly.copy(frequency: BillFrequency.yearly).toJson()),
      throwsA(isA<LedgerException>()),
    );
    expect(
      () => Bill.fromJson(
        bill
            .copy(
              startDate: '2200-12-31',
              frequency: BillFrequency.monthly,
              paymentCount: 2,
            )
            .toJson(),
      ),
      throwsA(isA<LedgerException>()),
    );
  });

  test(
    'Fixed plan progress keeps the next unpaid installment and remaining total',
    () async {
      final plan = bill.copy(paymentCount: 3);
      final ledger = fixture().copy(bills: [plan]);
      final app = controller(ledger);
      final category = ledger.category('bills')!;
      expect(plan.paidInstallments(app.ledger), 0);
      expect(plan.remainingCentavos(app.ledger), 15000);
      expect(plan.nextDue(app.ledger), '2026-10-31');

      for (var index = 0; index < 3; index++) {
        final due = plan.occurrence(index)!;
        expect(
          await app.recordBillPayment(
            plan,
            due,
            Wallet.cash,
            category,
            confirmed: true,
          ),
          isTrue,
        );
        final current = app.ledger.bill(plan.id)!;
        expect(current.paidInstallments(app.ledger), index + 1);
        expect(current.remainingCentavos(app.ledger), (2 - index) * 5000);
        expect(current.nextDue(app.ledger), plan.occurrence(index + 1));
      }
      expect(app.ledger.bill(plan.id)!.nextDue(app.ledger), isNull);
      expect(app.ledger.billPaidDates(plan.id), {
        '2026-10-31',
        '2026-11-30',
        '2026-12-31',
      });
      expect(
        await app.recordBillPayment(
          plan,
          '2027-01-31',
          Wallet.cash,
          category,
          confirmed: true,
        ),
        isFalse,
      );
    },
  );

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

  test('Deleted tombstones do not consume the active bill allowance', () async {
    final activeBills = [
      for (var index = 0; index < maxActiveBills; index++)
        Bill(
          id: 'active_$index',
          name: 'Active $index',
          centavos: 1,
          startDate: '2026-10-31',
        ),
    ];
    final app = controller(fixture().copy(bills: activeBills));
    final fresh = Bill(
      id: 'fresh_bill',
      name: 'Fresh bill',
      centavos: 100,
      startDate: '2026-10-31',
    );
    expect(await app.setBill(fresh), isFalse);

    final removedFirst = app.ledger.bills.first.copy(
      enabled: false,
      remind: false,
      deletedAt: 2,
    );
    app.ledger = app.ledger.copy(
      bills: [removedFirst, ...app.ledger.bills.skip(1)],
    );
    expect(await app.setBill(fresh), isTrue);
    expect(app.ledger.bills.length, maxActiveBills + 1);
    expect(
      app.ledger.bills.where((bill) => !bill.deleted).length,
      maxActiveBills,
    );
  });

  test(
    'Deleting a bill reverses linked wallets and one Undo restores exact state',
    () async {
      final plan = bill.copy(paymentCount: 3);
      final ledger = fixture()
          .copy(bills: [plan])
          .put(billPayment(plan, '2026-10-31', Wallet.cash))
          .put(billPayment(plan, '2026-11-30', Wallet.gcash, updatedAt: 20));
      final before = ledger.encode();
      final app = controller(ledger);
      final payments = ledger.entries.where((entry) => !entry.deleted).toList();

      expect(await app.deleteBill(plan, payments), isTrue);
      final deleted = app.ledger.bill(plan.id)!;
      expect(deleted.deleted, isTrue);
      expect(deleted.enabled, isFalse);
      expect(deleted.remind, isFalse);
      expect(deleted.nextDue(app.ledger), isNull);
      expect(app.ledger.entries.every((entry) => entry.deleted), isTrue);
      expect(app.ledger.calculate(Wallet.cash).balance, 10000);
      expect(app.ledger.calculate(Wallet.gcash).balance, 20000);
      expect(app.ledger.changes.last.isBillChange, isTrue);
      expect(app.feedbackUndo, isTrue);
      expect(Ledger.decode(app.ledger.encode()).encode(), app.ledger.encode());
      final tampered = app.ledger.copy(
        entries: [
          for (final entry in app.ledger.entries)
            if (entry.id == payments.first.id)
              Entry.fromJson({
                ...entry.toJson(),
                'note': 'changed after deletion',
              })
            else
              entry,
        ],
      );
      expect(
        () => Ledger.decode(tampered.encode()),
        throwsA(isA<LedgerException>()),
      );
      expect(
        () => app.ledger.restoreDeleted(payments.first.id, 100),
        throwsA(isA<LedgerException>()),
      );

      expect(await app.undo(), isTrue);
      expect(app.ledger.encode(), before);
      expect(app.ledger.bill(plan.id)!.remind, isTrue);
      expect(app.ledger.entries.every((entry) => !entry.deleted), isTrue);
    },
  );

  test('Bill deletion rejects stale bill or payment snapshots', () async {
    final plan = bill.copy(paymentCount: 2);
    final payment = billPayment(plan, plan.startDate, Wallet.cash);
    final ledger = fixture().copy(bills: [plan]).put(payment);
    expect(
      () => ledger.removeBill(plan.copy(centavos: 6000), [payment], 50),
      throwsA(isA<LedgerException>()),
    );
    final edited = ledger.put(
      Entry.fromJson({...payment.toJson(), 'note': 'corrected'}),
      editing: true,
    );
    expect(
      () => edited.removeBill(plan, [payment], 50),
      throwsA(isA<LedgerException>()),
    );

    final app = controller(ledger);
    expect(await app.setBill(plan.copy(centavos: 6000)), isTrue);
    expect(
      await app.setBill(plan.copy(centavos: 7000), reviewed: plan),
      isFalse,
    );
    expect(app.ledger.bill(plan.id)!.centavos, 6000);
  });

  test('Pristine backup restore silences bill Undo snapshots too', () async {
    final plan = bill.copy(paymentCount: 2);
    final payment = billPayment(plan, plan.startDate, Wallet.cash);
    final app = controller(fixture().copy(bills: [plan]).put(payment));
    expect(await app.deleteBill(plan, [payment]), isTrue);
    final restored = previewRestore(
      Ledger.empty(),
      Ledger.decode(app.ledger.encode()),
    ).ledger;
    expect(restored.bill(plan.id)!.remind, isFalse);
    expect(restored.bill(plan.id)!.enabled, isFalse);
    expect(restored.changes.last.beforeBill!.remind, isFalse);
    expect(restored.changes.last.afterBill!.remind, isFalse);
    expect(restored.changes.last.afterBill!.enabled, isFalse);
    final recoveredApp = controller(restored);
    expect(await recoveredApp.undo(), isTrue);
    expect(recoveredApp.ledger.bill(plan.id)!.deleted, isFalse);
    expect(recoveredApp.ledger.bill(plan.id)!.remind, isFalse);
    expect(recoveredApp.ledger.active.single.id, payment.id);
  });

  test('Deleted bill backups merge without restoring entries or accepting conflicts', () async {
    final plan = bill.copy(paymentCount: 2);
    final payment = billPayment(plan, plan.startDate, Wallet.cash);
    final deleted = fixture().copy(bills: [plan]).put(payment).removeBill(
      plan,
      [payment],
      100,
    );
    final imported = Ledger.decode(deleted.encode());
    final partial = Ledger.empty().copy(
      openings: {Wallet.cash: 10000, Wallet.gcash: 20000},
      budgets: {'2026-10': 100},
    );
    final merged = previewRestore(partial, imported).ledger;
    expect(merged.bill(plan.id)!.deleted, isTrue);
    expect(merged.active, isEmpty);
    expect(merged.bill(plan.id)!.nextDue(merged), isNull);
    expect(merged.entry(payment.id)!.deleted, isTrue);
    expect(
      () => previewRestore(partial.copy(bills: [plan]), imported),
      throwsA(isA<LedgerException>()),
    );
  });

  test(
    'Bill deletion Undo remains bounded near the date-range history cap',
    () {
      final plan = bill.copy(
        startDate: '1900-01-01',
        frequency: BillFrequency.weekly,
        paymentCount: 15000,
      );
      final payments = [
        for (var index = 0; index < 15000; index++)
          Entry(
            id: plan.paymentId(plan.occurrence(index)!),
            kind: EntryKind.expense,
            centavos: plan.centavos,
            date: plan.occurrence(index)!,
            wallet: Wallet.cash,
            categoryId: 'bills',
            createdAt: 1,
            updatedAt: 1,
            billId: plan.id,
            billDueDate: plan.occurrence(index)!,
          ),
      ];
      final ledger = Ledger.empty().copy(bills: [plan], entries: payments);
      final deleted = ledger.removeBill(plan, payments, 100);
      final backup = deleted.encode();
      expect(utf8.encode(backup).length, lessThan(maxBackupBytes));
      final decoded = Ledger.decode(backup);
      expect(decoded.entries.length, 15000);
      expect(decoded.changes.last.billPaymentCount, 15000);
      final undone = decoded.undo(200);
      expect(undone.bill(plan.id)!.deleted, isFalse);
      expect(undone.active.length, 15000);
      expect(undone.active.first.updatedAt, 1);
    },
  );

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

  test(
    'Recurring bills can gain or extend a term without dropping history',
    () async {
      final ledger = fixture().copy(bills: [bill]);
      final app = controller(ledger);
      final category = ledger.category('bills')!;
      await app.recordBillPayment(
        bill,
        bill.startDate,
        Wallet.cash,
        category,
        confirmed: true,
      );

      final twoPayments = bill.copy(paymentCount: 2);
      expect(await app.setBill(twoPayments), isTrue);
      expect(app.ledger.bill(bill.id)!.nextDue(app.ledger), '2026-11-30');
      expect(
        await app.recordBillPayment(
          twoPayments,
          '2026-11-30',
          Wallet.cash,
          category,
          confirmed: true,
        ),
        isTrue,
      );

      expect(await app.setBill(twoPayments.copy(paymentCount: 1)), isFalse);
      expect(app.ledger.bill(bill.id)!.paymentCount, 2);
      expect(await app.setBill(twoPayments.copy(paymentCount: 3)), isTrue);
      expect(app.ledger.bill(bill.id)!.paidInstallments(app.ledger), 2);
      expect(app.ledger.bill(bill.id)!.nextDue(app.ledger), '2026-12-31');
    },
  );

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
    final finiteBill = bill.copy(paymentCount: 6);
    final valid = fixture().copy(
      bills: [
        finiteBill,
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
        'id': finiteBill.id,
        'startDate': finiteBill.startDate,
        'frequency': 'monthly',
        'paymentCount': 6,
        'paidDates': <String>[],
      },
    ]);
    expect(valid.encode(), before);
    expect(valid.entries, isEmpty);
  });
}
