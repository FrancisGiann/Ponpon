import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';

// Artificial fixtures only. The two tests prefixed REGRESSION intentionally
// express the expected behavior of defects found in the 0.2.5 source audit.
const _allDays = [1, 2, 3, 4, 5, 6, 7];

AllowanceSchedule _rule({
  int cents = 10000,
  List<int> days = _allDays,
  String start = '2026-10-01',
  String through = '2026-09-30',
  bool enabled = true,
}) => AllowanceSchedule(
  id: 'allowance_audit_fixture',
  centavos: cents,
  wallet: Wallet.cash,
  days: days,
  startDate: start,
  processedThrough: through,
  enabled: enabled,
);

Ledger _ledger({AllowanceSchedule? rule}) => Ledger.empty().copy(
  allowance: rule,
  preferences: const Preferences(haptics: false),
);

AppController _app(LedgerStore store, DateTime Function() clock) {
  final app = AppController(store: store, clock: clock);
  addTearDown(app.dispose);
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('REGRESSION scheduled receipts belong to the Allowance category', () {
    final result = catchUpAllowance(
      _ledger(rule: _rule()),
      DateTime(2026, 10, 1, 12),
    );
    expect(result.count, 1);
    expect(result.ledger.calculate(Wallet.cash).balance, 10000);
    expect(result.ledger.total(EntryKind.income), 10000);
    expect(
      result.ledger.total(EntryKind.income, categoryId: 'income_allowance'),
      10000,
      reason:
          'A scheduled PHP 100 receipt should appear under Allowance. '
          'Baseline 0.2.5 records PHP 100 under General income instead; '
          'the aggregate balance is still PHP 100.',
    );
  });

  test(
    'first enable includes today once and future start waits for its date',
    () async {
      var now = DateTime(2026, 10, 1, 23, 59);
      final store = MemoryLedgerStore(_ledger());
      final app = _app(store, () => now);
      await app.initialize();
      expect(
        await app.setAllowance(
          centavos: 12345,
          wallet: Wallet.cash,
          days: _allDays,
          startDate: '2026-10-01',
          enabled: true,
        ),
        isTrue,
      );
      expect(app.ledger.total(EntryKind.income), 12345);
      expect(app.ledger.allowance!.processedThrough, '2026-10-01');
      expect(await app.recordAllowances(), isTrue);
      expect(app.ledger.entries.length, 1);

      final future = _app(MemoryLedgerStore(_ledger()), () => now);
      await future.initialize();
      expect(
        await future.setAllowance(
          centavos: 12345,
          wallet: Wallet.cash,
          days: _allDays,
          startDate: '2026-10-02',
          enabled: true,
        ),
        isTrue,
      );
      expect(future.ledger.entries, isEmpty);
      now = DateTime(2026, 10, 2);
      expect(await future.recordAllowances(), isTrue);
      expect(future.ledger.active.single.date, '2026-10-02');
      expect(future.ledger.total(EntryKind.income), 12345);
    },
  );

  test('weekday eligibility and a future start bound catch-up inclusively', () {
    final beforeStart = _ledger(
      rule: _rule(
        days: const [1, 2, 3, 4, 5],
        start: '2026-10-05',
        through: '2026-08-01',
      ),
    );
    expect(catchUpAllowance(beforeStart, DateTime(2026, 10, 4)).count, 0);
    final first = catchUpAllowance(beforeStart, DateTime(2026, 10, 5));
    expect(first.count, 1);
    expect(first.paused, isFalse);
    final week = catchUpAllowance(first.ledger, DateTime(2026, 10, 12));
    expect(week.count, 5);
    expect(week.ledger.total(EntryKind.income), 60000);
    expect(week.ledger.active.map((e) => e.date), [
      '2026-10-12',
      '2026-10-09',
      '2026-10-08',
      '2026-10-07',
      '2026-10-06',
      '2026-10-05',
    ]);
  });

  for (final boundary in [
    (
      name: 'month',
      start: '2026-01-30',
      through: '2026-01-29',
      end: DateTime(2026, 2, 2),
      dates: ['2026-02-02', '2026-02-01', '2026-01-31', '2026-01-30'],
    ),
    (
      name: 'leap day',
      start: '2028-02-28',
      through: '2028-02-27',
      end: DateTime(2028, 3, 1),
      dates: ['2028-03-01', '2028-02-29', '2028-02-28'],
    ),
    (
      name: 'year',
      start: '2026-12-31',
      through: '2026-12-30',
      end: DateTime(2027, 1, 1),
      dates: ['2027-01-01', '2026-12-31'],
    ),
    (
      name: 'spring DST dates',
      start: '2026-03-07',
      through: '2026-03-06',
      end: DateTime(2026, 3, 9),
      dates: ['2026-03-09', '2026-03-08', '2026-03-07'],
    ),
    (
      name: 'autumn DST dates',
      start: '2026-10-31',
      through: '2026-10-30',
      end: DateTime(2026, 11, 2),
      dates: ['2026-11-02', '2026-11-01', '2026-10-31'],
    ),
  ]) {
    test('${boundary.name} uses local calendar dates once each', () {
      final result = catchUpAllowance(
        _ledger(
          rule: _rule(start: boundary.start, through: boundary.through),
        ),
        boundary.end,
      );
      expect(result.count, boundary.dates.length);
      expect(result.ledger.active.map((e) => e.date), boundary.dates);
      expect(
        result.ledger.total(EntryKind.income),
        boundary.dates.length * 10000,
      );
      expect(result.ledger.allowance!.processedThrough, dayKey(boundary.end));
      expect(catchUpAllowance(result.ledger, boundary.end).count, 0);
    });
  }

  test('31 calendar days catch up, 32 days pause without assumed receipts', () {
    final initial = _ledger(
      rule: _rule(start: '2026-01-01', through: '2025-12-31'),
    );
    final thirtyOne = catchUpAllowance(initial, DateTime(2026, 1, 31));
    expect(thirtyOne.count, 31);
    expect(thirtyOne.ledger.total(EntryKind.income), 310000);
    final thirtyTwo = catchUpAllowance(initial, DateTime(2026, 2, 1));
    expect(thirtyTwo.paused, isTrue);
    expect(thirtyTwo.ledger.allowance!.enabled, isFalse);
    expect(thirtyTwo.ledger.allowance!.processedThrough, '2026-02-01');
    expect(thirtyTwo.ledger.entries, isEmpty);
  });

  test(
    'ordinary restart, same-day rerun and clock rollback do not replay',
    () async {
      var now = DateTime(2026, 10, 3, 23, 59);
      final store = MemoryLedgerStore(_ledger(rule: _rule()));
      final first = _app(store, () => now);
      await first.initialize();
      expect(first.ledger.total(EntryKind.income), 30000);
      expect(store.writes, 1);
      now = DateTime(2026, 10, 2, 1);
      expect(await first.recordAllowances(), isTrue);
      expect(first.ledger.allowance!.processedThrough, '2026-10-03');
      expect(store.writes, 1);
      now = DateTime(2026, 10, 3);
      final restarted = _app(store, () => now);
      await restarted.initialize();
      expect(restarted.ledger.total(EntryKind.income), 30000);
      expect(restarted.ledger.entries.length, 3);
      expect(store.writes, 1);
      now = DateTime(2026, 10, 4);
      expect(await restarted.recordAllowances(), isTrue);
      expect(restarted.ledger.total(EntryKind.income), 40000);
    },
  );

  test(
    'disabled days are skipped and same-day re-enable does not duplicate',
    () async {
      var now = DateTime(2026, 10, 1);
      final app = _app(MemoryLedgerStore(_ledger(rule: _rule())), () => now);
      await app.initialize();
      now = DateTime(2026, 10, 2);
      expect(
        await app.setAllowance(
          centavos: 10000,
          wallet: Wallet.cash,
          days: _allDays,
          startDate: '2026-10-02',
          enabled: false,
        ),
        isTrue,
      );
      // Disabling an enabled rule settles its still-due receipt for today.
      expect(app.ledger.total(EntryKind.income), 20000);
      now = DateTime(2026, 10, 5);
      await app.recordAllowances();
      expect(app.ledger.total(EntryKind.income), 20000);
      for (final enabled in [true, false, true]) {
        expect(
          await app.setAllowance(
            centavos: 10000,
            wallet: Wallet.cash,
            days: _allDays,
            startDate: '2026-10-05',
            enabled: enabled,
          ),
          isTrue,
        );
      }
      expect(app.ledger.total(EntryKind.income), 30000);
      expect(app.ledger.active.map((e) => e.date), [
        '2026-10-05',
        '2026-10-02',
        '2026-10-01',
      ]);
    },
  );

  test('edit, delete, restore and undo retain occurrence identity on replay', () async {
    final now = DateTime(2026, 10, 1);
    final app = _app(MemoryLedgerStore(_ledger(rule: _rule())), () => now);
    await app.initialize();
    final original = app.ledger.active.single;
    app.startDraft(editing: original);
    app.draft!
      ..amount = '25.01'
      ..date = '2026-09-29';
    expect(await app.saveDraft(Wallet.gcash), isTrue);
    expect(app.ledger.entry(original.id)!.occurrenceDate, '2026-10-01');
    expect(app.ledger.calculate(Wallet.cash).balance, 0);
    expect(app.ledger.calculate(Wallet.gcash).balance, 2501);
    expect(await app.delete(app.ledger.entry(original.id)!), isTrue);
    expect(app.ledger.activeWalletBalance, 0);
    // Simulate a stale cursor while retaining the durable occurrence tombstone.
    app.ledger = Ledger.decode(app.ledger.encode()).copy(
      allowance: app.ledger.allowance!.copy(processedThrough: '2026-09-30'),
    );
    expect(await app.recordAllowances(), isTrue);
    expect(app.ledger.activeWalletBalance, 0);
    expect(app.ledger.entries.length, 1);
    expect(await app.restoreDeleted(app.ledger.entry(original.id)!), isTrue);
    expect(app.ledger.activeWalletBalance, 2501);
    expect(await app.undo(), isTrue); // Restore -> deleted.
    expect(await app.undo(), isTrue); // Delete -> edited.
    expect(app.ledger.activeWalletBalance, 2501);
    expect(await app.undo(), isTrue); // Edit -> original.
    expect(app.ledger.activeWalletBalance, 10000);
    expect(await app.undo(), isTrue); // Original insertion -> tombstone.
    expect(await app.recordAllowances(), isTrue);
    expect(app.ledger.activeWalletBalance, 0);
    expect(app.ledger.entries.single.id, original.id);
  });

  test(
    'failed catch-up and failed rule save preserve both entries and cursor',
    () async {
      final initial = _ledger(rule: _rule());
      final store = MemoryLedgerStore(initial)..failWrites = true;
      final app = _app(store, () => DateTime(2026, 10, 3));
      await app.initialize();
      expect(app.ledger.encode(), initial.encode());
      expect(store.value.encode(), initial.encode());
      expect(
        await app.setAllowance(
          centavos: 20000,
          wallet: Wallet.gcash,
          days: _allDays,
          startDate: '2026-10-03',
          enabled: true,
        ),
        isFalse,
      );
      expect(app.ledger.encode(), initial.encode());
      expect(store.value.encode(), initial.encode());
      store.failWrites = false;
      expect(await app.recordAllowances(), isTrue);
      expect(app.ledger.total(EntryKind.income), 30000);
      expect(app.ledger.allowance!.processedThrough, '2026-10-03');
      expect(store.writes, 1);
    },
  );

  test('file restart and previous-save recovery keep each recovered occurrence once', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ponpon-allowance-audit-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileLedgerStore(directory);
    await store.save(_ledger(rule: _rule()));
    final first = _app(store, () => DateTime(2026, 10, 1));
    await first.initialize();
    expect(first.ledger.total(EntryKind.income), 10000);
    final restarted = _app(
      FileLedgerStore(directory),
      () => DateTime(2026, 10, 1),
    );
    await restarted.initialize();
    expect(restarted.ledger.total(EntryKind.income), 10000);
    await store.file('ledger.json').writeAsString('{synthetic-corruption');
    final recovered = _app(
      FileLedgerStore(directory),
      () => DateTime(2026, 10, 1),
    );
    await recovered.initialize();
    expect(recovered.notice, contains('Recovered the previous save'));
    expect(recovered.ledger.entries.length, 1);
    expect(recovered.ledger.total(EntryKind.income), 10000);
    expect(recovered.ledger.allowance!.processedThrough, '2026-10-01');
    expect(await recovered.recordAllowances(), isTrue);
    expect(recovered.ledger.total(EntryKind.income), 10000);
  });

  test(
    'newly imported schedules pause; an identical local rule stays enabled',
    () {
      final imported = catchUpAllowance(
        _ledger(rule: _rule()),
        DateTime(2026, 10, 1),
      ).ledger;
      for (final current in [
        _ledger(),
        _ledger().copy(budgets: {'2026-10': 50000}),
      ]) {
        final preview = previewRestore(current, imported);
        expect(preview.ledger.allowance!.enabled, isFalse);
        expect(preview.ledger.total(EntryKind.income), 10000);
        expect(
          catchUpAllowance(preview.ledger, DateTime(2026, 10, 3)).count,
          0,
        );
      }
      final identical = previewRestore(
        imported,
        Ledger.decode(imported.encode()),
      );
      expect(identical.ledger.allowance!.enabled, isTrue);
      expect(identical.skipped, 1);
      expect(identical.added, 0);
    },
  );

  test(
    'manual receipts are separate from automatic occurrences as documented',
    () {
      final manual = _ledger(rule: _rule()).put(
        const Entry(
          id: 'allowance_audit_manual',
          kind: EntryKind.income,
          centavos: 10000,
          date: '2026-10-01',
          wallet: Wallet.cash,
          categoryId: 'income_allowance',
          note: 'Artificial manual receipt',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      final result = catchUpAllowance(manual, DateTime(2026, 10, 1));
      expect(result.count, 1);
      expect(result.ledger.total(EntryKind.income), 20000);
      expect(result.ledger.entries.length, 2);
    },
  );

  test(
    'REGRESSION editing after clock rollback cannot revisit scanned dates',
    () async {
      final mondayRule = _rule(days: const [1]);
      final alreadyScanned = catchUpAllowance(
        _ledger(rule: mondayRule),
        DateTime(2026, 10, 12),
      ).ledger;
      expect(alreadyScanned.active.map((e) => e.date), [
        '2026-10-12',
        '2026-10-05',
      ]);
      expect(alreadyScanned.total(EntryKind.income), 20000);
      var now = DateTime(2026, 10, 9);
      final app = _app(MemoryLedgerStore(alreadyScanned), () => now);
      await app.initialize();
      expect(app.ledger.allowance!.processedThrough, '2026-10-12');
      expect(
        await app.setAllowance(
          centavos: 20000,
          wallet: Wallet.cash,
          days: _allDays,
          startDate: '2026-10-09',
          enabled: true,
        ),
        isTrue,
      );
      final savedCursor = app.ledger.allowance!.processedThrough;
      now = DateTime(2026, 10, 10);
      expect(await app.recordAllowances(), isTrue);
      expect(
        app.ledger.total(EntryKind.income),
        20000,
        reason:
            'October 10 was already scanned under the Monday-only rule. '
            'Baseline 0.2.5 rewinds the cursor to October 9 on edit and adds '
            'PHP 200 to October 10, inflating PHP 200 to PHP 400.',
      );
      expect(savedCursor, '2026-10-12');
      expect(app.ledger.entry(mondayRule.occurrenceId('2026-10-10')), isNull);
    },
  );
}
