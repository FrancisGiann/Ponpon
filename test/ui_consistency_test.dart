import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show fixture, synthetic, configure, capture, loadFonts;
import 'bills_balance_test.dart' show bill;

void main() {
  setUpAll(loadFonts);
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final budget in [0, 800000]) {
        testWidgets(
          'Plan equal widths and bottom clearance $width $scale $budget',
          (tester) async {
            configure(tester, Size(width, 640), scale: scale);
            var ledger = synthetic(theme: budget == 0 ? 'light' : 'dark')
                .copy(budgets: {'2026-10': budget});
            for (final category in ledger.categoriesFor(EntryKind.expense)) {
              ledger = ledger.put(
                Entry(
                  id: 'proof_${category.id}',
                  kind: EntryKind.expense,
                  centavos: 100,
                  date: '2026-10-12',
                  wallet: Wallet.cash,
                  categoryId: category.id,
                  note: 'Synthetic layout fixture',
                  createdAt: 1,
                  updatedAt: 1,
                ),
              );
            }
            final app = fixture(ledger);
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
            final spending = tester.getRect(
              find.byKey(const ValueKey('plan-spending-card')),
            );
            final categories = tester.getRect(
              find.byKey(const ValueKey('plan-category-card')),
            );
            expect(spending.left, closeTo(24, .1));
            expect(spending.width, closeTo(width - 48, .1));
            expect(categories.left, closeTo(spending.left, .1));
            expect(categories.width, closeTo(spending.width, .1));
            expect(tester.takeException(), isNull);
            final name =
                '028-plan-${width.toInt()}-$scale-${budget == 0 ? 'unset' : 'budget'}';
            await capture(tester, key, '$name-top');
            await tester.drag(
              find.byKey(const ValueKey('plan-scroll')),
              const Offset(0, -4000),
            );
            await tester.pumpAndSettle();
            final viewport = tester.getRect(
              find.byKey(const ValueKey('plan-scroll')),
            );
            final last = tester.getRect(find.widgetWithText(GroupRow, 'Other'));
            final nav = tester.getRect(
              find.bySemanticsLabel('Plan tab, selected'),
            );
            expect(last.top, greaterThanOrEqualTo(viewport.top));
            expect(last.bottom, lessThanOrEqualTo(viewport.bottom));
            expect(viewport.bottom, lessThanOrEqualTo(nav.top));
            expect(app.ledger.encode(), before);
            expect(tester.takeException(), isNull);
            await capture(tester, key, '$name-bottom');
          },
        );
      }
    }
  }

  for (final theme in ['light', 'dark']) {
    for (final scale in [1.0, 1.6]) {
      for (final form in ['wallet', 'allowance', 'bill', 'balance']) {
        testWidgets(
          'Shared fields and reachable controls $form $theme $scale',
          (tester) async {
            configure(tester, const Size(320, 640), scale: scale);
            final app = fixture(synthetic(theme: theme, populated: false));
            addTearDown(app.dispose);
            final before = app.ledger.encode();
            final key = GlobalKey();
            final Widget page = switch (form) {
              'wallet' => WalletEditorPage(app: app),
              'allowance' => AllowancePage(app: app),
              'bill' => BillEditorPage(app: app),
              _ => BalanceCheckPage(app: app, wallet: Wallet.cash),
            };
            final field = switch (form) {
              'wallet' => 'wallet-name',
              'allowance' => 'allowance-amount',
              'bill' => 'bill-amount',
              _ => 'balance-check-actual',
            };
            final action = switch (form) {
              'wallet' => 'Save wallet',
              'allowance' => 'Save schedule',
              'bill' => 'Save bill',
              _ => 'Compare balance',
            };
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
            await tester.pumpAndSettle();
            expect(find.byType(PocketTextField), findsWidgets);
            expect(tester.takeException(), isNull);
            await capture(tester, key, '028-$form-$theme-$scale-top');
            final scrollable = find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first;
            await tester.scrollUntilVisible(
              find.text(action),
              250,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.text(action)).bottom,
              lessThanOrEqualTo(616),
            );
            expect(app.ledger.encode(), before);
            expect(tester.takeException(), isNull);
            await capture(tester, key, '028-$form-$theme-$scale-bottom');
          },
        );
      }
    }
  }

  testWidgets(
    'Bill selections show choice states without navigation chevrons or automatic writes',
    (tester) async {
      configure(tester, const Size(320, 640), scale: 1.6);
      final app = fixture(synthetic(populated: false).copy(bills: [bill]));
      addTearDown(app.dispose);
      final before = app.ledger.encode();
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: BillPaymentPage(
            app: app,
            bill: bill,
            dueDate: bill.startDate,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cash = find.widgetWithText(GroupRow, 'Cash');
      final gcash = find.widgetWithText(GroupRow, 'GCash');
      expect(tester.widget<GroupRow>(cash).selected, isFalse);
      expect(tester.widget<GroupRow>(gcash).selected, isFalse);
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('GCash'),
        200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();
      expect(tester.widget<GroupRow>(gcash).selected, isTrue);
      expect(tester.widget<GroupRow>(cash).selected, isFalse);
      expect(
        find.descendant(
          of: gcash,
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsNothing,
      );
      expect(app.ledger.encode(), before);
      await tester.scrollUntilVisible(
        find.text('Review payment'),
        250,
        scrollable: scrollable,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
