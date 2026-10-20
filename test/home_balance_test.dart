import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';

const _third = Wallet(id: 'synthetic_third', label: 'Third wallet');

Entry _entry(
  String id,
  EntryKind kind,
  int centavos,
  Wallet wallet, {
  Wallet? to,
}) => Entry(
  id: id,
  kind: kind,
  centavos: centavos,
  date: '2026-10-12',
  wallet: wallet,
  toWallet: to,
  categoryId: kind == EntryKind.transfer
      ? null
      : kind == EntryKind.income
      ? 'income'
      : 'food',
  createdAt: 1000,
  updatedAt: 1000,
);

void _expectBalanceWithoutMutation(Ledger ledger, int expected) {
  final before = ledger.toJson();
  final encoded = ledger.encode();
  for (var read = 0; read < 3; read++) {
    expect(ledger.activeWalletBalance, expected);
  }
  expect(ledger.toJson(), before);
  expect(ledger.encode(), encoded);
}

void main() {
  test('opening balances, income, expenses and exact transfers combine', () {
    final ledger = Ledger.empty()
        .copy(openings: {Wallet.cash: 30001, Wallet.gcash: -500})
        .put(_entry('income', EntryKind.income, 777, Wallet.cash))
        .put(_entry('expense', EntryKind.expense, 333, Wallet.cash))
        .put(
          _entry(
            'transfer',
            EntryKind.transfer,
            101,
            Wallet.cash,
            to: Wallet.gcash,
          ),
        );

    expect(ledger.calculate(Wallet.cash).balance, 30344);
    expect(ledger.calculate(Wallet.gcash).balance, -399);
    _expectBalanceWithoutMutation(ledger, 29945);
    expect(ledger.total(EntryKind.income), 777);
    expect(ledger.total(EntryKind.expense), 333);
  });

  test('transfers between active wallets conserve the aggregate', () {
    var ledger = Ledger.empty().copy(
      wallets: [...Wallet.values, _third],
      openings: {Wallet.cash: 10001, Wallet.gcash: -500, _third: 79},
    );
    _expectBalanceWithoutMutation(ledger, 9580);
    for (final (index, amount) in [1, 10001, maxCentavos].indexed) {
      ledger = ledger.put(
        _entry(
          'transfer_$index',
          EntryKind.transfer,
          amount,
          index.isEven ? Wallet.cash : _third,
          to: Wallet.gcash,
        ),
      );
      _expectBalanceWithoutMutation(ledger, 9580);
    }
    expect(ledger.total(EntryKind.income), 0);
    expect(ledger.total(EntryKind.expense), 0);
  });

  for (final removed in [false, true]) {
    final hidden = removed ? 'removed' : 'archived';
    for (final (label, from, to, expected) in [
      ('active to hidden', Wallet.cash, Wallet.gcash, -234),
      ('hidden to active', Wallet.gcash, Wallet.cash, 2234),
      ('hidden to hidden', Wallet.gcash, _third, 1000),
    ]) {
      test('$label transfer respects the $hidden wallet boundary', () {
        final before = Ledger.empty()
            .copy(
              wallets: [...Wallet.values, _third],
              openings: {Wallet.cash: 1000, Wallet.gcash: 2000, _third: 3000},
              preferences: const Preferences(quickWallets: []),
            )
            .put(_entry('boundary', EntryKind.transfer, 1234, from, to: to));
        final ledger = Ledger.decode(
          before
              .copy(
                wallets: [
                  Wallet.cash,
                  Wallet.gcash.copy(archived: true, removed: removed),
                  _third.copy(archived: true, removed: removed),
                ],
              )
              .encode(),
        );

        // Decoded entry references have no status; wallet metadata controls scope.
        expect(ledger.entries.single.wallet.archived, false);
        _expectBalanceWithoutMutation(before, 6000);
        _expectBalanceWithoutMutation(ledger, expected);
        expect(ledger.total(EntryKind.income), 0);
        expect(ledger.total(EntryKind.expense), 0);
        expect(ledger.toJson()['entries'], before.toJson()['entries']);
        expect(ledger.toJson()['changes'], before.toJson()['changes']);
        expect(ledger.toJson()['openings'], before.toJson()['openings']);
        expect(
          ledger.wallets.fold<int>(
            0,
            (sum, wallet) => sum + ledger.calculate(wallet).balance,
          ),
          6000,
        );
        _expectBalanceWithoutMutation(ledger.delete('boundary', 2000), 1000);
      });
    }
  }

  for (final (label, cash, gcash, expected) in [
    ('positive', 101, 202, 303),
    ('negative', -101, -202, -303),
    ('zero', 101, -101, 0),
  ]) {
    test('$label aggregate retains signed integer centavos', () {
      final ledger = Ledger.empty().copy(
        openings: {Wallet.cash: cash, Wallet.gcash: gcash},
      );
      _expectBalanceWithoutMutation(ledger, expected);
      expect(ledger.activeWalletBalance, isA<int>());
    });
  }

  test('all hidden wallets return zero while history and totals remain', () {
    final before = Ledger.empty()
        .copy(
          openings: {Wallet.cash: 100, Wallet.gcash: -200},
          preferences: const Preferences(quickWallets: []),
        )
        .put(_entry('income', EntryKind.income, 201, Wallet.cash))
        .put(_entry('expense', EntryKind.expense, 31, Wallet.gcash));
    final ledger = Ledger.decode(
      before
          .copy(
            wallets: [
              Wallet.cash.copy(archived: true),
              Wallet.gcash.copy(archived: true, removed: true),
            ],
          )
          .encode(),
    );

    expect(ledger.availableWallets, isEmpty);
    _expectBalanceWithoutMutation(ledger, 0);
    expect(ledger.calculate(Wallet.cash).balance, 301);
    expect(ledger.calculate(Wallet.gcash).balance, -231);
    expect(ledger.total(EntryKind.income), 201);
    expect(ledger.total(EntryKind.expense), 31);
    expect(ledger.toJson()['entries'], before.toJson()['entries']);
    expect(ledger.toJson()['changes'], before.toJson()['changes']);
  });

  test('twenty wallets sum exactly beyond the per-wallet amount limit', () {
    final wallets = [
      for (var index = 0; index < 20; index++)
        Wallet(id: 'synthetic_$index', label: 'Synthetic wallet $index'),
    ];
    final ledger = Ledger.decode(
      Ledger.empty()
          .copy(
            wallets: wallets,
            openings: {
              for (final (index, wallet) in wallets.indexed)
                wallet: maxCentavos - index,
            },
            preferences: const Preferences(quickWallets: []),
          )
          .encode(),
    );

    expect(ledger.availableWallets.length, 20);
    _expectBalanceWithoutMutation(ledger, 20 * maxCentavos - 190);
  });

  test(
    'archived and removed balances are both excluded from active wallets',
    () {
      const fourth = Wallet(id: 'synthetic_fourth', label: 'Fourth wallet');
      final ledger = Ledger.decode(
        Ledger.empty()
            .copy(
              wallets: [
                Wallet.cash,
                Wallet.gcash.copy(archived: true),
                _third.copy(archived: true, removed: true),
                fourth,
              ],
              openings: {
                Wallet.cash: 101,
                Wallet.gcash: 202,
                _third: -303,
                fourth: 0,
              },
              preferences: const Preferences(quickWallets: []),
            )
            .encode(),
      );

      expect(ledger.availableWallets.map((wallet) => wallet.id), [
        Wallet.cash.id,
        fourth.id,
      ]);
      _expectBalanceWithoutMutation(ledger, 101);
      expect(ledger.calculate(Wallet.gcash).balance, 202);
      expect(ledger.calculate(_third).balance, -303);
    },
  );

  test(
    'edits, deletion, undo and recovery refresh only their own snapshot',
    () {
      final initial = Ledger.empty().copy(
        openings: {Wallet.cash: 1000, Wallet.gcash: -500},
      );
      _expectBalanceWithoutMutation(initial, 500);
      final added = initial.put(
        _entry('entry', EntryKind.income, 1234, Wallet.cash),
      );
      _expectBalanceWithoutMutation(added, 1734);
      final edited = added.put(
        _entry('entry', EntryKind.expense, 77, Wallet.gcash),
        editing: true,
      );
      _expectBalanceWithoutMutation(edited, 423);
      final deleted = edited.delete('entry', 2000);
      _expectBalanceWithoutMutation(deleted, 500);
      final undoDelete = Ledger.decode(deleted.encode()).undo(3000);
      _expectBalanceWithoutMutation(undoDelete, 423);
      final undoEdit = undoDelete.undo(4000);
      _expectBalanceWithoutMutation(undoEdit, 1734);
      final undoAdd = undoEdit.undo(5000);
      _expectBalanceWithoutMutation(undoAdd, 500);
      final restored = undoAdd.restoreDeleted('entry', 6000);
      _expectBalanceWithoutMutation(restored, 1734);

      // Every earlier warmed cache remains tied to its immutable ledger.
      for (final (ledger, expected) in [
        (initial, 500),
        (added, 1734),
        (edited, 423),
        (deleted, 500),
        (undoDelete, 423),
        (undoEdit, 1734),
        (undoAdd, 500),
        (restored, 1734),
      ]) {
        _expectBalanceWithoutMutation(ledger, expected);
      }
    },
  );

  test('opening and wallet status copies replace warmed aggregate caches', () {
    final initial = Ledger.empty().copy(
      openings: {Wallet.cash: 10001, Wallet.gcash: 10002},
      preferences: const Preferences(quickWallets: []),
    );
    _expectBalanceWithoutMutation(initial, 20003);
    final archived = initial.copy(
      wallets: [Wallet.cash, Wallet.gcash.copy(archived: true)],
    );
    _expectBalanceWithoutMutation(archived, 10001);
    final removed = archived.copy(
      wallets: [Wallet.cash, Wallet.gcash.copy(archived: true, removed: true)],
    );
    _expectBalanceWithoutMutation(removed, 10001);
    final restored = removed.copy(wallets: Wallet.values);
    _expectBalanceWithoutMutation(restored, 20003);
    final updatedOpening = restored.copy(
      openings: {Wallet.cash: 10001, Wallet.gcash: -10001},
    );
    _expectBalanceWithoutMutation(updatedOpening, 0);
    _expectBalanceWithoutMutation(initial, 20003);
    _expectBalanceWithoutMutation(archived, 10001);
    _expectBalanceWithoutMutation(removed, 10001);
    _expectBalanceWithoutMutation(restored, 20003);
  });

  test('empty, partial and ordered direct buttons do not change balances', () {
    final ledger = Ledger.empty().copy(
      openings: {Wallet.cash: 12345, Wallet.gcash: -100},
    );
    for (final ids in <List<String>>[
      [],
      ['gcash'],
      ['gcash', 'cash'],
    ]) {
      final changed = Ledger.decode(
        ledger
            .copy(preferences: ledger.preferences.copy(quickWallets: ids))
            .encode(),
      );
      expect(changed.quickWallets.map((wallet) => wallet.id), ids);
      _expectBalanceWithoutMutation(changed, 12245);
      expect(changed.toJson()['openings'], ledger.toJson()['openings']);
    }
  });

  for (final version in [1, 2, 3]) {
    test(
      'synthetic schema $version decode keeps existing financial meaning',
      () {
        final original = Ledger.empty()
            .copy(openings: {Wallet.cash: 12345, Wallet.gcash: 6789})
            .put(_entry('expense', EntryKind.expense, 1501, Wallet.cash))
            .put(_entry('income', EntryKind.income, 3003, Wallet.gcash))
            .put(
              _entry(
                'transfer',
                EntryKind.transfer,
                1001,
                Wallet.cash,
                to: Wallet.gcash,
              ),
            );
        final old = original.toJson()..['schemaVersion'] = version;
        if (version <= 2) {
          old.remove('wallets');
          old.remove('allowance');
        } else {
          for (final wallet in old['wallets'] as List) {
            (wallet as Map).remove('removed');
          }
        }
        if (version == 1) {
          old.remove('changes');
          old.remove('preferences');
          for (final entry in old['entries'] as List) {
            (entry as Map).remove('updatedAt');
            entry.remove('deletedAt');
          }
        }
        final ledger = Ledger.decode(jsonEncode(old));

        _expectBalanceWithoutMutation(ledger, 20636);
        expect(ledger.calculate(Wallet.cash).balance, 9843);
        expect(ledger.calculate(Wallet.gcash).balance, 10793);
        expect(ledger.total(EntryKind.expense), 1501);
        expect(ledger.total(EntryKind.income), 3003);
        expect(ledger.toJson()['entries'], original.toJson()['entries']);
        expect(ledger.toJson()['schemaVersion'], schemaVersion);
        expect(Ledger.decode(ledger.encode()).encode(), ledger.encode());
      },
    );
  }

  test(
    'aggregate reads reuse calculations without adding persisted fields',
    () {
      final ledger = Ledger.empty().copy(
        openings: {Wallet.cash: 101, Wallet.gcash: 202},
      );
      final cash = ledger.calculate(Wallet.cash);
      final gcash = ledger.calculate(Wallet.gcash);

      _expectBalanceWithoutMutation(ledger, 303);
      expect(identical(ledger.calculate(Wallet.cash), cash), true);
      expect(identical(ledger.calculate(Wallet.gcash), gcash), true);
      expect(ledger.toJson().containsKey('activeWalletBalance'), false);
    },
  );
}
