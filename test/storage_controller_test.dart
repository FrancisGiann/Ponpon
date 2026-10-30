import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/coordinated_store.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';

class SpendBeforeTransferStore extends MemoryLedgerStore {
  SpendBeforeTransferStore(super.value);
  bool conflictNext = true;

  @override
  Future<void> save(Ledger ledger) async {
    if (conflictNext) {
      conflictNext = false;
      value = value.put(
        Entry(
          id: 'background_spend',
          kind: EntryKind.expense,
          centavos: 600,
          date: '2026-10-12',
          wallet: Wallet.cash,
          categoryId: 'food',
          createdAt: 2000,
          updatedAt: 2000,
        ),
      );
      throw const LedgerChangedException();
    }
    await super.save(ledger);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'private offline persistence, restart draft, and atomic file recovery',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pocket-synthetic-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileLedgerStore(directory);
      final one = Ledger.empty().copy(
        openings: {Wallet.cash: 20001, Wallet.gcash: 30002},
      );
      await store.save(one);
      final two = one.copy(budgets: {'2026-10': 150000});
      await store.save(two);
      expect(
        (await FileLedgerStore(directory).load()).ledger.encode(),
        two.encode(),
      );
      final draft = Draft(
        categoryId: 'food',
        amount: '1.25',
        date: '2026-10-12',
        note: 'Synthetic only',
      );
      await store.saveDraft(jsonEncode(draft.toJson()));
      expect((await FileLedgerStore(directory).loadDraft())!.amount, '1.25');
      await store.file('ledger.json').writeAsString('{truncated');
      final recovered = await store.load();
      expect(recovered.notice, isNotNull);
      expect(recovered.ledger.encode(), one.encode());
      await store.save(recovered.ledger);
      expect(
        await store.file('ledger.unreadable.json').readAsString(),
        '{truncated',
      );
      expect((await store.load()).ledger.encode(), one.encode());
    },
  );
  test(
    'both damaged saves fail closed without resetting existing files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pocket-synthetic-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileLedgerStore(directory);
      await store.file('ledger.json').writeAsString('broken');
      await store.file('ledger.previous.json').writeAsString('also broken');
      expect(store.load, throwsA(isA<LedgerException>()));
      expect(await store.file('ledger.json').readAsString(), 'broken');
    },
  );
  test('repeated save taps create exactly one entry and one write', () async {
    final store = MemoryLedgerStore(
      Ledger.empty().copy(preferences: const Preferences(haptics: false)),
    )..delay = const Duration(milliseconds: 30);
    final app = AppController(
      store: store,
      clock: () => DateTime(2026, 10, 12),
    );
    addTearDown(app.dispose);
    await app.initialize();
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '0.01';
    app.updateDraft();
    final results = await Future.wait([
      app.saveDraft(Wallet.cash),
      app.saveDraft(Wallet.gcash),
      app.saveDraft(Wallet.cash),
    ]);
    expect(results.where((v) => v).length, 1);
    expect(store.writes, 1);
    expect(app.ledger.entries.single.wallet, Wallet.cash);
    expect(app.ledger.entries.single.centavos, 1);
    expect(app.draft, isNull);
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '0.02';
    await app.saveDraft(Wallet.gcash);
    expect(app.ledger.active.length, 2);
    expect(app.ledger.calculate(Wallet.gcash).balance, -2);
  });
  test(
    'transfers reject overdraw and invalid cents, then accept exact balance',
    () async {
      final initial = Ledger.empty().copy(
        openings: {Wallet.cash: 1000, Wallet.gcash: 50},
        preferences: const Preferences(haptics: false),
      );
      final store = MemoryLedgerStore(initial);
      final app = AppController(
        store: store,
        clock: () => DateTime(2026, 10, 12),
      );
      addTearDown(app.dispose);
      await app.initialize();
      app.startDraft();
      app.changeDraftKind(EntryKind.transfer);
      app.draft!.amount = '10.01';
      app.updateDraft();
      expect(await app.saveDraft(Wallet.cash), false);
      expect(app.storageError, contains('Not enough'));
      expect(app.ledger.entries, isEmpty);
      expect(store.writes, 0);

      for (final amount in ['0', '-0.01', '1.001']) {
        app.draft!.amount = amount;
        app.updateDraft();
        expect(await app.saveDraft(Wallet.cash), false, reason: amount);
        expect(app.ledger.entries, isEmpty, reason: amount);
      }

      app.draft!.amount = '10.00';
      app.updateDraft();
      expect(await app.saveDraft(Wallet.cash), true);
      expect(app.ledger.calculate(Wallet.cash).balance, 0);
      expect(app.ledger.calculate(Wallet.gcash).balance, 1050);
      expect(app.ledger.total(EntryKind.income), 0);
      expect(app.ledger.total(EntryKind.expense), 0);
    },
  );
  test('a concurrent spend refreshes a transfer draft and blocks a stale overdraw retry', () async {
    final store = SpendBeforeTransferStore(
      Ledger.empty().copy(
        openings: {Wallet.cash: 1000, Wallet.gcash: 0},
        preferences: const Preferences(haptics: false),
      ),
    );
    final app = AppController(
      store: store,
      clock: () => DateTime(2026, 10, 12),
    );
    addTearDown(app.dispose);
    await app.initialize();
    app.startDraft();
    app.changeDraftKind(EntryKind.transfer);
    app.draft!.amount = '5.00';
    app.updateDraft();
    expect(await app.saveDraft(Wallet.cash), false);
    expect(app.storageError, contains('Records changed in the background'));
    expect(app.ledger.calculate(Wallet.cash).balance, 400);
    expect(app.draft!.amount, '5.00');

    expect(await app.saveDraft(Wallet.cash), false);
    expect(app.storageError, contains('Available: ₱4.00'));
    expect(store.value.active.single.id, 'background_spend');
    expect(store.value.calculate(Wallet.cash).balance, 400);
  });
  test(
    'editing a transfer replaces its posting before checking available funds',
    () async {
      const mariBank = Wallet(id: 'mari', label: 'MariBank', color: 'green');
      var initial = Ledger.empty().copy(
        wallets: [...Wallet.values, mariBank],
        openings: {Wallet.cash: 2000, Wallet.gcash: 500, mariBank: 0},
        preferences: const Preferences(haptics: false),
      );
      final old = Entry(
        id: 'old_transfer',
        kind: EntryKind.transfer,
        centavos: 1000,
        date: '2026-10-12',
        wallet: Wallet.cash,
        toWallet: Wallet.gcash,
        createdAt: 1000,
        updatedAt: 1000,
      );
      initial = initial.put(old);
      final store = MemoryLedgerStore(initial);
      final app = AppController(
        store: store,
        clock: () => DateTime(2026, 10, 12),
      );
      addTearDown(app.dispose);
      await app.initialize();
      app.startDraft(editing: old);
      app.draft!
        ..amount = '20.00'
        ..to = mariBank;
      app.updateDraft();

      expect(await app.saveDraft(Wallet.cash), true);
      expect(app.ledger.entries, hasLength(1));
      expect(app.ledger.calculate(Wallet.cash).balance, 0);
      expect(app.ledger.calculate(Wallet.gcash).balance, 500);
      expect(app.ledger.calculate(mariBank).balance, 2000);
      expect(app.ledger.total(EntryKind.income), 0);
      expect(app.ledger.total(EntryKind.expense), 0);
    },
  );
  test('a failed save preserves the draft and ledger for retry', () async {
    final store = MemoryLedgerStore(
      Ledger.empty().copy(preferences: const Preferences(haptics: false)),
    )..failWrites = true;
    final app = AppController(store: store);
    addTearDown(app.dispose);
    await app.initialize();
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '123.45';
    expect(await app.saveDraft(Wallet.cash), false);
    expect(app.ledger.entries, isEmpty);
    expect(app.draft!.amount, '123.45');
    expect(app.storageError, contains('Could not save'));
    store.failWrites = false;
    expect(await app.saveDraft(Wallet.gcash), true);
    expect(app.ledger.entries.single.wallet, Wallet.gcash);
  });
  test(
    'crash after commit before clearing draft never replays the transaction',
    () async {
      final store = MemoryLedgerStore(
        Ledger.empty().copy(preferences: const Preferences(haptics: false)),
      );
      final d = Draft(
        id: 'crash_case',
        amount: '15.01',
        categoryId: 'food',
        date: '2026-10-12',
      );
      await store.saveDraft(jsonEncode(d.toJson()));
      await store.save(
        store.value.put(
          Entry(
            id: d.id,
            kind: d.kind,
            centavos: 1501,
            date: d.date,
            wallet: Wallet.gcash,
            categoryId: d.categoryId,
            createdAt: 1000,
            updatedAt: 1000,
          ),
        ),
      );
      final app = AppController(store: store);
      addTearDown(app.dispose);
      await app.initialize();
      expect(app.draft, null);
      expect(store.draft, null);
      expect(app.ledger.active.length, 1);
      expect(await app.saveDraft(Wallet.cash), false);
      expect(app.ledger.active.length, 1);
    },
  );
  test('restore preserves a snapshot and rejects a stale preview', () async {
    final store = MemoryLedgerStore();
    final app = AppController(store: store);
    addTearDown(app.dispose);
    await app.initialize();
    final incoming = Ledger.empty().copy(
      openings: {Wallet.cash: 123, Wallet.gcash: 456},
    );
    final preview = previewRestore(app.ledger, incoming);
    await app.setBudget('2026-10', 150000);
    expect(await app.restore(preview), false);
    expect(app.storageError, contains('changed after'));
    final fresh = previewRestore(Ledger.empty(), incoming);
    app.ledger = Ledger.empty();
    expect(await app.restore(fresh), true);
    expect(store.recovery, isNotNull);
    expect(await app.recoverBeforeRestore(), true);
    expect(app.ledger.openings[Wallet.cash], 0);
  });
  test(
    'unfinished edit remains recoverable after restart and rotation',
    () async {
      final store = MemoryLedgerStore();
      final app = AppController(store: store);
      addTearDown(app.dispose);
      await app.initialize();
      app.startDraft(categoryId: 'travel');
      app.draft!.amount = '123.01';
      app.draft!.note = 'Synthetic trip';
      app.updateDraft();
      // Drain the exact write queue through a discard-free restart.
      await Future<void>.delayed(Duration.zero);
      final restarted = AppController(store: store);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.draft!.amount, '123.01');
      expect(restarted.draft!.categoryId, 'travel');
      expect(restarted.draft!.toJson().keys, isNot(contains('wallet')));
    },
  );
}
