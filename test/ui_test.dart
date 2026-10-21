import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/entry_page.dart';
import 'package:pocket_entry/ui/screens.dart';

Future<void> loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
  final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  await inter.load();
  await icons.load();
}

Ledger synthetic({
  String theme = 'light',
  bool welcomed = true,
  bool populated = true,
  bool reduced = true,
}) {
  var ledger = Ledger.empty().copy(
    preferences: Preferences(
      welcomed: welcomed,
      theme: theme,
      haptics: false,
      reduceMotion: reduced,
    ),
  );
  if (!populated) return ledger;
  ledger = ledger.copy(
    openings: {Wallet.cash: 130000, Wallet.gcash: 320000},
    budgets: {'2026-10': 800000},
  );
  Entry e(
    String id,
    EntryKind kind,
    int cents,
    Wallet wallet,
    String category,
    String note,
    int timestamp, {
    String date = '2026-10-12',
    Wallet? to,
  }) => Entry(
    id: id,
    kind: kind,
    centavos: cents,
    date: date,
    wallet: wallet,
    toWallet: to,
    categoryId: kind == EntryKind.transfer ? null : category,
    note: note,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  ledger = ledger.put(
    e(
      'fixture_lunch',
      EntryKind.expense,
      14850,
      Wallet.cash,
      'food',
      'Lunch after class',
      2000,
    ),
  );
  ledger = ledger.put(
    e(
      'fixture_trip',
      EntryKind.expense,
      2400,
      Wallet.gcash,
      'travel',
      'Ride home',
      3000,
    ),
  );
  ledger = ledger.put(
    e(
      'fixture_bill',
      EntryKind.expense,
      50000,
      Wallet.gcash,
      'bills',
      'Internet share',
      1000,
      date: '2026-10-11',
    ),
  );
  ledger = ledger.put(
    e(
      'fixture_income',
      EntryKind.income,
      250000,
      Wallet.gcash,
      'income',
      'Synthetic allowance',
      500,
      date: '2026-10-01',
    ),
  );
  ledger = ledger.put(
    e(
      'fixture_transfer',
      EntryKind.transfer,
      100000,
      Wallet.gcash,
      '',
      'Cash withdrawal',
      5000,
      to: Wallet.cash,
    ),
  );
  return ledger;
}

AppController fixture(Ledger ledger) {
  final app = AppController(
    store: MemoryLedgerStore(ledger),
    clock: () => DateTime(2026, 10, 12),
  );
  app.ledger = ledger;
  return app;
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('screenshots/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void configure(WidgetTester tester, Size size, {double scale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'Cash and GCash are explicit final actions, with no default wallet',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an entry').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('save-cash')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-gcash')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('key-1')));
      await tester.tap(find.byKey(const ValueKey('key-2')));
      await tester.tap(find.byKey(const ValueKey('save-gcash')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a category before saving.'), findsOneWidget);
      expect(app.ledger.entries, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(EntryPage),
          matching: find.text('Food'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('save-gcash')));
      await tester.pumpAndSettle();
      expect(app.ledger.entries.single.centavos, 1200);
      expect(app.ledger.entries.single.wallet, Wallet.gcash);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.ledger.active, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Android Back and rotation preserve an unfinished draft', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic(populated: false));
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an entry').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('key-8')));
    await tester.tap(find.byKey(const ValueKey('key-5')));
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(app.draft!.amount, '85');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.draft!.amount, '85');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Resume unfinished entry'), findsOneWidget);
    await tester.tap(find.text('Resume unfinished entry'));
    await tester.pumpAndSettle();
    expect(find.text('85'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'shortcut bypasses onboarding and stale category requires an explicit choice',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic(populated: false, welcomed: false));
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          initialEntry: const {'categoryId': 'missing_category'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New entry'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
      expect(app.draft!.categoryId, isNull);
      expect(app.notice, contains('category changed'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('reduced motion eliminates authored page and press transitions', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic(populated: false));
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an entry').first);
    await tester.pump();
    final context = tester.element(find.byType(EntryPage));
    expect(MotionScope.of(context), true);
    expect(ModalRoute.of(context)!.animation!.isCompleted, true);
    for (final scale in tester.widgetList<AnimatedScale>(
      find.byType(AnimatedScale),
    )) {
      expect(scale.duration, Duration.zero);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'keypad semantics and minimum targets stay usable at 360px / large type',
    (tester) async {
      configure(tester, const Size(360, 640), scale: 1.5);
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'travel');
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: EntryPage(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.bySemanticsLabel(RegExp('Paid with Cash')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Delete last digit')), findsWidgets);
      for (final key in ['1', '2', '3', '.', '0', '⌫']) {
        final size = tester.getSize(find.byKey(ValueKey('key-$key')));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('save-gcash'))).height,
        greaterThanOrEqualTo(48),
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('history edit, delete and recovery have working navigation', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic());
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app, initialTab: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsOneWidget);
    await tester.tap(find.text('Edit entry'));
    await tester.pumpAndSettle();
    expect(app.draft!.editingId, 'fixture_lunch');
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('key-⌫')));
    }
    await tester.tap(find.byKey(const ValueKey('key-9')));
    await tester.tap(find.byKey(const ValueKey('save-gcash')));
    await tester.pumpAndSettle();
    expect(app.ledger.entry('fixture_lunch')!.centavos, 900);
    expect(app.ledger.entry('fixture_lunch')!.wallet, Wallet.gcash);
    await tester.tap(find.text('Delete entry').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete entry').last);
    await tester.pumpAndSettle();
    expect(app.ledger.entry('fixture_lunch')!.deleted, true);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.ledger.entry('fixture_lunch')!.deleted, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'category stays visible above keypad with insets and large type',
    (tester) async {
      configure(tester, const Size(360, 640), scale: 1.5);
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'travel');
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: EntryPage(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      final category = find.text('Travel').first;
      expect(
        tester.getRect(category).bottom,
        lessThan(tester.getRect(find.byKey(const ValueKey('key-1'))).top),
      );
      expect(tester.getRect(category).top, greaterThan(24));
      await tester.tap(category);
      expect(app.draft!.categoryId, 'travel');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('settings switches expose labels and 48dp targets', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: SettingsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['Haptics', 'Reduce motion', 'Private app previews']) {
      final finder = find.byWidgetPredicate(
        (w) => w is PocketSwitch && w.label == label,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each entry and appearance segment has a 48dp semantic target', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic(populated: false));
    addTearDown(app.dispose);
    final semantics = tester.ensureSemantics();
    app.startDraft(categoryId: 'food');
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: EntryPage(controller: app),
      ),
    );
    await tester.pumpAndSettle();
    for (final kind in EntryKind.values) {
      final finder = find.byKey(ValueKey('entry-kind-${kind.name}'));
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(finder).width, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(finder).rect.height, greaterThanOrEqualTo(48));
    }
    await tester.tapAt(
      tester
              .getRect(find.byKey(const ValueKey('entry-kind-income')))
              .topCenter +
          const Offset(0, 2),
    );
    await tester.pumpAndSettle();
    expect(app.draft!.kind, EntryKind.income);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: SettingsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();
    for (final value in ['system', 'light', 'dark']) {
      final finder = find.byKey(ValueKey('theme-$value'));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(finder).width, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(finder).rect.height, greaterThanOrEqualTo(48));
    }
    await tester.tapAt(
      tester.getRect(find.byKey(const ValueKey('theme-dark'))).bottomCenter -
          const Offset(0, 2),
    );
    await tester.pumpAndSettle();
    expect(app.ledger.preferences.theme, 'dark');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a note is persisted and included when saving immediately', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic(populated: false));
    addTearDown(app.dispose);
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '25';
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an entry').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byWidgetPredicate((w) => w is Press && w.label == 'Add a note')
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'Synthetic snack');
    expect(app.draft!.note, 'Synthetic snack');
    await tester.tap(find.text('Save').last);
    await tester.pump();
    expect(app.draft!.note, 'Synthetic snack');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-cash')));
    await tester.pumpAndSettle();
    expect(app.ledger.entries.single.note, 'Synthetic snack');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a fresh system-themed install starts without setup or account', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(Ledger.empty());
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Add an entry').first, findsOneWidget);
    expect(app.ledger.active, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'dynamic wallet picker records explicitly with accurate income labels',
    (tester) async {
      configure(tester, const Size(360, 640), scale: 1.5);
      const maya = Wallet(
        id: 'fixture_maya',
        label: 'Maya',
        icon: 'phone',
        color: 'green',
      );
      final app = fixture(
        synthetic(populated: false).copy(
          wallets: [...Wallet.values, maya],
          openings: {Wallet.cash: 0, Wallet.gcash: 0, maya: 0},
        ),
      );
      addTearDown(app.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an entry').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(EntryPage),
          matching: find.text('Food'),
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('key-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('key-7')));
      expect(find.bySemanticsLabel('Paid with Cash'), findsOneWidget);
      await tester.ensureVisible(find.text('Income'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('save-gcash')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Received in GCash'), findsOneWidget);
      final more = find.byKey(const ValueKey('more-wallets'));
      expect(tester.getSize(more).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey('wallet-choice-fixture_maya'));
      expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Received in Maya'), findsOneWidget);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(app.ledger.active.single.wallet, maya);
      expect(app.ledger.active.single.kind, EntryKind.income);
      expect(app.ledger.calculate(maya).income, 700);
      expect(tester.takeException(), null);
      app.startDraft(categoryId: 'food');
      expect(app.draft!.kind, EntryKind.expense);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'wallet creation and inactive allowance setup are explicit and accessible',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: WalletEditorPage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('wallet-name')), 'Maya');
      await tester.scrollUntilVisible(
        find.text('Save wallet'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save wallet'));
      await tester.pumpAndSettle();
      expect(app.ledger.wallets.length, 3);
      expect(app.ledger.availableWallets.last.label, 'Maya');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: AllowancePage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.ledger.allowance, isNull);
      expect(find.text('No income will be recorded.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('allowance-amount')),
        '10.25',
      );
      await tester.tap(find.text('Choose a wallet'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('wallet-choice-${app.ledger.availableWallets.last.id}'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekdays'));
      await tester.pumpAndSettle();
      for (var d = 1; d <= 7; d++) {
        expect(
          tester.getSize(find.byKey(ValueKey('allowance-day-$d'))).height,
          greaterThanOrEqualTo(48),
        );
      }
      await tester.scrollUntilVisible(
        find.text('Save schedule'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save schedule'));
      await tester.pumpAndSettle();
      expect(app.ledger.allowance!.enabled, false);
      expect(app.ledger.allowance!.centavos, 1025);
      expect(app.ledger.allowance!.days, [1, 2, 3, 4, 5]);
      expect(app.ledger.entries, isEmpty);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'custom transfer destination and self-transfer rejection work in entry UI',
    (tester) async {
      configure(tester, const Size(390, 844));
      const maya = Wallet(id: 'fixture_maya', label: 'Maya', color: 'green');
      final app = fixture(
        synthetic(populated: false).copy(
          wallets: [...Wallet.values, maya],
          openings: {Wallet.cash: 0, Wallet.gcash: 0, maya: 0},
        ),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an entry').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('key-2')));
      await tester.tap(find.byKey(const ValueKey('transfer-to')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wallet-choice-cash')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Cash → Cash'));
      await tester.pumpAndSettle();
      expect(app.ledger.entries, isEmpty);
      await tester.tap(find.byKey(const ValueKey('transfer-to')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('wallet-choice-fixture_maya')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Cash → Maya'));
      await tester.pumpAndSettle();
      expect(app.ledger.active.single.toWallet, maya);
      expect(app.ledger.total(EntryKind.expense), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'category entry sheet survives Back and reopens the unfinished draft',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic(populated: false, reduced: false));
      addTearDown(app.dispose);
      await tester.pumpWidget(PocketApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-category-travel')));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(tester.element(find.byType(EntryPage))),
        isA<PocketEntryRoute<void>>(),
      );
      expect(app.draft!.categoryId, 'travel');
      await tester.tap(find.byKey(const ValueKey('key-2')));
      await tester.tap(find.byKey(const ValueKey('key-5')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.draft!.amount, '25');
      expect(app.ledger.active, isEmpty);
      await tester.tap(find.text('Add an entry').first);
      await tester.pumpAndSettle();
      expect(app.draft!.categoryId, 'travel');
      expect(app.draft!.amount, '25');
      await tester.tap(find.byKey(const ValueKey('save-gcash')));
      await tester.pumpAndSettle();
      expect(app.ledger.active.single.centavos, 2500);
      expect(app.ledger.active.single.wallet, Wallet.gcash);
      expect(find.byType(EntryPage), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'enabling today requires confirmation and cancellation records nothing',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: AllowancePage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('allowance-amount')),
        '15.25',
      );
      await tester.tap(find.text('Choose a wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wallet-choice-gcash')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PocketSwitch && w.label == 'Enable scheduled allowance',
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save schedule'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save schedule'));
      await tester.pumpAndSettle();
      expect(find.text("Record today's allowance?"), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.ledger.allowance, isNull);
      expect(app.ledger.active, isEmpty);
      await tester.tap(find.text('Save schedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record and enable'));
      await tester.pumpAndSettle();
      expect(app.ledger.allowance!.enabled, true);
      expect(app.ledger.active.single.centavos, 1525);
      expect(app.ledger.active.single.wallet, Wallet.gcash);
      await app.recordAllowances();
      expect(app.ledger.active.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final theme in ['light', 'dark']) {
    testWidgets('render launched entry and wallet sheets $theme', (
      tester,
    ) async {
      configure(tester, const Size(390, 844));
      const maya = Wallet(
        id: 'fixture_maya',
        label: 'Maya',
        icon: 'phone',
        color: 'green',
      );
      final app = fixture(
        synthetic(theme: theme).copy(wallets: [...Wallet.values, maya]),
      );
      addTearDown(app.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-category-food')));
      await tester.pumpAndSettle();
      for (final digit in ['1', '4', '8', '.', '5', '0']) {
        await tester.tap(find.byKey(ValueKey('key-$digit')));
      }
      await tester.pumpAndSettle();
      await capture(tester, key, 'entry-sheet-$theme');
      await tester.tap(find.byKey(const ValueKey('more-wallets')));
      await tester.pumpAndSettle();
      final sheet = find.byType(SheetFrame);
      expect(tester.getSize(sheet).height, lessThan(600));
      await capture(tester, key, 'wallet-picker-$theme');
      expect(app.ledger.entries.length, 5);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.draft!.amount, '148.50');
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  final cases =
      <String, ({String theme, Size size, double scale, String page})>{
        'today-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'today',
        ),
        'history-dark': (
          theme: 'dark',
          size: const Size(390, 844),
          scale: 1,
          page: 'history',
        ),
        'settings-dark': (
          theme: 'dark',
          size: const Size(390, 844),
          scale: 1,
          page: 'settings',
        ),
        'detail-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'detail',
        ),
        'categories-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'categories',
        ),
        'today-dark': (
          theme: 'dark',
          size: const Size(390, 844),
          scale: 1,
          page: 'today',
        ),
        'amount-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'entry',
        ),
        'amount-dark': (
          theme: 'dark',
          size: const Size(390, 844),
          scale: 1,
          page: 'entry',
        ),
        'amount-large-type': (
          theme: 'light',
          size: const Size(360, 640),
          scale: 1.5,
          page: 'entry',
        ),
        'amount-landscape': (
          theme: 'light',
          size: const Size(844, 390),
          scale: 1,
          page: 'entry',
        ),
        'transfer-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'transfer',
        ),
        'history-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'history',
        ),
        'plan-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'plan',
        ),
        'welcome-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'welcome',
        ),
        'welcome-large-type': (
          theme: 'light',
          size: const Size(360, 640),
          scale: 1.5,
          page: 'welcome',
        ),
        'empty-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'empty',
        ),
        'settings-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'settings',
        ),
        'wallets-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'wallets',
        ),
        'income-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'income',
        ),
        'entry-custom-large': (
          theme: 'light',
          size: const Size(360, 640),
          scale: 1.5,
          page: 'custom-entry',
        ),
        'allowance-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'allowance',
        ),
        'allowance-dark': (
          theme: 'dark',
          size: const Size(390, 844),
          scale: 1,
          page: 'allowance',
        ),
        'allowance-large-type': (
          theme: 'light',
          size: const Size(360, 640),
          scale: 1.5,
          page: 'allowance',
        ),
        'wallet-editor-light': (
          theme: 'light',
          size: const Size(390, 844),
          scale: 1,
          page: 'wallet-editor',
        ),
      };
  for (final item in cases.entries) {
    testWidgets('render synthetic ${item.key}', (tester) async {
      final c = item.value;
      configure(tester, c.size, scale: c.scale);
      final app = fixture(
        synthetic(
          theme: c.theme,
          welcomed: c.page != 'welcome',
          populated: c.page != 'empty',
        ),
      );
      addTearDown(app.dispose);
      Widget? page;
      if (c.page == 'custom-entry' || c.page == 'wallet-editor') {
        const custom = Wallet(
          id: 'fixture_maya',
          label: 'Maya',
          icon: 'phone',
          color: 'green',
        );
        app.ledger = app.ledger.copy(
          wallets: [...Wallet.values, custom],
          openings: {...app.ledger.openings, custom: 0},
        );
      }
      if (['entry', 'transfer', 'income', 'custom-entry'].contains(c.page)) {
        app.startDraft(categoryId: 'food');
        app.draft!.amount = '148.50';
        if (c.page == 'transfer') {
          app.draft!.kind = EntryKind.transfer;
          app.draft!.amount = '500';
          app.draft!.from = Wallet.gcash;
          app.draft!.to = Wallet.cash;
        }
        if (c.page == 'income') app.draft!.kind = EntryKind.income;
        page = EntryPage(controller: app);
      }
      if (c.page == 'detail') {
        page = EntryDetailPage(app: app, id: 'fixture_lunch');
      }
      if (c.page == 'categories') page = CategoriesPage(app: app);
      if (c.page == 'settings') page = SettingsPage(app: app);
      if (c.page == 'wallets') page = WalletsPage(app: app);
      if (c.page == 'allowance') page = AllowancePage(app: app);
      if (c.page == 'wallet-editor') {
        page = WalletEditorPage(app: app, wallet: app.ledger.wallets.last);
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(
            controller: app,
            testHome: page,
            initialTab: c.page == 'history'
                ? 1
                : c.page == 'plan'
                ? 2
                : 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      if (c.size.width > c.size.height) {
        final heading = tester.getRect(find.text('New entry'));
        expect(heading.top, greaterThanOrEqualTo(24));
        expect(heading.bottom, lessThan(c.size.height));
        await tester.ensureVisible(find.byKey(const ValueKey('save-cash')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('save-cash'))).bottom,
          lessThanOrEqualTo(c.size.height - 24),
        );
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, 700),
        );
        await tester.pumpAndSettle();
      }
      await capture(tester, key, item.key);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('render actual Flutter navigation motion fixture', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic(reduced: false));
    addTearDown(app.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: PocketApp(controller: app),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an entry').first);
    await tester.pump();
    for (var i = 0; i < 36; i++) {
      await tester.pump(const Duration(microseconds: 16667));
      await capture(
        tester,
        key,
        'motion/frame_${i.toString().padLeft(3, '0')}',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
