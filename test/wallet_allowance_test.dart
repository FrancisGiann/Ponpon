import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';

const maya = Wallet(
  id: 'fixture_maya',
  label: 'Maya',
  icon: 'phone',
  color: 'green',
);
Ledger custom() => Ledger.empty().copy(
  wallets: [...Wallet.values, maya],
  openings: {Wallet.cash: 0, Wallet.gcash: 0, maya: 0},
  preferences: const Preferences(haptics: false),
);
AllowanceSchedule schedule({
  bool enabled = true,
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  String start = '2026-10-01',
  String through = '2026-09-30',
}) => AllowanceSchedule(
  id: 'fixture_schedule',
  centavos: 10001,
  wallet: maya,
  days: days,
  startDate: start,
  processedThrough: through,
  enabled: enabled,
);
void main() {
  test(
    'real v2 fixture preserves IDs, openings, journal and balances through v3',
    () {
      final old = jsonDecode(
        File('test/fixtures/legacy-v2.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final l = Ledger.decode(jsonEncode(old));
      expect(l.wallets.map((w) => w.id), ['cash', 'gcash']);
      expect(l.allowance, isNull);
      expect(l.entry('legacy_expense')!.wallet, Wallet.cash);
      expect(l.calculate(Wallet.cash).balance, 45000);
      expect(l.calculate(Wallet.gcash).balance, 112000);
      expect(l.changes.length, 1);
      expect(Ledger.decode(l.encode()).encode(), l.encode());
    },
  );
  test('custom transfer, rename, archived history and backup keep stable references', () async {
    final app = AppController(
      store: MemoryLedgerStore(
        custom().copy(openings: {Wallet.cash: 0, Wallet.gcash: 1234, maya: 0}),
      ),
      clock: () => DateTime(2026, 10, 5),
    );
    addTearDown(app.dispose);
    await app.initialize();
    app.startDraft();
    app.draft!
      ..kind = EntryKind.transfer
      ..from = Wallet.gcash
      ..to = maya
      ..amount = '12.34';
    expect(await app.saveDraft(Wallet.gcash), true);
    expect(app.ledger.calculate(maya).balance, 1234);
    expect(app.ledger.calculate(Wallet.gcash).balance, 0);
    expect(app.ledger.total(EntryKind.income), 0);
    expect(app.ledger.total(EntryKind.expense), 0);
    await app.setWallet(maya.copy(label: 'School wallet', archived: true));
    final l = Ledger.decode(app.ledger.encode());
    expect(l.wallet(maya)!.label, 'School wallet');
    expect(l.entry(app.ledger.entries.single.id)!.toWallet, maya);
    expect(previewRestore(l, l).skipped, 1);
    final broken = l.toJson();
    broken['wallets'] = (broken['wallets'] as List)
        .where((w) => w['id'] != maya.id)
        .toList();
    expect(
      () => Ledger.decode(jsonEncode(broken)),
      throwsA(isA<LedgerException>()),
    );
  });
  test(
    'wallet validation rejects duplicates, orphaned transfers and bad pins',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => (m['wallets'] as List).add((m['wallets'] as List).first),
        (m) => m['openings']['unknown'] = 3,
        (m) => m['preferences']['quickWallets'] = ['unknown'],
        (m) => m['wallets'][0]['color'] = 'unknown',
      ]) {
        final m = custom().toJson();
        mutate(m);
        expect(
          () => Ledger.decode(jsonEncode(m)),
          throwsA(isA<LedgerException>()),
        );
      }
    },
  );
  test('catch-up uses exact calendar occurrences and skips weekends', () {
    final l = custom().copy(allowance: schedule(days: [1, 2, 3, 4, 5]));
    final result = catchUpAllowance(l, DateTime(2026, 10, 5, 23, 59));
    expect(result.count, 3);
    expect(result.ledger.total(EntryKind.income), 30003);
    expect(result.ledger.active.map((e) => e.date), [
      '2026-10-05',
      '2026-10-02',
      '2026-10-01',
    ]);
    expect(result.ledger.allowance!.processedThrough, '2026-10-05');
    expect(
      catchUpAllowance(
        Ledger.decode(result.ledger.encode()),
        DateTime(2026, 10, 5),
      ).count,
      0,
    );
    expect(catchUpAllowance(result.ledger, DateTime(2026, 10, 4)).count, 0);
    expect(catchUpAllowance(result.ledger, DateTime(2026, 10, 6)).count, 1);
  });
  test(
    'catch-up commit is atomic across failure, repetition and restart',
    () async {
      final store = MemoryLedgerStore(custom().copy(allowance: schedule()))
        ..failWrites = true;
      final app = AppController(
        store: store,
        clock: () => DateTime(2026, 10, 3),
      );
      addTearDown(app.dispose);
      await app.initialize();
      expect(app.ledger.entries, isEmpty);
      expect(app.ledger.allowance!.processedThrough, '2026-09-30');
      store.failWrites = false;
      store.delay = const Duration(milliseconds: 10);
      await Future.wait([
        app.recordAllowances(),
        app.recordAllowances(),
        app.recordAllowances(),
      ]);
      expect(app.ledger.entries.length, 3);
      expect(store.writes, 1);
      final restarted = AppController(
        store: store,
        clock: () => DateTime(2026, 10, 3),
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.ledger.entries.length, 3);
      expect(store.writes, 1);
    },
  );
  test(
    'edited, deleted and undone allowance occurrences never regenerate',
    () async {
      final store = MemoryLedgerStore(custom().copy(allowance: schedule()));
      final app = AppController(
        store: store,
        clock: () => DateTime(2026, 10, 1),
      );
      addTearDown(app.dispose);
      await app.initialize();
      final original = app.ledger.entries.single;
      app.startDraft(editing: original);
      app.draft!
        ..amount = '3.21'
        ..date = '2026-09-29';
      expect(await app.saveDraft(Wallet.cash), true);
      expect(app.ledger.entries.single.occurrenceDate, '2026-10-01');
      await app.delete(app.ledger.entries.single);
      await app.recordAllowances();
      expect(app.ledger.active, isEmpty);
      await app.undo();
      expect(app.ledger.active.single.centavos, 321);
      await app.undo();
      expect(app.ledger.active.single.centavos, 10001);
      await app.undo();
      await app.recordAllowances();
      expect(app.ledger.active, isEmpty);
      final stale = app.ledger.copy(
        allowance: app.ledger.allowance!.copy(processedThrough: '2026-09-30'),
      );
      expect(catchUpAllowance(stale, DateTime(2026, 10, 1)).count, 0);
    },
  );
  test(
    'paused days and future start never become guessed historical income',
    () async {
      final app = AppController(
        store: MemoryLedgerStore(
          custom().copy(allowance: schedule(enabled: false)),
        ),
        clock: () => DateTime(2026, 10, 6),
      );
      addTearDown(app.dispose);
      await app.initialize();
      expect(app.ledger.entries, isEmpty);
      await app.setAllowance(
        centavos: 20000,
        wallet: maya,
        days: [1, 2, 3, 4, 5, 6, 7],
        startDate: '2026-10-06',
        enabled: true,
      );
      expect(app.ledger.entries.single.date, '2026-10-06');
      final future = catchUpAllowance(
        custom().copy(allowance: schedule(start: '2026-12-01')),
        DateTime(2026, 10, 6),
      );
      expect(future.count, 0);
      expect(
        await app.setAllowance(
          centavos: 1,
          wallet: maya,
          days: [1],
          startDate: '2026-10-01',
          enabled: true,
        ),
        false,
      );
    },
  );
  test('enabled edits settle old rule, apply tomorrow and archive requires moving schedule', () async {
    var now = DateTime(2026, 10, 1);
    final app = AppController(
      store: MemoryLedgerStore(custom().copy(allowance: schedule())),
      clock: () => now,
    );
    addTearDown(app.dispose);
    await app.initialize();
    expect(await app.setWallet(maya.copy(archived: true)), false);
    await app.setAllowance(
      centavos: 700,
      wallet: Wallet.cash,
      days: [1, 2, 3, 4, 5, 6, 7],
      startDate: '2026-10-01',
      enabled: true,
    );
    expect(app.ledger.total(EntryKind.income), 10001);
    now = DateTime(2026, 10, 2);
    await app.recordAllowances();
    expect(app.ledger.calculate(Wallet.cash).income, 700);
    expect(await app.setWallet(maya.copy(archived: true)), true);
  });
  test(
    'long gaps pause and imported schedules are paused for explicit review',
    () {
      final result = catchUpAllowance(
        custom().copy(allowance: schedule()),
        DateTime(2026, 11, 5),
      );
      expect(result.paused, true);
      expect(result.ledger.entries, isEmpty);
      expect(result.ledger.allowance!.enabled, false);
      final imported = catchUpAllowance(
        custom().copy(allowance: schedule()),
        DateTime(2026, 10, 1),
      ).ledger;
      final preview = previewRestore(Ledger.empty(), imported);
      expect(preview.ledger.allowance!.enabled, false);
      expect(preview.ledger.entries.length, 1);
      expect(
        () => previewRestore(
          imported,
          imported.copy(allowance: imported.allowance!.copy(centavos: 42)),
        ),
        throwsA(isA<LedgerException>()),
      );
    },
  );
  test(
    'allowance schema rejects malformed rules and occurrence identities',
    () {
      final l = catchUpAllowance(
        custom().copy(allowance: schedule()),
        DateTime(2026, 10, 1),
      ).ledger;
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => m['allowance']['days'] = [1, 1],
        (m) => m['allowance']['days'] = [0],
        (m) => m['allowance']['centavos'] = 1.0,
        (m) => m['allowance']['wallet'] = 'missing',
        (m) => m['entries'][0]['occurrenceDate'] = '2026-02-30',
        (m) => m['entries'][0]['scheduleId'] = 'unknown',
      ]) {
        final m = l.toJson();
        mutate(m);
        expect(
          () => Ledger.decode(jsonEncode(m)),
          throwsA(isA<LedgerException>()),
        );
      }
    },
  );
}
