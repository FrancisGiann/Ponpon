import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show configure, fixture, loadFonts;

Entry posting(
  String id,
  EntryKind kind,
  int cents,
  Wallet wallet, {
  Wallet? to,
  String? category,
  String date = '2026-10-12',
  int time = 1,
}) => Entry(
  id: id,
  kind: kind,
  centavos: cents,
  date: date,
  wallet: wallet,
  toWallet: to,
  categoryId: kind == EntryKind.transfer
      ? null
      : category ?? (kind == EntryKind.income ? 'income' : 'food'),
  createdAt: 1,
  updatedAt: time,
);

Ledger startingLedger() =>
    Ledger.empty().copy(openings: {Wallet.cash: 100000, Wallet.gcash: 50000});

Ledger sampleLedger() => startingLedger()
    .put(posting('meal', EntryKind.expense, 14850, Wallet.cash))
    .put(posting('pay', EntryKind.income, 50000, Wallet.gcash))
    .put(
      posting('move', EntryKind.transfer, 20000, Wallet.cash, to: Wallet.gcash),
    );

void main() {
  setUpAll(loadFonts);

  test('1000 Cash +500 GCash +500 income -148.50 expense totals1851.50', () {
    final l = sampleLedger();
    final cash = l.calculate(Wallet.cash), gcash = l.calculate(Wallet.gcash);
    expect(cash.balance, 65150);
    expect(gcash.balance, 120000);
    expect(l.activeWalletBalance, 185150);
    expect(l.total(EntryKind.income), 50000);
    expect(l.total(EntryKind.expense), 14850);
    expect(cash.outgoing, 20000);
    expect(gcash.incoming, 20000);
    expect(cash.incoming + gcash.incoming, cash.outgoing + gcash.outgoing);
    expect(l.total(EntryKind.income) - l.total(EntryKind.expense), 35150);
    expect(l.activeWalletBalance, 150000 + 35150);
    final restored = Ledger.decode(l.encode());
    expect(restored.activeWalletBalance, 185150);
    expect(
      restored.entries.map((e) => e.toJson()),
      l.entries.map((e) => e.toJson()),
    );
  });

  test('Edit wallet/amount/type/transfer direction replaces one posting', () {
    var l = sampleLedger();
    l.calculate(Wallet.cash);
    l.calculate(Wallet.gcash);
    l.total(EntryKind.expense);
    l = l.put(
      posting('meal', EntryKind.expense, 10101, Wallet.gcash, time: 2),
      editing: true,
    );
    expect(l.calculate(Wallet.cash).balance, 80000);
    expect(l.calculate(Wallet.gcash).balance, 109899);
    expect(l.activeWalletBalance, 189899);
    expect(l.total(EntryKind.expense), 10101);

    l = l.put(
      posting('pay', EntryKind.expense, 50000, Wallet.gcash, time: 3),
      editing: true,
    );
    expect(l.total(EntryKind.income), 0);
    expect(l.total(EntryKind.expense), 60101);
    expect(l.activeWalletBalance, 89899);
    l = l.put(
      posting(
        'move',
        EntryKind.transfer,
        20000,
        Wallet.gcash,
        to: Wallet.cash,
        time: 4,
      ),
      editing: true,
    );
    expect(l.calculate(Wallet.cash).balance, 120000);
    expect(l.calculate(Wallet.gcash).balance, -30101);
    expect(l.activeWalletBalance, 89899);
    expect(l.entries.length, 3);
  });

  test('Delete/restore/undo and repeated clicks affect each receipt once', () {
    final original = sampleLedger();
    var l = original.delete('move', 2);
    expect(l.calculate(Wallet.cash).balance, 85150);
    expect(l.calculate(Wallet.gcash).balance, 100000);
    expect(l.activeWalletBalance, 185150);
    expect(l.delete('move', 3).encode(), l.encode());
    l = Ledger.decode(l.encode()).undo(4);
    expect(l.calculate(Wallet.cash).balance, 65150);
    expect(l.calculate(Wallet.gcash).balance, 120000);
    l = l.delete('meal', 5);
    expect(l.activeWalletBalance, 200000);
    l = l.restoreDeleted('meal', 6);
    expect(l.activeWalletBalance, 185150);
    expect(l.restoreDeleted('meal', 7).encode(), l.encode());
    l = l.undo(8);
    expect(l.activeWalletBalance, 200000);
    l = l.undo(9);
    expect(l.activeWalletBalance, 185150);
  });

  test('Opening is a starting amount, not a replacement for current balance', () {
    final old = sampleLedger();
    final entries = jsonEncode(old.entries.map((e) => e.toJson()).toList());
    final changed = old.copy(openings: {...old.openings, Wallet.cash: 65150});
    // Entering651.50 as the opening after the existing -348.50 flow yields303.
    expect(changed.calculate(Wallet.cash).balance, 30300);
    expect(old.calculate(Wallet.cash).balance, 65150);
    expect(
      jsonEncode(changed.entries.map((e) => e.toJson()).toList()),
      entries,
    );
    expect(changed.total(EntryKind.expense), old.total(EntryKind.expense));
    expect(changed.total(EntryKind.income), old.total(EntryKind.income));
  });

  test(
    'Hidden/removed wallet leaves active total but retains historical money',
    () {
      final base = sampleLedger();
      for (final removed in [false, true]) {
        final hidden = base.copy(
          wallets: [
            Wallet.cash,
            Wallet.gcash.copy(archived: true, removed: removed),
          ],
          preferences: base.preferences.copy(quickWallets: ['cash']),
        );
        expect(hidden.activeWalletBalance, 65150);
        expect(hidden.calculate(Wallet.gcash).balance, 120000);
        expect(hidden.total(EntryKind.income), 50000);
        expect(hidden.total(EntryKind.expense), 14850);
        expect(Ledger.decode(hidden.encode()).activeWalletBalance, 65150);
        expect(hidden.copy(wallets: Wallet.values).activeWalletBalance, 185150);
      }
      expect(
        base
            .copy(
              wallets: [
                Wallet.cash.copy(archived: true),
                Wallet.gcash.copy(archived: true),
              ],
            )
            .activeWalletBalance,
        0,
      );
    },
  );

  test('Cent precision is exact and unsupported decimals are rejected', () {
    var l = Ledger.empty();
    for (var i = 0; i < 100; i++) {
      l = l.put(
        posting('cent_$i', EntryKind.income, parseMoney('0.01'), Wallet.cash),
      );
    }
    l = l.put(
      posting('two_cents', EntryKind.expense, parseMoney('0.02'), Wallet.cash),
    );
    expect(l.calculate(Wallet.cash).balance, 98);
    expect(money(l.calculate(Wallet.cash).balance), '₱0.98');
    expect(parseMoney('999999999.99'), maxCentavos);
    expect(parseMoney('-0.01', signed: true), -1);
    expect(() => parseMoney('1.005'), throwsA(isA<LedgerException>()));
    expect(() => parseMoney('1e3'), throwsA(isA<LedgerException>()));
  });

  test('Date/month/category aggregates use the entered calendar period', () {
    var l = Ledger.empty();
    for (final item in [
      ('sep', '2026-09-30', 100, 'food'),
      ('oct_first', '2026-10-01', 200, 'food'),
      ('oct_last', '2026-10-31', 300, 'other'),
      ('nov', '2026-11-01', 400, 'food'),
      ('dec', '2026-12-31', 500, 'other'),
      ('jan', '2027-01-01', 600, 'food'),
    ]) {
      l = l.put(
        posting(
          item.$1,
          EntryKind.expense,
          item.$3,
          Wallet.cash,
          date: item.$2,
          category: item.$4,
        ),
      );
    }
    l = l.put(
      posting(
        'oct_pay',
        EntryKind.income,
        10000,
        Wallet.cash,
        date: '2026-10-15',
      ),
    );
    l = l.put(
      posting(
        'oct_move',
        EntryKind.transfer,
        5000,
        Wallet.cash,
        to: Wallet.gcash,
        date: '2026-10-15',
      ),
    );
    expect(l.total(EntryKind.expense, month: '2026-10'), 500);
    expect(
      l.total(EntryKind.expense, month: '2026-10', categoryId: 'food'),
      200,
    );
    expect(l.total(EntryKind.expense, date: '2026-10-31'), 300);
    expect(l.total(EntryKind.income, month: '2026-10'), 10000);
    expect(l.total(EntryKind.expense, month: '2027-01'), 600);
    expect(l.total(EntryKind.expense), 2100);
    expect(l.activeWalletBalance, 7900);
  });

  test(
    'Deterministic mixed journal agrees with independently applied postings',
    () {
      final random = Random(26015);
      var l = startingLedger();
      final balances = {Wallet.cash: 100000, Wallet.gcash: 50000};
      final bucket = {EntryKind.income: 0, EntryKind.expense: 0};
      final expected = <String, Entry>{};
      void apply(Entry e, int sign) {
        if (e.deleted) return;
        if (e.kind == EntryKind.transfer) {
          balances[e.wallet] = balances[e.wallet]! - sign * e.centavos;
          balances[e.toWallet!] = balances[e.toWallet!]! + sign * e.centavos;
        } else {
          bucket[e.kind] = bucket[e.kind]! + sign * e.centavos;
          balances[e.wallet] =
              balances[e.wallet]! +
              sign * e.centavos * (e.kind == EntryKind.income ? 1 : -1);
        }
      }

      for (var step = 0; step < 180; step++) {
        final live = expected.values.where((e) => !e.deleted).toList();
        final deleted = expected.values.where((e) => e.deleted).toList();
        final action = random.nextInt(4);
        if (action == 2 && live.isNotEmpty) {
          final old = live[random.nextInt(live.length)];
          apply(old, -1);
          l = l.delete(old.id, step + 10);
          expected[old.id] = l.entry(old.id)!;
        } else if (action == 3 && deleted.isNotEmpty) {
          final old = deleted[random.nextInt(deleted.length)];
          l = l.restoreDeleted(old.id, step + 10);
          expected[old.id] = l.entry(old.id)!;
          apply(expected[old.id]!, 1);
        } else {
          final edit = action == 1 && live.isNotEmpty;
          final old = edit ? live[random.nextInt(live.length)] : null;
          final kind = EntryKind.values[random.nextInt(3)],
              wallet = Wallet.values[random.nextInt(2)];
          final next = posting(
            old?.id ?? 'mix_$step',
            kind,
            1 + random.nextInt(50000),
            wallet,
            to: kind == EntryKind.transfer
                ? Wallet.values.firstWhere((w) => w != wallet)
                : null,
            time: step + 10,
          );
          if (old != null) apply(old, -1);
          apply(next, 1);
          expected[next.id] = next;
          l = l.put(next, editing: edit);
        }
        expect(
          l.calculate(Wallet.cash).balance,
          balances[Wallet.cash],
          reason: 'Cash step$step',
        );
        expect(
          l.calculate(Wallet.gcash).balance,
          balances[Wallet.gcash],
          reason: 'GCash step$step',
        );
        expect(
          l.total(EntryKind.income),
          bucket[EntryKind.income],
          reason: 'income step$step',
        );
        expect(
          l.total(EntryKind.expense),
          bucket[EntryKind.expense],
          reason: 'expense step$step',
        );
        expect(
          l.activeWalletBalance,
          150000 + bucket[EntryKind.income]! - bucket[EntryKind.expense]!,
        );
        if (step % 17 == 0) l = Ledger.decode(l.encode());
      }
    },
  );

  testWidgets(
    'History amount search accepts1000 without formatting punctuation',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(
        Ledger.empty().put(
          posting('search_amount', EntryKind.expense, 100000, Wallet.cash),
        ),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: HistoryPage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EntryRow), findsOneWidget);
      await tester.enterText(find.byType(CupertinoSearchTextField), '1000');
      await tester.pumpAndSettle();
      expect(find.byType(EntryRow), findsOneWidget);
      expect(find.text('No matching entries'), findsNothing);
    },
  );

  testWidgets(
    'Wallet/type filters include transfers once and never change money',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(sampleLedger());
      addTearDown(app.dispose);
      final before = app.ledger.encode();
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: HistoryPage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EntryRow), findsNWidgets(3));
      await tester.tap(find.text('GCash').first);
      await tester.pumpAndSettle();
      expect(find.byType(EntryRow), findsNWidgets(2));
      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryRow), findsNothing);
      expect(app.ledger.encode(), before);
      expect(app.ledger.activeWalletBalance, 185150);
    },
  );
}
