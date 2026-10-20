import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/entry_page.dart';
import 'package:pocket_entry/ui/design.dart' show Press;

import 'ui_test.dart' show fixture, configure, capture, loadFonts;

const proofPhase = String.fromEnvironment(
  'PONPON_PROOF_PHASE',
  defaultValue: 'after',
);

Ledger walletLayoutFixture(
  int count, {
  String theme = 'light',
  bool longNames = false,
}) {
  final wallets = [
    Wallet.cash,
    Wallet.gcash,
    for (var i = 2; i < count; i++)
      Wallet(
        id: 'layout_$i',
        label: longNames
            ? (i.isEven
                  ? 'Household spending reserve'
                  : 'Household spending savings')
            : ['Bank', 'Travel', 'Savings', 'Family', 'Bills', 'Personal'][i %
                  6],
        icon: i.isEven ? 'bank' : 'wallet',
        color: ['amber', 'green', 'blue', 'plum'][i % 4],
      ),
  ].take(count).toList();
  return Ledger.empty().copy(
    wallets: wallets,
    openings: {for (final w in wallets) w: 100000},
    preferences: Preferences(
      welcomed: true,
      theme: theme,
      haptics: false,
      reduceMotion: true,
      privatePreview: true,
      quickWallets: wallets.map((w) => w.id).toList(),
    ),
  );
}

void main() {
  setUpAll(loadFonts);
  for (final count in [1, 2, 3, 4, 6, 7]) {
    testWidgets('Synthetic $count-wallet Direct Entry $proofPhase', (
      tester,
    ) async {
      configure(tester, const Size(390, 844));
      final app = fixture(walletLayoutFixture(count));
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'food');
      app.draft!.amount = '148.50';
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(
            controller: app,
            testHome: EntryPage(controller: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.ledger.preferences.privatePreview, isTrue);
      expect(tester.takeException(), isNull);
      if (proofPhase == 'after' && count <= 4) {
        final rects = [
          for (final w in app.ledger.quickWallets)
            tester.getRect(find.byKey(ValueKey('save-${w.id}'))),
        ];
        expect(rects.map((r) => r.width.round()).toSet().length, 1);
        for (final rect in rects) {
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.bottom, lessThanOrEqualTo(820));
        }
      }
      await capture(tester, key, 'direct-025/$proofPhase-$count-wallets');
      if (proofPhase == 'after' && count == 6) {
        final next = find.byKey(const ValueKey('next-direct-wallets'));
        for (
          var i = 0;
          i < 20 && tester.widget<Press>(next).onPressed != null;
          i++
        ) {
          await tester.tap(next);
          await tester.pumpAndSettle();
        }
        expect(tester.widget<Press>(next).onPressed, isNull);
        expect(
          tester
              .widget<Press>(
                find.byKey(const ValueKey('previous-direct-wallets')),
              )
              .onPressed,
          isNotNull,
        );
        expect(app.ledger.entries, isEmpty);
        expect(
          app.ledger.preferences.quickWallets,
          walletLayoutFixture(count).preferences.quickWallets,
        );
        await capture(tester, key, 'direct-025/after-6-wallets-end');
      }
      if (count == 3 && proofPhase == 'before') {
        await tester.tap(find.byKey(const ValueKey('next-direct-wallets')));
        await tester.pumpAndSettle();
        await capture(tester, key, 'direct-025/$proofPhase-3-wallets-last');
      }
    });
  }
  for (final c in <({String name, Size size, double scale, String theme})>[
    (name: 'small', size: const Size(320, 568), scale: 1, theme: 'light'),
    (name: 'large-type', size: const Size(360, 640), scale: 1.5, theme: 'dark'),
    (name: 'landscape', size: const Size(844, 390), scale: 1, theme: 'light'),
  ]) {
    testWidgets('Synthetic long-label Direct Entry ${c.name} $proofPhase', (
      tester,
    ) async {
      configure(tester, c.size, scale: c.scale);
      final app = fixture(
        walletLayoutFixture(4, theme: c.theme, longNames: true),
      );
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'income');
      app.draft!.amount = '500';
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketApp(
            controller: app,
            testHome: EntryPage(controller: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'direct-025/$proofPhase-${c.name}-first-view');
      if (proofPhase == 'after' && c.name != 'landscape') {
        await tester.ensureVisible(find.byKey(const ValueKey('save-cash')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('next-direct-wallets')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('next-direct-wallets')));
        await tester.pumpAndSettle();
      }
      if (proofPhase == 'after' && c.name == 'landscape') {
        await tester.fling(
          find.byKey(const ValueKey('direct-wallet-pages')),
          const Offset(-900, 0),
          1200,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Swipe'), findsWidgets);
      }
      await capture(tester, key, 'direct-025/$proofPhase-${c.name}-4-wallets');
      expect(tester.takeException(), isNull);
    });
  }
  for (final count in [3, 4]) {
    testWidgets(
      '$count visible wallets save the tapped wallet without changing order',
      (tester) async {
        configure(tester, const Size(390, 844));
        final ledger = walletLayoutFixture(count);
        final app = fixture(ledger);
        addTearDown(app.dispose);
        final selected = ledger.quickWallets.last;
        final beforeOrder = ledger.preferences.quickWallets.toList();
        final storedOrder = ledger.wallets.map((w) => w.id).toList();
        await tester.pumpWidget(PocketApp(controller: app));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add an entry').first);
        await tester.pumpAndSettle();
        if (count == 4) {
          await tester.tap(find.text('Income'));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(
            find.descendant(
              of: find.byType(EntryPage),
              matching: find.text('Food'),
            ),
          );
        }
        await tester.tap(find.byKey(const ValueKey('key-1')));
        await tester.tap(find.byKey(const ValueKey('key-2')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('save-${selected.id}')).hitTestable(),
          findsOneWidget,
        );
        expect(app.ledger.entries, isEmpty);
        await tester.tap(find.byKey(ValueKey('save-${selected.id}')));
        await tester.pumpAndSettle();
        expect(app.ledger.entries.single.wallet, selected);
        expect(app.ledger.entries.single.centavos, 1200);
        expect(
          app.ledger.entries.single.kind,
          count == 4 ? EntryKind.income : EntryKind.expense,
        );
        expect(app.ledger.preferences.quickWallets, beforeOrder);
        expect(app.ledger.wallets.map((w) => w.id), storedOrder);
        expect(
          app.ledger.activeWalletBalance,
          ledger.activeWalletBalance + (count == 4 ? 1200 : -1200),
        );
        expect(app.ledger.preferences.privatePreview, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
