import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/entry_page.dart';
import 'package:pocket_entry/ui/design.dart';

import 'ui_test.dart' show synthetic, fixture, configure, capture, loadFonts;

void main() {
  setUpAll(loadFonts);
  test(
    'Income choices are typed and older ledgers get lazy built-ins',
    () async {
      final old = synthetic().copy(
        categories: [
          ...defaultCategories
              .where((c) => !c.id.startsWith('income_'))
              .map((c) => c.id == 'income' ? c.copy(name: 'Income') : c),
          const Category(id: 'freelance', name: 'Freelance', icon: 'income'),
        ],
      );
      final loaded = Ledger.decode(old.encode());
      expect(
        loaded.categories.map((c) => c.toJson()),
        old.categories.map((c) => c.toJson()),
      );
      expect(loaded.categoriesFor(EntryKind.income).map((c) => c.name), [
        'General income',
        'Allowance',
        'Salary',
        'Gift',
        'Other income',
        'Freelance',
      ]);
      expect(
        loaded.categoriesFor(EntryKind.expense).any((c) => c.isIncome),
        isFalse,
      );
      final app = fixture(loaded);
      addTearDown(app.dispose);
      final before = loaded.entries.map((e) => e.toJson()).toList();
      app.startDraft(categoryId: 'food');
      app.changeDraftKind(EntryKind.income);
      expect(app.draft!.categoryId, 'income');
      expect(app.ledger.encode(), loaded.encode());
      app.draft!
        ..amount = '500'
        ..categoryId = 'income_salary';
      expect(await app.saveDraft(Wallet.gcash), isTrue);
      expect(app.ledger.category('income_salary')!.name, 'Salary');
      expect(
        app.ledger.entries.take(before.length).map((e) => e.toJson()),
        before,
      );
      final saved = app.ledger.entries.last;
      expect(saved.kind, EntryKind.income);
      expect(saved.wallet, Wallet.gcash);
      expect(saved.categoryId, 'income_salary');
      expect(
        Ledger.decode(app.ledger.encode()).entry(saved.id)!.toJson(),
        saved.toJson(),
      );
      expect(await app.undo(), isTrue);
      expect(app.ledger.activeWalletBalance, loaded.activeWalletBalance);
    },
  );

  test(
    'Income shortcut infers type and kind changes clear incompatible category',
    () {
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'income_gift');
      expect(app.draft!.kind, EntryKind.income);
      expect(app.draft!.categoryId, 'income_gift');
      app.changeDraftKind(EntryKind.expense);
      expect(app.draft!.categoryId, isNull);
      app.draft!.categoryId = 'bills';
      app.changeDraftKind(EntryKind.transfer);
      expect(app.draft!.categoryId, isNull);
      app.changeDraftKind(EntryKind.income);
      expect(app.draft!.categoryId, 'income');
    },
  );

  test(
    'Legacy income history retains its original category through edit and undo',
    () async {
      final legacy = synthetic(populated: false).put(
        const Entry(
          id: 'old_income',
          kind: EntryKind.income,
          centavos: 10000,
          date: '2026-10-11',
          wallet: Wallet.cash,
          categoryId: 'food',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      final app = fixture(legacy);
      addTearDown(app.dispose);
      app.startDraft(editing: legacy.entry('old_income'));
      app.draft!.amount = '200';
      expect(await app.saveDraft(Wallet.cash), isTrue);
      expect(app.ledger.entry('old_income')!.categoryId, 'food');
      expect(await app.undo(), isTrue);
      expect(
        app.ledger.entry('old_income')!.toJson(),
        legacy.entry('old_income')!.toJson(),
      );
      app.startDraft(editing: legacy.entry('old_income'));
      app.changeDraftKind(EntryKind.expense);
      app.changeDraftKind(EntryKind.income);
      expect(app.draft!.categoryId, 'income');
    },
  );

  test(
    'Saved Salary draft survives restart without becoming General income',
    () async {
      final store = MemoryLedgerStore(synthetic(populated: false));
      await store.saveDraft(
        jsonEncode(
          Draft(
            kind: EntryKind.income,
            categoryId: 'income_salary',
            amount: '250',
            date: '2026-10-12',
          ).toJson(),
        ),
      );
      final app = AppController(
        store: store,
        clock: () => DateTime(2026, 10, 12),
      );
      addTearDown(app.dispose);
      await app.initialize();
      expect(app.draft!.categoryId, 'income_salary');
      expect(app.draft!.amount, '250');
      expect(app.ledger.entries, isEmpty);
    },
  );

  test('Balance visibility defaults hidden, round-trips, and restore keeps local choice', () {
    final current = Ledger.empty();
    final map = current.toJson();
    (map['preferences'] as Map).remove('balanceWidgetVisible');
    expect(
      Ledger.decode(jsonEncode(map)).preferences.balanceWidgetVisible,
      isFalse,
    );
    final imported = current.copy(
      preferences: current.preferences.copy(balanceWidgetVisible: true),
    );
    expect(
      Ledger.decode(imported.encode()).preferences.balanceWidgetVisible,
      isTrue,
    );
    expect(
      previewRestore(current, imported).ledger.preferences.balanceWidgetVisible,
      isFalse,
    );
  });

  test(
    'Native snapshot totals only active wallets, independent of direct buttons',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null),
      );
      final ledger = synthetic(populated: false).copy(
        wallets: [
          Wallet.cash,
          Wallet.gcash.copy(archived: true),
          const Wallet(
            id: 'maya',
            label: 'Maya',
            icon: 'wallet',
            color: 'green',
          ),
        ],
        openings: {
          Wallet.cash: -12345,
          Wallet.gcash: 90000,
          Wallet.reference('maya'): 22345,
        },
        preferences: synthetic().preferences.copy(
          quickWallets: [],
          balanceWidgetVisible: true,
          widgetCategories: ['food', 'travel', 'bills', 'income'],
        ),
      );
      await const NativeBridge().sync(ledger);
      final data = calls.single.arguments as Map;
      expect(data['balanceCentavos'], 10000);
      expect(data['activeWalletCount'], 2);
      expect(data['balanceWidgetVisible'], isTrue);
      expect(
        (data['wideCategories'] as List)
            .map((row) => (row as Map)['id'])
            .toList(),
        ['food', 'travel', 'bills', 'income'],
      );
      expect(
        (data['wideCategories'] as List)
            .map((row) => (row as Map)['kind'])
            .toList(),
        ['expense', 'expense', 'expense', 'income'],
      );
      expect(
        (data['wideCategories'] as List)
            .map((row) => (row as Map)['icon'])
            .toList(),
        ['food', 'travel', 'bills', 'income'],
      );
      expect(
        (data['wideCategories'] as List).map((row) => (row as Map)['id']),
        (data['categories'] as List).map((row) => (row as Map)['id']),
      );
      expect(data.containsKey('wallet'), isFalse);
      expect(data.containsKey('entries'), isFalse);
    },
  );

  testWidgets(
    'Income automatically selects General income and saves with one explicit wallet tap',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an entry').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(EntryPage),
          matching: find.text('Food'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('entry-kind-income')));
      await tester.pumpAndSettle();
      expect(app.draft!.categoryId, 'income');
      expect(
        find.bySemanticsLabel('General income category, selected'),
        findsOneWidget,
      );
      for (final name in ['Food', 'Bills', 'Travel']) {
        expect(
          find.descendant(
            of: find.byType(EntryPage),
            matching: find.text(name),
          ),
          findsNothing,
        );
      }
      await tester.tap(find.bySemanticsLabel('All categories'));
      await tester.pumpAndSettle();
      for (final name in [
        'General income',
        'Allowance',
        'Salary',
        'Gift',
        'Other income',
      ]) {
        expect(find.text(name), findsWidgets);
      }
      expect(
        find.descendant(
          of: find.byType(SheetFrame),
          matching: find.text('Food'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Salary').last);
      await tester.pumpAndSettle();
      expect(app.draft!.categoryId, 'income_salary');
      await tester.tap(find.byKey(const ValueKey('entry-kind-expense')));
      await tester.pumpAndSettle();
      expect(app.draft!.categoryId, isNull);
      expect(find.bySemanticsLabel('General income category'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('entry-kind-income')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('key-5')));
      expect(app.ledger.entries, isEmpty);
      await tester.tap(find.byKey(const ValueKey('save-gcash')));
      await tester.pumpAndSettle();
      expect(app.ledger.entries.single.kind, EntryKind.income);
      expect(app.ledger.entries.single.categoryId, 'income');
      expect(app.ledger.entries.single.wallet, Wallet.gcash);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final c in [
    (
      name: 'income-default-light-023',
      size: const Size(390, 844),
      scale: 1.0,
      theme: 'light',
      picker: false,
    ),
    (
      name: 'income-default-dark-023',
      size: const Size(390, 844),
      scale: 1.0,
      theme: 'dark',
      picker: false,
    ),
    (
      name: 'income-default-large-023',
      size: const Size(360, 640),
      scale: 1.5,
      theme: 'light',
      picker: false,
    ),
    (
      name: 'income-categories-023',
      size: const Size(390, 844),
      scale: 1.0,
      theme: 'light',
      picker: true,
    ),
    (
      name: 'income-landscape-023',
      size: const Size(844, 390),
      scale: 1.0,
      theme: 'light',
      picker: false,
    ),
  ]) {
    testWidgets('render ${c.name}', (tester) async {
      configure(tester, c.size, scale: c.scale);
      final app = fixture(synthetic(theme: c.theme, populated: false));
      addTearDown(app.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(
            controller: app,
            initialEntry: const {'categoryId': 'food'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('entry-kind-income')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('key-5')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.pumpAndSettle();
      if (c.picker) {
        await tester.tap(find.bySemanticsLabel('All categories'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await capture(tester, key, c.name);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
