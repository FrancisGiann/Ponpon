import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show fixture, synthetic, configure, capture, loadFonts;

void main() {
  setUpAll(loadFonts);
  test(
    'Old and unknown settings retain Original with unchanged serialization',
    () {
      final original = const Preferences().toJson();
      expect(original.containsKey('visualStyle'), false);
      expect(Preferences.fromJson(original).visualStyle, VisualStyle.original);
      expect(
        Preferences.fromJson({...original, 'visualStyle': 'future'})
            .visualStyle,
        VisualStyle.original,
      );
      expect(Preferences.fromJson(original).toJson(), original);
    },
  );
  test('Midnight preserves light, dark and system choices', () {
    for (final mode in ['light', 'dark', 'system']) {
      final preferences = Preferences(theme: mode)
          .copy(visualStyle: VisualStyle.midnight);
      expect(preferences.effectiveTheme, 'dark');
      final loaded = Preferences.fromJson(preferences.toJson());
      expect(
        loaded.copy(visualStyle: VisualStyle.original).effectiveTheme,
        mode,
      );
    }
  });
  test('Native appearance follows style without changing amounts or widget privacy', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeBridge.channel, null),
    );
    final base = synthetic();
    for (final style in VisualStyle.values) {
      await const NativeBridge().sync(
        base.copy(preferences: base.preferences.copy(visualStyle: style)),
      );
    }
    final original = Map<String, dynamic>.from(calls.first.arguments as Map)
      ..remove('theme');
    for (var i = 0; i < calls.length; i++) {
      expect(calls[i].method, 'syncAppearance');
      final payload = Map<String, dynamic>.from(calls[i].arguments as Map);
      expect(
        payload.remove('theme'),
        VisualStyle.values[i] == VisualStyle.midnight ? 'dark' : 'light',
      );
      expect(payload, original);
    }
  });
  testWidgets(
    'Failed style save is visible, preserves data and can be retried',
    (tester) async {
      configure(tester, const Size(320, 640), scale: 1.6);
      final app = fixture(synthetic());
      addTearDown(app.dispose);
      final store = app.store as MemoryLedgerStore;
      final before = app.ledger.encode();
      store.failWrites = true;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(
            controller: app,
            testHome: VisualStylePage(app: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('style-powderBlue'));
      await tester.scrollUntilVisible(target, 300);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Style could not be saved'), findsOneWidget);
      expect(app.ledger.encode(), before);
      expect(store.value.encode(), before);
      await capture(tester, key, '028-style-save-failure');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      store.failWrites = false;
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(app.ledger.preferences.visualStyle, VisualStyle.powderBlue);
      expect(store.value.preferences.visualStyle, VisualStyle.powderBlue);
      expect(tester.takeException(), isNull);
    },
  );
  for (final style in VisualStyle.values) {
    test(
      '$style persists across file restart without financial record changes',
      () async {
        final directory = Directory.systemTemp.createTempSync('ponpon-style-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final ledger = synthetic();
        final changed = ledger.copy(
          preferences: ledger.preferences.copy(visualStyle: style),
        );
        await FileLedgerStore(directory).save(changed);
        final restored = (await FileLedgerStore(directory).load()).ledger;
        expect(restored.preferences.visualStyle, style);
        final before = jsonDecode(ledger.encode()) as Map;
        final after = jsonDecode(restored.encode()) as Map;
        before.remove('preferences');
        after.remove('preferences');
        expect(after, before);
        expect(restored.preferences.theme, ledger.preferences.theme);
        expect(
          restored.preferences.effectiveTheme,
          style == VisualStyle.midnight ? 'dark' : 'light',
        );
      },
    );
    testWidgets(
      '$style Today, History, Settings and feedback remain readable',
      (tester) async {
        configure(tester, const Size(390, 844));
        final base = synthetic();
        final app = fixture(
          base.copy(preferences: base.preferences.copy(visualStyle: style)),
        );
        addTearDown(app.dispose);
        final before = app.ledger.encode();
        final key = GlobalKey();
        for (final tab in [0, 1]) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: PocketApp(
                controller: app,
                testHome: HomeShell(app: app, initialTab: tab),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            '028-${style.name}-${tab == 0 ? 'today' : 'history'}',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: PocketApp(
              controller: app,
              testHome: SettingsPage(app: app),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.text('Visual style');
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await capture(tester, key, '028-${style.name}-settings');
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byType(VisualStylePage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: PocketApp(
              controller: app,
              testHome: Builder(
                builder: (context) => PocketPage(
                  'Feedback',
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const QuietMessage(
                        'Nothing here yet',
                        'Add an entry when you are ready.',
                      ),
                      const ErrorLine('Enter a valid amount.'),
                      const PrimaryButton('Save entry', onPressed: null),
                      const SizedBox(height: 12),
                      const SecondaryButton('Edit budget', onPressed: null),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, '028-${style.name}-feedback');
        expect(app.ledger.encode(), before);
      },
    );
    testWidgets(
      '$style income selection, themed sheet, explicit save and Undo',
      (tester) async {
        configure(tester, const Size(320, 640), scale: 1.6);
        final base = synthetic(populated: false);
        final app = fixture(
          base.copy(preferences: base.preferences.copy(visualStyle: style)),
        );
        addTearDown(app.dispose);
        final semantics = tester.ensureSemantics();
        try {
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: PocketApp(controller: app),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Add an entry').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add an entry').first);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('entry-kind-income')));
          await tester.pumpAndSettle();
          expect(app.draft!.categoryId, 'income');
          expect(
            find.bySemanticsLabel('General income category, selected'),
            findsOneWidget,
          );
          await tester.tap(find.bySemanticsLabel('All categories'));
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(SheetFrame),
              matching: find.text('Food'),
            ),
            findsNothing,
          );
          await capture(tester, key, '028-${style.name}-income-sheet-large');
          await tester.tap(find.text('Salary').last);
          await tester.pumpAndSettle();
          expect(app.draft!.categoryId, 'income_salary');
          await tester.tap(find.byKey(const ValueKey('key-5')));
          await tester.pumpAndSettle();
          expect(app.ledger.entries, isEmpty);
          await tester.ensureVisible(find.byKey(const ValueKey('save-gcash')));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('save-gcash'))).bottom,
            lessThanOrEqualTo(616),
          );
          await capture(tester, key, '028-${style.name}-entry-large');
          await tester.tap(find.byKey(const ValueKey('save-gcash')));
          await tester.pumpAndSettle();
          expect(app.ledger.entries.single.wallet, Wallet.gcash);
          expect(app.ledger.entries.single.categoryId, 'income_salary');
          expect(app.ledger.entries.single.centavos, 500);
          await tester.tap(find.text('Undo'));
          await tester.pumpAndSettle();
          expect(app.ledger.active, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
    for (final form in ['wallet', 'allowance', 'balance']) {
      testWidgets(
        '$style $form large text, keyboard and final control clearance',
        (tester) async {
          configure(tester, const Size(320, 640), scale: 1.6);
          final base = synthetic();
          final app = fixture(
            base.copy(preferences: base.preferences.copy(visualStyle: style)),
          );
          addTearDown(app.dispose);
          final before = app.ledger.encode();
          final page = switch (form) {
            'wallet' => WalletEditorPage(app: app),
            'allowance' => AllowancePage(app: app),
            _ => BalanceCheckPage(app: app, wallet: Wallet.cash),
          };
          final field = switch (form) {
            'wallet' => 'wallet-name',
            'allowance' => 'allowance-amount',
            _ => 'balance-check-actual',
          };
          final action = switch (form) {
            'wallet' => 'Save wallet',
            'allowance' => 'Save schedule',
            _ => 'Compare balance',
          };
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: PocketApp(controller: app, testHome: page),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(ValueKey(field)),
            form == 'wallet' ? 'Synthetic wallet' : '123.45',
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          final scrollable = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.text(action),
            200,
            scrollable: scrollable,
          );
          await tester.ensureVisible(find.text(action));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.text(action)).bottom,
            lessThanOrEqualTo(420),
          );
          expect(tester.takeException(), isNull);
          expect(app.ledger.encode(), before);
          await capture(tester, key, '028-${style.name}-$form-keyboard-large');
        },
      );
    }
    for (final dark in [false, true]) {
      test('$style $dark readable text contrast', () {
        final p = Palette(dark || style == VisualStyle.midnight, style);
        double contrast(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
        }

        for (final background in [p.surface, p.background]) {
          expect(contrast(p.ink, background), greaterThanOrEqualTo(4.5));
          expect(contrast(p.secondary, background), greaterThanOrEqualTo(4.5));
        }
        for (final semantic in [p.green, p.blue, p.danger, p.amber]) {
          expect(contrast(semantic, p.surface), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(p.accent, p.tint), greaterThanOrEqualTo(4.5));
      });
    }
    for (final scale in [1.0, 1.6]) {
      testWidgets('$style Plan and bill form at 320 text $scale', (
        tester,
      ) async {
        configure(tester, const Size(320, 640), scale: scale);
        final base = synthetic();
        final app = fixture(
          base.copy(preferences: base.preferences.copy(visualStyle: style)),
        );
        addTearDown(app.dispose);
        final before = app.ledger.encode();
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: PocketApp(
              controller: app,
              testHome: HomeShell(app: app, initialTab: 2),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, '028-${style.name}-plan-$scale');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: PocketApp(
              controller: app,
              testHome: BillEditorPage(app: app),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await capture(tester, key, '028-${style.name}-bill-$scale');
        expect(tester.takeException(), isNull);
        expect(app.ledger.encode(), before);
      });
    }
  }
  testWidgets(
    'Preview selection applies, persists and restores stored appearance',
    (tester) async {
      configure(tester, const Size(320, 640), scale: 1.6);
      final base = synthetic();
      final app = fixture(base);
      addTearDown(app.dispose);
      final before = jsonDecode(app.ledger.encode()) as Map
        ..remove('preferences');
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(
            controller: app,
            testHome: VisualStylePage(app: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final style in VisualStyle.values.reversed) {
        final target = find.byKey(ValueKey('style-${style.name}'));
        await tester.scrollUntilVisible(
          target,
          style == VisualStyle.midnight ? 400 : -400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(app.ledger.preferences.visualStyle, style);
        final theme = tester
            .widget<CupertinoApp>(find.byType(CupertinoApp))
            .theme!;
        expect(
          theme.brightness,
          style == VisualStyle.midnight ? Brightness.dark : Brightness.light,
        );
        expect(app.ledger.preferences.theme, 'light');
        final after = jsonDecode(app.ledger.encode()) as Map
          ..remove('preferences');
        expect(after, before);
        expect(tester.takeException(), isNull);
        await capture(tester, key, '028-preview-${style.name}-large');
      }
    },
  );
}
