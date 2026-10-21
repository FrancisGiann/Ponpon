import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show synthetic, fixture, configure, capture, loadFonts;
import 'direct_wallet_test.dart' show many;

void main() {
  setUpAll(loadFonts);
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'Home stably puts positive and negative wallets before zero at $scale type',
      (tester) async {
        configure(tester, const Size(390, 844), scale: scale);
        const maya = Wallet(
          id: 'maya',
          label: 'Maya',
          icon: 'wallet',
          color: 'green',
        );
        final ledger = synthetic(populated: false).copy(
          wallets: [Wallet.cash, Wallet.gcash, maya],
          openings: {Wallet.cash: 0, Wallet.gcash: -5000, maya: 10000},
          preferences: synthetic().preferences.copy(
            quickWallets: ['cash', 'maya', 'gcash'],
          ),
        );
        final app = fixture(ledger);
        addTearDown(app.dispose);
        final before = app.ledger.encode();
        final proof = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: proof,
            child: PocketApp(controller: app),
          ),
        );
        await tester.pumpAndSettle();
        final gcash = tester.getRect(
          find.byKey(const ValueKey('home-wallet-gcash')),
        );
        final mayarow = tester.getRect(
          find.byKey(const ValueKey('home-wallet-maya')),
        );
        final cash = tester.getRect(
          find.byKey(const ValueKey('home-wallet-cash')),
        );
        expect(gcash.top, lessThan(mayarow.top));
        expect(mayarow.top, lessThan(cash.top));
        expect(find.text('₱50.00'), findsWidgets);
        expect(app.ledger.wallets.map((w) => w.id), ['cash', 'gcash', 'maya']);
        expect(app.ledger.quickWallets.map((w) => w.id), [
          'cash',
          'maya',
          'gcash',
        ]);
        expect(app.ledger.encode(), before);
        await capture(
          tester,
          proof,
          scale == 1
              ? 'home-three-wallets-023'
              : 'home-three-wallets-large-023',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Home uses selected income shortcuts with income entry type', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final base = synthetic(populated: false);
    final app = fixture(
      base.copy(
        preferences: base.preferences.copy(widgetCategories: ['income_salary']),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('quick-category-income_salary')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('quick-category-income_salary')),
    );
    await tester.pumpAndSettle();
    expect(app.draft!.kind, EntryKind.income);
    expect(app.draft!.categoryId, 'income_salary');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Manage works with an empty selection and saves the shared scope',
    (tester) async {
      configure(tester, const Size(390, 844));
      final base = synthetic(populated: false);
      final app = fixture(
        base.copy(preferences: base.preferences.copy(widgetCategories: [])),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      expect(find.text('Quick categories'), findsOneWidget);
      expect(
        find.textContaining('Choose up to four in Manage'),
        findsOneWidget,
      );
      final manage = find.bySemanticsLabel('Manage quick categories');
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      final categoriesScroll = find
          .descendant(
            of: find.byType(CategoriesPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final scope = find.textContaining('for Today and home-screen widgets');
      await tester.scrollUntilVisible(
        scope,
        300,
        scrollable: categoriesScroll,
      );
      expect(
        scope,
        findsOneWidget,
      );
      final food = find.bySemanticsLabel('Food as a quick category');
      await tester.scrollUntilVisible(
        food,
        300,
        scrollable: categoriesScroll,
      );
      await tester.tap(food);
      await tester.pumpAndSettle();
      expect(app.ledger.preferences.widgetCategories, ['food']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-category-food')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('New category creation offers Income and keeps that type', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic(populated: false));
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    final manage = find.bySemanticsLabel('Manage quick categories');
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Create category'));
    await tester.pumpAndSettle();
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).last, 'Side work');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final created = app.ledger.categories.singleWhere(
      (category) => category.name == 'Side work',
    );
    expect(created.icon, 'income');
    expect(created.isIncome, isTrue);
    expect(categoryIconsFor(created), ['income']);
    expect(tester.takeException(), isNull);
  });
  test(
    'Archiving hides a quick category but retains its historical ID',
    () async {
      const custom = Category(id: 'custom', name: 'Custom', icon: 'home');
      final base = synthetic(populated: false).copy(
        categories: [...defaultCategories, custom],
        entries: [
          Entry(
            id: 'history_custom',
            kind: EntryKind.expense,
            centavos: 1234,
            date: '2026-10-12',
            wallet: Wallet.cash,
            categoryId: custom.id,
            note: 'Historical note',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
        preferences: synthetic().preferences.copy(
          widgetCategories: ['custom', 'food'],
        ),
      );
      final app = fixture(base);
      addTearDown(app.dispose);
      await app.category(custom.copy(archived: true));
      expect(app.ledger.category(custom.id)!.archived, isTrue);
      expect(app.ledger.entry('history_custom')!.categoryId, custom.id);
      expect(app.ledger.preferences.widgetCategories, ['food']);
      expect(app.ledger.quickCategories.map((c) => c.id), ['food']);
      await app.category(custom.copy(archived: false));
      expect(app.ledger.quickCategories.map((c) => c.id), ['food']);
      expect(app.ledger.preferences.widgetCategories, ['food']);
    },
  );
  testWidgets('More wallets has a counted View all and stable full breakdown', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(
      many(archived: false).copy(preferences: synthetic().preferences),
    );
    addTearDown(app.dispose);
    final preview = tester.ensureSemantics();
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.text('View all'), findsOneWidget);
    expect(find.text('+18 more'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-view-wallets')));
    await tester.pumpAndSettle();
    expect(find.text('Your wallets'), findsOneWidget);
    expect(find.byType(HomeWalletBalanceRow), findsNWidgets(22));
    expect(tester.takeException(), isNull);
    preview.dispose();
  });
  testWidgets(
    'Home leads with scoped total and wallet balances before recording',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic());
      addTearDown(app.dispose);
      final before = app.ledger.encode();
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      final total = tester.getRect(
        find.byKey(const ValueKey('home-total-balance')),
      );
      final action = tester.getRect(find.text('Add an entry').first);
      expect(
        (tester.widget(
          find.byKey(const ValueKey('home-total-balance')),
        ) as Text).data,
        '₱6,327.50',
      );
      expect(total.bottom, lessThan(action.top));
      expect(
        tester.getRect(find.byKey(const ValueKey('home-wallet-gcash'))).bottom,
        lessThan(action.top),
      );
      expect(find.text('Active wallets · manual records'), findsOneWidget);
      expect(app.ledger.encode(), before);
    },
  );
  testWidgets(
    'Direct selection does not hide balances; breakdown exposes all active wallets',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(
        many(archived: false)
            .copy(preferences: synthetic().preferences.copy(quickWallets: [])),
      );
      addTearDown(app.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-wallet-cash')), findsOneWidget);
      final before = app.ledger.encode();
      await tester.tap(find.byKey(const ValueKey('home-view-wallets')));
      await tester.pumpAndSettle();
      expect(find.byType(SheetFrame), findsOneWidget);
      final last = find.descendant(
        of: find.byType(SheetFrame),
        matching: find.byKey(const ValueKey('home-wallet-wallet_19')),
      );
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      expect(tester.widget<Press>(last).label, endsWith('Manage wallets.'));
      expect(app.ledger.encode(), before);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.byType(WalletsPage), findsOneWidget);
      expect(app.ledger.encode(), before);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'No active wallets has an honest empty total and a recovery route',
    (tester) async {
      configure(tester, const Size(390, 844));
      final original = synthetic();
      final app = fixture(
        original.copy(
          wallets: [for (final w in original.wallets) w.copy(archived: true)],
          preferences: original.preferences.copy(quickWallets: []),
        ),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      expect(
        (tester.widget(
          find.byKey(const ValueKey('home-total-balance')),
        ) as Text).data,
        '—',
      );
      expect(find.text('No active wallets'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-wallet-cash')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-view-wallets')));
      await tester.pumpAndSettle();
      expect(find.byType(WalletsPage), findsOneWidget);
      expect(app.ledger.entries.length, original.entries.length);
    },
  );
  testWidgets(
    'Balance scope and full long wallet names have accessible readouts',
    (tester) async {
      configure(tester, const Size(360, 640), scale: 1.5);
      final ledger = synthetic(populated: false).copy(
        wallets: [
          Wallet.cash.copy(label: 'Everyday savings and groceries'),
          Wallet.gcash,
        ],
        openings: {Wallet.cash: -12345, Wallet.gcash: 5000},
      );
      final app = fixture(ledger);
      addTearDown(app.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Total tracked balance.*active wallets')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Everyday savings and groceries tracked balance'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('home-view-wallets'))).bottom,
        lessThan(640 - 24),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('home-view-wallets'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  for (final c in [
    (
      name: 'home-after-light',
      size: const Size(390, 844),
      scale: 1.0,
      kind: 'normal',
      theme: 'light',
    ),
    (
      name: 'home-after-dark',
      size: const Size(390, 844),
      scale: 1.0,
      kind: 'normal',
      theme: 'dark',
    ),
    (
      name: 'home-large-type',
      size: const Size(360, 640),
      scale: 1.5,
      kind: 'normal',
      theme: 'light',
    ),
    (
      name: 'home-many-wallets',
      size: const Size(390, 844),
      scale: 1.0,
      kind: 'many',
      theme: 'light',
    ),
    (
      name: 'home-negative',
      size: const Size(390, 844),
      scale: 1.0,
      kind: 'negative',
      theme: 'light',
    ),
    (
      name: 'home-all-hidden',
      size: const Size(390, 844),
      scale: 1.0,
      kind: 'hidden',
      theme: 'light',
    ),
    (
      name: 'home-long-wallet',
      size: const Size(360, 640),
      scale: 1.5,
      kind: 'long',
      theme: 'light',
    ),
    (
      name: 'home-landscape',
      size: const Size(844, 390),
      scale: 1.0,
      kind: 'normal',
      theme: 'light',
    ),
    (
      name: 'home-wallet-breakdown-light',
      size: const Size(390, 844),
      scale: 1.0,
      kind: 'breakdown',
      theme: 'light',
    ),
    (
      name: 'home-wallet-breakdown-dark',
      size: const Size(390, 844),
      scale: 1.0,
      kind: 'breakdown',
      theme: 'dark',
    ),
  ]) {
    testWidgets('render ${c.name}', (tester) async {
      configure(tester, c.size, scale: c.scale);
      var ledger = synthetic(theme: c.theme);
      if (c.kind == 'many') {
        ledger = many(archived: false)
            .copy(preferences: synthetic().preferences);
      }
      if (c.kind == 'negative') {
        ledger = synthetic(populated: false)
            .copy(openings: {Wallet.cash: -150050, Wallet.gcash: 20000});
      }
      if (c.kind == 'long') {
        ledger = synthetic(populated: false).copy(
          wallets: [
            Wallet.cash.copy(label: 'Everyday savings and groceries'),
            Wallet.gcash,
          ],
          openings: {Wallet.cash: 12345678900, Wallet.gcash: 100},
        );
      }
      if (c.kind == 'hidden') {
        ledger = ledger.copy(
          wallets: [for (final w in ledger.wallets) w.copy(archived: true)],
          preferences: ledger.preferences.copy(quickWallets: []),
        );
      }
      final app = fixture(ledger);
      addTearDown(app.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      if (c.kind == 'breakdown') {
        await tester.tap(find.byKey(const ValueKey('home-view-wallets')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await capture(tester, key, c.name);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
