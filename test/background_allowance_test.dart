import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/background_allowance.dart';
import 'package:pocket_entry/data/coordinated_store.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart' show allowanceBackground;

Ledger scheduled() => Ledger.empty().copy(
  preferences: const Preferences(
    welcomed: true,
    haptics: false,
    visualStyle: VisualStyle.powderBlue,
  ),
  allowance: AllowanceSchedule(
    id: 'background',
    centavos: 1000,
    wallet: Wallet.cash,
    days: [1, 2, 3, 4, 5, 6, 7],
    startDate: '2026-10-12',
    processedThrough: '2026-10-11',
    enabled: true,
  ),
);
Entry expense() => const Entry(
  id: 'foreground_expense',
  kind: EntryKind.expense,
  centavos: 500,
  date: '2026-10-14',
  wallet: Wallet.cash,
  categoryId: 'food',
  note: 'Synthetic',
  createdAt: 1,
  updatedAt: 1,
);

class DiskFake {
  DiskFake(Ledger ledger) : current = ledger.encode();
  String? current, previous;
  int version = 0, writes = 0;
  bool fail = false;
  Future<void> Function()? beforeSave;
  Ledger get ledger => Ledger.decode(current!);
  void replace(Ledger value) {
    previous = current;
    current = value.encode();
    version++;
  }

  Future<dynamic> handle(MethodCall call) async {
    switch (call.method) {
      case 'privatePath':
        return Directory.systemTemp.path;
      case 'snapshot':
        return {
          'revision': '$version',
          'currentPresent': current != null,
          'previousPresent': previous != null,
          'current': current == null
              ? null
              : Uint8List.fromList(utf8.encode(current!)),
          'previous': previous == null
              ? null
              : Uint8List.fromList(utf8.encode(previous!)),
        };
      case 'save':
        final args = call.arguments as Map;
        final hook = beforeSave;
        beforeSave = null;
        await hook?.call();
        if (args['expectedRevision'] != '$version') {
          throw PlatformException(code: 'conflict');
        }
        if (fail) throw PlatformException(code: 'storage');
        replace(Ledger.decode(args['encoded'] as String));
        writes++;
        return '$version';
      case 'syncSnapshot':
        if ((call.arguments as Map)['ledgerRevision'] != '$version') {
          throw PlatformException(code: 'conflict');
        }
        return null;
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DiskFake disk;
  late Directory directory;
  CoordinatedLedgerStore store() => CoordinatedLedgerStore(directory);
  Future<bool> run({DateTime? now}) => processBackgroundAllowance(
    store(),
    clock: () => now ?? DateTime(2026, 10, 14),
  );
  setUp(() {
    directory = Directory.systemTemp.createTempSync('ponpon-bg-test-');
    disk = DiskFake(scheduled());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CoordinatedLedgerStore.channel, disk.handle);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CoordinatedLedgerStore.channel, null);
    directory.deleteSync(recursive: true);
  });
  test('Actual headless entry point initializes, processes and acknowledges completion', () async {
    const completion = MethodChannel('dev.giann.pocket_entry/allowance_job');
    Map? completed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(completion, (call) async {
          expect(call.method, 'complete');
          completed = call.arguments as Map;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(completion, null),
    );
    // No due history assumption: current test machine date may be >31 days.
    disk.replace(
      disk.ledger.copy(allowance: disk.ledger.allowance!.copy(enabled: false)),
    );
    await allowanceBackground();
    expect(completed, {'success': true});
    expect(disk.ledger.active, isEmpty);
  });
  test('Missed days use intended dates, fixed wallet and survive restart/duplicate wakes', () async {
    expect(await run(), true);
    expect(
      disk.ledger.active.map((e) => e.date),
      unorderedEquals(['2026-10-12', '2026-10-13', '2026-10-14']),
    );
    expect(
      disk.ledger.active.every(
        (e) => e.wallet == Wallet.cash && e.categoryId == 'income_allowance',
      ),
      true,
    );
    expect(disk.ledger.calculate(Wallet.cash).balance, 3000);
    final before = disk.current;
    expect(await run(), true);
    expect(disk.current, before);
    expect((await store().load()).ledger.encode(), before);
    expect(disk.ledger.preferences.visualStyle, VisualStyle.powderBlue);
  });
  test('Large existing journal survives worker encoding and background catch-up exactly', () async {
    final history = List.generate(
      2000,
      (i) => Entry(
        id: 'synthetic_$i',
        kind: EntryKind.expense,
        centavos: 1,
        date: '2026-10-10',
        wallet: Wallet.cash,
        categoryId: 'food',
        note: 'Synthetic history',
        createdAt: i + 1,
        updatedAt: i + 1,
      ),
    );
    disk.replace(disk.ledger.copy(entries: history));
    expect(await run(), true);
    final byId = {for (final entry in disk.ledger.entries) entry.id: entry};
    for (final entry in history) {
      expect(byId[entry.id]!.toJson(), entry.toJson());
    }
    expect(disk.ledger.active.length, 2003);
    expect(disk.ledger.calculate(Wallet.cash).balance, 1000);
  });
  test(
    'Two concurrent workers produce one occurrence per scheduled date',
    () async {
      final results = await Future.wait([run(), run()]);
      expect(results.every((r) => r), true);
      expect(disk.ledger.active.length, 3);
      expect(disk.ledger.active.map((e) => e.id).toSet().length, 3);
    },
  );
  test(
    'Background retries fresh foreground record instead of overwriting it',
    () async {
      disk.beforeSave = () async {
        disk.replace(disk.ledger.put(expense()));
      };
      expect(await run(), true);
      expect(disk.ledger.entry('foreground_expense')!.centavos, 500);
      expect(disk.ledger.active.length, 4);
      expect(disk.ledger.calculate(Wallet.cash).balance, 2500);
    },
  );
  test('Foreground conflict preserves draft, refreshes and saves on retry without duplicates', () async {
    final foreground = store();
    final app = AppController(
      store: foreground,
      clock: () => DateTime(2026, 10, 14),
    );
    addTearDown(app.dispose);
    app.ledger = (await foreground.load()).ledger;
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '5';
    disk.beforeSave = () async {
      expect(await run(), true);
    };
    expect(await app.saveDraft(Wallet.cash), false);
    expect(app.draft!.amount, '5');
    expect(app.storageError, contains('Records changed'));
    expect(app.ledger.active.length, 3);
    expect(await app.saveDraft(Wallet.cash), true);
    expect(
      disk.ledger.active.where((e) => e.kind == EntryKind.income).length,
      3,
    );
    expect(
      disk.ledger.active.where((e) => e.kind == EntryKind.expense).length,
      1,
    );
    expect(disk.ledger.calculate(Wallet.cash).balance, 2500);
  });
  test('Disable winning a race prevents stale background allowance', () async {
    disk.beforeSave = () async {
      disk.replace(
        disk.ledger.copy(
          allowance: disk.ledger.allowance!.copy(enabled: false),
        ),
      );
    };
    expect(await run(), true);
    expect(disk.ledger.active, isEmpty);
    expect(disk.ledger.allowance!.enabled, false);
  });
  test(
    'Edited amount and wallet winning a race are re-read before processing',
    () async {
      disk.beforeSave = () async {
        disk.replace(
          disk.ledger.copy(
            allowance: disk.ledger.allowance!.copy(
              centavos: 2300,
              wallet: Wallet.gcash,
            ),
          ),
        );
      };
      expect(await run(), true);
      expect(
        disk.ledger.active.every(
          (e) => e.wallet == Wallet.gcash && e.centavos == 2300,
        ),
        true,
      );
      expect(disk.ledger.calculate(Wallet.cash).balance, 0);
      expect(disk.ledger.calculate(Wallet.gcash).balance, 6900);
    },
  );
  test('Interrupted save leaves old cursor and records intact; retry is idempotent', () async {
    final before = disk.current;
    disk.fail = true;
    expect(await run(), false);
    expect(disk.current, before);
    disk.fail = false;
    expect(await run(), true);
    expect(await run(), true);
    expect(disk.ledger.active.length, 3);
  });
  test('Date rollback does not rewind cursor; over-31-day gap pauses without receipts', () async {
    expect(await run(), true);
    final before = disk.current;
    expect(await run(now: DateTime(2026, 10, 11)), true);
    expect(disk.current, before);
    expect(await run(now: DateTime(2026, 12, 1)), true);
    expect(disk.ledger.allowance!.enabled, false);
    expect(disk.ledger.active.length, 3);
    expect(
      disk.ledger.active.map((e) => e.toJson()),
      Ledger.decode(before!).active.map((e) => e.toJson()),
    );
  });
  test('Archived wallet fails closed with no rerouting, cursor change or entry writes', () async {
    disk.replace(
      disk.ledger.copy(
        wallets: [Wallet.cash.copy(archived: true), Wallet.gcash],
      ),
    );
    final before = disk.current;
    expect(await run(), false);
    expect(disk.current, before);
  });
  test('Disabled schedule and future start do not create receipts', () async {
    disk.replace(
      disk.ledger.copy(allowance: disk.ledger.allowance!.copy(enabled: false)),
    );
    final before = disk.current;
    expect(await run(), true);
    expect(disk.current, before);
    disk.replace(
      disk.ledger.copy(
        allowance: disk.ledger.allowance!.copy(
          enabled: true,
          startDate: '2026-11-01',
        ),
      ),
    );
    final future = disk.current;
    expect(await run(), true);
    expect(disk.current, future);
  });
  test(
    'Deleted occurrence is not silently recreated after duplicate processing',
    () async {
      expect(await run(), true);
      final old = disk.ledger;
      final id = old.active.first.id;
      disk.replace(
        old
            .delete(id, 999999)
            .copy(
              allowance: old.allowance!.copy(processedThrough: '2026-10-11'),
            ),
      );
      expect(await run(), true);
      expect(disk.ledger.entry(id)!.deleted, true);
      expect(disk.ledger.active.length, 2);
    },
  );
  test('Recovered previous file requires review; unattended worker never replaces damage', () async {
    disk.previous = disk.current;
    disk.current = 'damaged';
    final before = disk.current;
    expect(await run(), false);
    expect(disk.current, before);
  });
  test('Unreadable data blocks normal saves but explicit recovery preserves expected revision guard', () async {
    disk.current = 'damaged';
    disk.previous = 'also damaged';
    final reader = store();
    await expectLater(reader.load(), throwsA(isA<LedgerException>()));
    await expectLater(
      reader.save(scheduled()),
      throwsA(isA<LedgerException>()),
    );
    expect(disk.current, 'damaged');
    await reader.recover(scheduled());
    expect(disk.ledger.active, isEmpty);
  });
  test('External receipts invalidate an older toast Undo without changing earlier entries', () async {
    final foreground = store();
    final app = AppController(
      store: foreground,
      clock: () => DateTime(2026, 10, 14),
    );
    addTearDown(app.dispose);
    app.ledger = (await foreground.load()).ledger;
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '5';
    expect(await app.saveDraft(Wallet.cash), true);
    expect(app.feedbackUndo, true);
    final expense = app.ledger.active.single;
    expect(await run(), true);
    await app.refreshFromStorage();
    expect(app.feedbackUndo, false);
    expect(app.feedback, isNull);
    expect(app.ledger.entry(expense.id)!.toJson(), expense.toJson());
    expect(app.ledger.active.length, 4);
  });
  test('Background refresh keeps an unfinished draft and updated financial records', () async {
    final foreground = store();
    final app = AppController(
      store: foreground,
      clock: () => DateTime(2026, 10, 14),
    );
    addTearDown(app.dispose);
    app.ledger = (await foreground.load()).ledger;
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '12';
    expect(await run(), true);
    await app.refreshFromStorage();
    expect(app.draft!.amount, '12');
    expect(app.ledger.active.length, 3);
    await app.reconcileOnResume();
    expect(disk.ledger.active.length, 3);
  });
}
