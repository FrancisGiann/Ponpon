import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show configure, fixture, loadFonts;

Ledger historyLedger() {
  var ledger = Ledger.empty();
  for (var i = 0; i < 43; i++) {
    final income = i % 5 == 0;
    ledger = ledger.put(
      Entry(
        id: 'page_$i',
        kind: income ? EntryKind.income : EntryKind.expense,
        centavos: 100 + i,
        date: i < 25 ? '2026-10-12' : '2026-10-11',
        wallet: i.isEven ? Wallet.cash : Wallet.gcash,
        categoryId: income
            ? 'income'
            : i.isEven
            ? 'food'
            : 'travel',
        note: 'record $i',
        createdAt: i + 1,
        updatedAt: i + 1,
      ),
    );
  }
  return ledger;
}

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'History pages keep date groups and clamp after deleting the last page',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(historyLedger());
      addTearDown(app.dispose);
      final originalTotal = app.ledger.activeWalletBalance;
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: AnimatedBuilder(
            animation: app,
            builder: (context, _) => HistoryPage(app: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1–20 of 43'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-filters')), findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find.byWidgetPredicate(
                (w) => w is EntryRow && w.entry.id == 'page_24',
              ),
            )
            .dy,
        lessThan(500),
      );
      expect(
        find.byWidgetPredicate((w) => w is EntryRow && w.entry.id == 'page_24'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('history-next-page')));
      await tester.pumpAndSettle();
      expect(find.text('21–40 of 43'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget); // The date group spans pages.
      expect(
        find.byWidgetPredicate((w) => w is EntryRow && w.entry.id == 'page_4'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('history-next-page')));
      await tester.pumpAndSettle();
      expect(find.text('41–43 of 43'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is EntryRow && w.entry.id == 'page_27'),
        findsOneWidget,
      );
      expect(app.ledger.activeWalletBalance, originalTotal);
      for (final id in ['page_25', 'page_26', 'page_27']) {
        expect(await app.delete(app.ledger.entry(id)!), isTrue);
      }
      await tester.pumpAndSettle();
      expect(find.text('21–40 of 40'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-next-page')), findsOneWidget);
      app.ledger = app.ledger.put(
        const Entry(
          id: 'new_after_delete',
          kind: EntryKind.expense,
          centavos: 100,
          date: '2026-10-12',
          wallet: Wallet.cash,
          categoryId: 'food',
          createdAt: 100,
          updatedAt: 100,
        ),
      );
      app.publish();
      await tester.pumpAndSettle();
      expect(find.text('21–40 of 41'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'History filters the complete set before paging and resets the page',
    (tester) async {
      configure(tester, const Size(390, 844));
      final app = fixture(historyLedger());
      addTearDown(app.dispose);
      final originalTotal = app.ledger.activeWalletBalance;
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: AnimatedBuilder(
            animation: app,
            builder: (context, _) => HistoryPage(app: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-next-page')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoSearchTextField), 'record 4');
      await tester.pumpAndSettle();
      expect(find.text('4 of 43 entries match'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-next-page')), findsNothing);
      await tester.enterText(find.byType(CupertinoSearchTextField), '');
      await tester.pumpAndSettle();
      expect(find.text('1–20 of 43'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-filters')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is GroupRow && w.title == 'Cash'),
      );
      await tester.pumpAndSettle();
      expect(find.text('22 of 43 entries match'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-filters')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is GroupRow && w.title == 'Clear filters',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1–20 of 43'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-filters')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is GroupRow && w.title == 'Date'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Apply selected date'));
      await tester.pumpAndSettle();
      expect(find.text('25 of 43 entries match'), findsOneWidget);
      expect(find.text('1–20 of 25'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-filters')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is GroupRow && w.title == 'Category'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is GroupRow && w.title == 'Food'),
      );
      await tester.pumpAndSettle();
      expect(find.text('10 of 43 entries match'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-next-page')), findsNothing);
      expect(app.ledger.activeWalletBalance, originalTotal);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
