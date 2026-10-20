import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';

Entry record(
  String id,
  EntryKind kind,
  int cents,
  Wallet wallet, {
  Wallet? to,
  String category = 'food',
  String date = '2026-10-12',
  String note = '',
}) => Entry(
  id: id,
  kind: kind,
  centavos: cents,
  date: date,
  wallet: wallet,
  toWallet: to,
  categoryId: kind == EntryKind.transfer ? null : category,
  note: note,
  createdAt: 1000,
  updatedAt: 1000,
);

void main() {
  group('integer centavos', () {
    test('parses exact decimals and large amounts without a float', () {
      expect(parseMoney('0.01'), 1);
      expect(parseMoney('148.50'), 14850);
      expect(parseMoney('1.'), 100);
      expect(parseMoney('0001.2'), 120);
      expect(parseMoney('999999999.99'), maxCentavos);
      expect(parseMoney('-15.05', signed: true), -1505);
      expect(parseMoney('0', allowZero: true), 0);
      expect(money(12345678901), '₱123,456,789.01');
      expect(money(-1), '−₱0.01');
      expect(moneyInput(-101), '-1.01');
    });
    test('rejects extra decimals, exponent, grouping and invalid values', () {
      for (final value in [
        '',
        'NaN',
        '1e3',
        '1.001',
        '1,000',
        '-1',
        '0',
        '.',
        '1000000000',
        '₱25',
      ]) {
        expect(
          () => parseMoney(value),
          throwsA(isA<LedgerException>()),
          reason: value,
        );
      }
    });
  });
  test(
    'transfers conserve total wallets and do not inflate income or expense',
    () {
      var l = Ledger.empty().copy(
        openings: {Wallet.cash: 100000, Wallet.gcash: 400000},
      );
      l = l.put(record('expense', EntryKind.expense, 12550, Wallet.cash));
      l = l.put(
        record(
          'income',
          EntryKind.income,
          55000,
          Wallet.gcash,
          category: 'income',
        ),
      );
      l = l.put(
        record(
          'transfer',
          EntryKind.transfer,
          20000,
          Wallet.cash,
          to: Wallet.gcash,
        ),
      );
      expect(l.calculate(Wallet.cash).balance, 67450);
      expect(l.calculate(Wallet.gcash).balance, 475000);
      expect(l.total(EntryKind.expense, month: '2026-10'), 12550);
      expect(l.total(EntryKind.income), 55000);
      expect(
        l.calculate(Wallet.cash).balance + l.calculate(Wallet.gcash).balance,
        500000 + 55000 - 12550,
      );
      final reversed = record(
        'transfer',
        EntryKind.transfer,
        20000,
        Wallet.gcash,
        to: Wallet.cash,
      );
      l = l.put(reversed, editing: true);
      expect(l.calculate(Wallet.cash).balance, 107450);
      expect(l.calculate(Wallet.gcash).balance, 435000);
    },
  );
  test('edit changes amount, date, wallet and monthly totals', () {
    var l = Ledger.empty().put(
      record('one', EntryKind.expense, 101, Wallet.cash),
    );
    l = l.put(
      record(
        'one',
        EntryKind.income,
        10002,
        Wallet.gcash,
        category: 'income',
        date: '2026-09-30',
      ),
      editing: true,
    );
    expect(l.total(EntryKind.expense, month: '2026-10'), 0);
    expect(l.total(EntryKind.income, month: '2026-09'), 10002);
    expect(l.calculate(Wallet.cash).balance, 0);
    expect(l.calculate(Wallet.gcash).balance, 10002);
    l = Ledger.decode(l.encode()).undo(2000);
    expect(l.total(EntryKind.expense), 101);
    expect(l.calculate(Wallet.cash).balance, -101);
  });
  test('soft deletion, persisted undo and recovery recalculate exactly', () {
    var l = Ledger.empty().put(
      record('one', EntryKind.transfer, 10001, Wallet.cash, to: Wallet.gcash),
    );
    l = l.delete('one', 2000);
    expect(l.active, isEmpty);
    expect(l.entries.single.deleted, isTrue);
    expect(l.calculate(Wallet.gcash).balance, 0);
    l = Ledger.decode(l.encode()).undo(3000);
    expect(l.active.length, 1);
    expect(l.calculate(Wallet.gcash).balance, 10001);
    l = l.delete('one', 4000).restoreDeleted('one', 5000);
    expect(l.active.length, 1);
    expect(l.calculate(Wallet.cash).balance, -10001);
  });
  test(
    'same save ID is idempotent and conflicting repeated save is rejected',
    () {
      final e = record('one', EntryKind.expense, 3, Wallet.cash);
      final l = Ledger.empty().put(e);
      expect(l.put(e).entries.length, 1);
      expect(
        () => l.put(record('one', EntryKind.expense, 4, Wallet.cash)),
        throwsA(isA<LedgerException>()),
      );
      expect(
        () => Ledger.empty().put(
          record(
            'same_wallet',
            EntryKind.transfer,
            1,
            Wallet.cash,
            to: Wallet.cash,
          ),
        ),
        throwsA(isA<LedgerException>()),
      );
    },
  );
  test(
    'v1 migration fills revision and deletion fields and round-trips v3',
    () {
      final old = Ledger.empty()
          .put(record('one', EntryKind.expense, 1501, Wallet.cash))
          .toJson();
      old['schemaVersion'] = 1;
      old.remove('changes');
      old.remove('preferences');
      final rows = old['entries'] as List;
      (rows[0] as Map).remove('updatedAt');
      (rows[0] as Map).remove('deletedAt');
      final migrated = Ledger.decode(jsonEncode(old));
      expect(migrated.entry('one')!.updatedAt, 1000);
      expect(migrated.toJson()['schemaVersion'], schemaVersion);
      expect(migrated.total(EntryKind.expense), 1501);
      expect(Ledger.decode(migrated.encode()).encode(), migrated.encode());
    },
  );
  test('restore repeats safely and rejects changed/deleted records', () {
    final one = Ledger.empty().put(
      record('one', EntryKind.expense, 50, Wallet.cash),
    );
    final preview = previewRestore(one, Ledger.decode(one.encode()));
    expect(preview.added, 0);
    expect(preview.skipped, 1);
    expect(preview.ledger.active.length, 1);
    final two = one.put(
      record('two', EntryKind.income, 77, Wallet.gcash, category: 'income'),
    );
    expect(previewRestore(one, two).added, 1);
    expect(
      () => previewRestore(one.delete('one', 2000), one),
      throwsA(isA<LedgerException>()),
    );
    expect(
      () => previewRestore(
        one,
        one.copy(openings: {Wallet.cash: 1, Wallet.gcash: 0}),
      ),
      throwsA(isA<LedgerException>()),
    );
    expect(
      () => previewRestore(
        one.copy(budgets: {'2026-10': 100}),
        one.copy(budgets: {'2026-10': 200}),
      ),
      throwsA(isA<LedgerException>()),
    );
  });
  test(
    'import validation rejects wrong schemas, dates, duplicates and floats',
    () {
      final good = Ledger.empty()
          .put(record('one', EntryKind.expense, 1, Wallet.cash))
          .encode();
      final cases = <void Function(Map<String, dynamic>)>[
        (m) => m['schemaVersion'] = 99,
        (m) => m['schemaVersion'] = 2.0,
        (m) => m['currency'] = 'USD',
        (m) => m['application'] = 'other_app',
        (m) => (m['entries'] as List)[0]['centavos'] = 1.1,
        (m) => (m['entries'] as List)[0]['date'] = '2026-02-30',
        (m) => (m['entries'] as List)[0]['date'] = '2026-10-12T00:00:00Z',
        (m) => (m['entries'] as List)[0]['wallet'] = 'bank',
        (m) => (m['entries'] as List)[0]['categoryId'] = 'missing',
        (m) => (m['entries'] as List).add((m['entries'] as List)[0]),
        (m) => (m['entries'] as List)[0]['centavos'] = -1,
        (m) => (m['preferences'] as Map)['theme'] = 'invalid',
      ];
      for (final corrupt in cases) {
        final map = jsonDecode(good) as Map<String, dynamic>;
        corrupt(map);
        expect(
          () => Ledger.decode(jsonEncode(map)),
          throwsA(isA<LedgerException>()),
        );
      }
      expect(() => Ledger.decode('not json'), throwsA(isA<LedgerException>()));
      expect(
        () => Ledger.decode(' ' * (maxBackupBytes + 1)),
        throwsA(isA<LedgerException>()),
      );
    },
  );
  test('calendar dates remain local and leap days validate', () {
    expect(dayKey(localDay('2024-02-29')), '2024-02-29');
    expect(localDay('2026-10-12').isUtc, false);
    expect(() => localDay('2025-02-29'), throwsA(isA<LedgerException>()));
    final l = Ledger.empty()
        .put(
          record(
            'one',
            EntryKind.expense,
            maxCentavos,
            Wallet.cash,
            date: '2026-09-30',
          ),
        )
        .put(
          record(
            'two',
            EntryKind.expense,
            maxCentavos,
            Wallet.cash,
            date: '2026-10-01',
          ),
        );
    expect(l.total(EntryKind.expense, month: '2026-09'), maxCentavos);
    expect(l.calculate(Wallet.cash).balance, -2 * maxCentavos);
  });
}
