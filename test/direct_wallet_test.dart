import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/entry_page.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show synthetic, fixture, configure, capture, loadFonts;

Ledger many({bool all = false, bool archived = true}) {
  final wallets = [
    ...Wallet.values,
    for (var i = 2; i < 20; i++)
      Wallet(
        id: 'wallet_$i',
        label: i == 2 ? 'MariBank' : 'Wallet $i',
        icon: 'bank',
        color: 'green',
        archived: archived && i == 19,
      ),
  ];
  return synthetic().copy(
    wallets: wallets,
    openings: {for (final w in wallets) w: 0},
    preferences: synthetic().preferences.copy(
      quickWallets: all
          ? wallets.where((w) => !w.archived).map((w) => w.id).toList()
          : ['gcash', 'cash'],
    ),
  );
}

void main() {
  setUpAll(loadFonts);
  test('schema 3 preserves pins, financial records and private preview on migration', () {
    final old = many().toJson()..['schemaVersion'] = 3;
    for (final w in old['wallets'] as List) {
      (w as Map).remove('removed');
    }
    final migrated = Ledger.decode(jsonEncode(old));
    expect(migrated.preferences.quickWallets, ['gcash', 'cash']);
    expect(migrated.preferences.privatePreview, true);
    expect(migrated.toJson()['schemaVersion'], schemaVersion);
    expect(migrated.toJson()['entries'], old['entries']);
    expect(migrated.wallets.every((w) => !w.removed), true);
  });
  test(
    'twenty selections, empty, order and repeated toggles survive disk restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pocket-direct-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileLedgerStore(directory);
      final original = many(archived: false);
      await store.save(original);
      final app = AppController(store: store);
      addTearDown(app.dispose);
      await app.initialize();
      final ids = original.wallets.map((w) => w.id).toList().reversed.toList();
      expect(await app.setQuickWallets(ids), true);
      expect((await store.load()).ledger.preferences.quickWallets, ids);
      for (var i = 0; i < 6; i++) {
        expect(await app.setQuickWallets(i.isEven ? [] : ids), true);
      }
      expect(await app.setQuickWallets([]), true);
      final after = (await store.load()).ledger;
      expect(after.quickWallets, isEmpty);
      expect(after.toJson()['entries'], original.toJson()['entries']);
      expect(after.toJson()['openings'], original.toJson()['openings']);
      expect(after.toJson()['changes'], original.toJson()['changes']);
    },
  );
  test('invalid or archived selection and failed write leave previous preferences intact', () async {
    final store = MemoryLedgerStore(many());
    final app = AppController(store: store);
    addTearDown(app.dispose);
    await app.initialize();
    for (final ids in [
      ['cash', 'cash'],
      ['wallet_19'],
      ['missing'],
    ]) {
      expect(await app.setQuickWallets(ids), false);
    }
    store.failWrites = true;
    expect(await app.setQuickWallets([]), false);
    expect(app.ledger.preferences.quickWallets, ['gcash', 'cash']);
  });
  test('unused removal is recoverable; linked deletion archives without changing money', () async {
    final app = fixture(many());
    addTearDown(app.dispose);
    final original = app.ledger;
    final unused = app.ledger.wallets[2];
    expect(await app.removeWallet(unused), true);
    expect(app.ledger.wallet(unused)!.removed, true);
    expect(app.ledger.availableWallets.contains(unused), false);
    expect(await app.restoreWallet(unused), true);
    expect(app.ledger.wallet(unused)!.removed, false);
    expect(await app.removeWallet(Wallet.gcash), true);
    expect(app.ledger.wallet(Wallet.gcash)!.archived, true);
    expect(app.ledger.wallet(Wallet.gcash)!.removed, false);
    expect(app.ledger.quickWallets.contains(Wallet.gcash), false);
    expect(
      app.ledger.calculate(Wallet.gcash).balance,
      original.calculate(Wallet.gcash).balance,
    );
    expect(app.ledger.toJson()['entries'], original.toJson()['entries']);
    expect(await app.restoreWallet(Wallet.gcash), true);
    expect(app.ledger.quickWallets.contains(Wallet.gcash), false);
    expect(
      Ledger.decode(app.ledger.encode()).wallet(Wallet.gcash)!.archived,
      false,
    );
  });
  test(
    'removing last active wallet persists and rejects stale new transaction',
    () async {
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      expect(await app.removeWallet(Wallet.cash), true);
      expect(await app.removeWallet(Wallet.gcash), true);
      expect(Ledger.decode(app.ledger.encode()).availableWallets, isEmpty);
      app.startDraft(categoryId: 'food');
      app.draft!.amount = '1';
      expect(await app.saveDraft(Wallet.gcash), false);
      expect(app.ledger.entries, isEmpty);
      expect(await app.restoreWallet(Wallet.cash), true);
      expect(await app.saveDraft(Wallet.cash), true);
    },
  );
  test('allowance removal requires explicit pause, commits atomically, never reroutes or resumes on restore', () async {
    final rule = AllowanceSchedule(
      id: 'test_schedule',
      centavos: 100,
      wallet: Wallet.gcash,
      days: [1, 2, 3, 4, 5, 6, 7],
      startDate: '2026-10-12',
      processedThrough: '2026-10-12',
      enabled: true,
    );
    final store = MemoryLedgerStore(
      synthetic(populated: false).copy(allowance: rule),
    );
    final app = AppController(
      store: store,
      clock: () => DateTime(2026, 10, 12),
    );
    addTearDown(app.dispose);
    await app.initialize();
    expect(await app.removeWallet(Wallet.gcash), false);
    store.failWrites = true;
    expect(await app.removeWallet(Wallet.gcash, pauseAllowance: true), false);
    expect(app.ledger.allowance!.enabled, true);
    expect(app.ledger.wallet(Wallet.gcash)!.archived, false);
    store.failWrites = false;
    expect(await app.removeWallet(Wallet.gcash, pauseAllowance: true), true);
    expect(app.ledger.allowance!.enabled, false);
    expect(app.ledger.allowance!.wallet, Wallet.gcash);
    expect(catchUpAllowance(app.ledger, DateTime(2026, 10, 13)).count, 0);
    expect(await app.restoreWallet(Wallet.gcash), true);
    expect(app.ledger.allowance!.enabled, false);
    expect(app.ledger.entries, isEmpty);
  });
  test('opening balances and deleted transaction references retain archive semantics', () async {
    final app = fixture(
      synthetic(populated: false)
          .copy(openings: {Wallet.cash: 100, Wallet.gcash: 0}),
    );
    addTearDown(app.dispose);
    await app.removeWallet(Wallet.cash);
    expect(app.ledger.wallet(Wallet.cash)!.removed, false);
    expect(app.ledger.calculate(Wallet.cash).balance, 100);
    await app.restoreWallet(Wallet.cash);
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '0.01';
    await app.saveDraft(Wallet.cash);
    await app.delete(app.ledger.active.single);
    await app.removeWallet(Wallet.cash);
    expect(app.ledger.wallet(Wallet.cash)!.removed, false);
    expect(app.ledger.changes, isNotEmpty);
  });
  testWidgets('central bulk controls, order, repeated toggles and semantics', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(many());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: DirectEntryButtonsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    await tester.tap(find.byKey(const ValueKey('select-all-wallets')));
    await tester.pumpAndSettle();
    expect(app.ledger.quickWallets.length, 19);
    expect(app.ledger.quickWallets.any((w) => w.id == 'wallet_19'), false);
    await tester.tap(find.byKey(const ValueKey('direct-down-gcash')));
    await tester.pumpAndSettle();
    expect(app.ledger.quickWallets.first, Wallet.cash);
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(
        find.byKey(const ValueKey('direct-toggle-cash')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('direct-toggle-cash')));
      await tester.pumpAndSettle();
    }
    expect(app.ledger.preferences.quickWallets.toSet().length, 19);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('clear-direct-wallets')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-direct-wallets')));
    await tester.pumpAndSettle();
    expect(app.ledger.quickWallets, isEmpty);
    expect(
      tester.getSize(find.byKey(const ValueKey('select-all-wallets'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets(
    'wallet pages expose every selected wallet, overflow and settings preserve draft',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(many(all: true));
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'food');
      app.draft!.amount = '1.23';
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: EntryPage(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 20 &&
            find
                .byKey(const ValueKey('save-wallet_18'))
                .hitTestable()
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.tap(find.byKey(const ValueKey('next-direct-wallets')));
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('save-wallet_18')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('more-wallets')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('wallet-choice-wallet_19')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('manage-direct-buttons')));
      await tester.pumpAndSettle();
      expect(find.byType(DirectEntryButtonsPage), findsOneWidget);
      expect(app.draft!.amount, '1.23');
      expect(app.ledger.entries.length, 5);
      await tester.ensureVisible(
        find.byKey(const ValueKey('clear-direct-wallets')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-direct-wallets')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('choose-save-wallet')), findsOneWidget);
      expect(app.draft!.amount, '1.23');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'removal confirmation cancellation and hidden-wallet restore are explicit',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: WalletsPage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove wallet').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.ledger.wallet(Wallet.cash)!.archived, false);
      await tester.tap(find.text('Remove wallet').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CupertinoDialogAction, 'Remove wallet'),
      );
      await tester.pumpAndSettle();
      expect(app.ledger.wallet(Wallet.cash)!.removed, true);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: HiddenWalletsPage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-wallet-cash')));
      await tester.pumpAndSettle();
      expect(app.ledger.wallet(Wallet.cash)!.archived, false);
    },
  );
  testWidgets(
    'detail short values share trailing edge; long values and note wrap',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic());
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: EntryDetailPage(app: app, id: 'fixture_lunch'),
        ),
      );
      await tester.pumpAndSettle();
      final rects = [
        for (final label in ['Date', 'Category', 'Paid with'])
          tester.getRect(find.byKey(ValueKey('entry-fact-$label'))),
      ];
      expect(rects.map((r) => r.right).toSet().length, 1);
      expect(find.text('Lunch after class'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'damaged-ledger recovery pauses imported allowance and keeps private previews',
    (tester) async {
      configure(tester, const Size(390, 844));
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'ponpon-recovery-test',
        );
        await File('${directory.path}/ledger.json')
            .writeAsString('broken synthetic data');
      });
      final imported = synthetic(populated: false).copy(
        allowance: AllowanceSchedule(
          id: 'recovery_rule',
          centavos: 100,
          wallet: Wallet.gcash,
          days: [1, 2, 3, 4, 5, 6, 7],
          startDate: '2026-10-12',
          processedThrough: '2026-10-11',
          enabled: true,
        ),
      );
      final appearance = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, (call) async {
            if (call.method == 'privatePath') return directory.path;
            if (call.method == 'pickBackup') return imported.encode();
            if (call.method == 'syncAppearance') {
              appearance.add(call.arguments as Map<dynamic, dynamic>);
            }
            return null;
          });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null);
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(const BootstrapApp());
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 40 && find.text('Restore a backup').evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.tap(find.text('Restore a backup'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CupertinoDialogAction, 'Restore backup'),
      );
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 80 && find.byType(PocketApp).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
        final saved = (await FileLedgerStore(directory).load()).ledger;
        expect(saved.allowance!.enabled, false);
        expect(saved.allowance!.id, imported.allowance!.id);
        expect(saved.entries, isEmpty);
        expect(
          await File('${directory.path}/ledger.unreadable.json').readAsString(),
          'broken synthetic data',
        );
      });
      expect(appearance.last['privatePreview'], true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final item
      in <String, ({String page, Size size, double scale, String theme})>{
        'direct-buttons-light': (
          page: 'manager',
          size: const Size(390, 844),
          scale: 1,
          theme: 'light',
        ),
        'direct-buttons-dark': (
          page: 'manager',
          size: const Size(390, 844),
          scale: 1,
          theme: 'dark',
        ),
        'direct-buttons-large-type': (
          page: 'manager',
          size: const Size(360, 640),
          scale: 1.5,
          theme: 'light',
        ),
        'direct-many-entry': (
          page: 'entry',
          size: const Size(390, 844),
          scale: 1,
          theme: 'light',
        ),
        'direct-many-landscape': (
          page: 'entry',
          size: const Size(844, 390),
          scale: 1,
          theme: 'light',
        ),
        'direct-many-large-type': (
          page: 'entry',
          size: const Size(360, 640),
          scale: 1.5,
          theme: 'light',
        ),
        'direct-empty-entry': (
          page: 'empty',
          size: const Size(390, 844),
          scale: 1,
          theme: 'light',
        ),
        'hidden-wallets-light': (
          page: 'hidden',
          size: const Size(390, 844),
          scale: 1,
          theme: 'light',
        ),
        'no-active-wallets': (
          page: 'no-wallet',
          size: const Size(390, 844),
          scale: 1,
          theme: 'light',
        ),
        'detail-long-large-type': (
          page: 'detail',
          size: const Size(360, 640),
          scale: 1.5,
          theme: 'light',
        ),
        'detail-dark': (
          page: 'detail-normal',
          size: const Size(390, 844),
          scale: 1,
          theme: 'dark',
        ),
      }.entries) {
    testWidgets('render ${item.key}', (tester) async {
      final c = item.value;
      configure(tester, c.size, scale: c.scale);
      var ledger = many(all: true)
          .copy(preferences: many(all: true).preferences.copy(theme: c.theme));
      if (c.page == 'detail') {
        ledger = ledger.copy(
          categories: [
            for (final cat in ledger.categories)
              cat.id == 'food'
                  ? cat.copy(name: 'Meals and groceries for family')
                  : cat,
          ],
        );
      }
      final app = fixture(ledger);
      addTearDown(app.dispose);
      if (c.page == 'hidden' || c.page == 'no-wallet') {
        for (final wallet
            in c.page == 'hidden'
                ? [Wallet.gcash, ledger.wallets[2]]
                : [...ledger.availableWallets]) {
          await app.removeWallet(wallet);
        }
      }
      if (c.page == 'empty') await app.setQuickWallets([]);
      Widget page = DirectEntryButtonsPage(app: app);
      if (['entry', 'empty', 'no-wallet'].contains(c.page)) {
        app.startDraft(categoryId: 'food');
        app.draft!.amount = '148.50';
        page = EntryPage(controller: app);
      }
      if (c.page == 'hidden') page = HiddenWalletsPage(app: app);
      if (c.page.startsWith('detail')) {
        page = EntryDetailPage(app: app, id: 'fixture_lunch');
      }
      app.feedback = null;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(controller: app, testHome: page),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (c.page == 'entry') {
        expect(
          tester.getRect(find.byKey(const ValueKey('entry-date'))).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('Food').first).top + 12),
        );
        if (c.scale > 1.25) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('next-direct-wallets')),
          );
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .getRect(
                find.byKey(
                  ValueKey(
                    c.size.width > c.size.height
                        ? 'more-wallets'
                        : 'next-direct-wallets',
                  ),
                ),
              )
              .bottom,
          lessThanOrEqualTo(c.size.height - 24),
        );
      }
      await capture(tester, key, item.key);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
