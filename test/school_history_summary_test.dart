import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';

import 'ui_test.dart' show capture, configure, fixture, loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'School expense has its own searchable history and Plan subtotal',
    (tester) async {
      configure(tester, const Size(390, 844));
      final old = Ledger.empty()
          .copy(
            categories: defaultCategories
                .where((c) => c.id != 'school_supplies')
                .toList(),
            preferences: const Preferences(
              welcomed: true,
              theme: 'light',
              haptics: false,
              reduceMotion: true,
            ),
          )
          .put(
            const Entry(
              id: 'other_preserved',
              kind: EntryKind.expense,
              centavos: 1000,
              date: '2026-10-11',
              wallet: Wallet.cash,
              categoryId: 'other',
              note: 'Independent Other expense',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      final app = fixture(old);
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'school_supplies');
      app.draft!.amount = '12.34';
      expect(await app.saveDraft(Wallet.gcash), isTrue);
      final stored = app.ledger.encode();
      expect(
        app.ledger.entry('other_preserved')!.toJson(),
        old.entry('other_preserved')!.toJson(),
      );

      final historyProof = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: historyProof,
          child: PocketApp(controller: app, initialTab: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(CupertinoSearchTextField),
        'School supplies',
      );
      await tester.pumpAndSettle();
      expect(find.byType(EntryRow), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EntryRow),
          matching: find.text('School supplies'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(CupertinoIcons.book), findsOneWidget);
      expect(app.ledger.encode(), stored);
      await capture(tester, historyProof, 'school-history-026');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final summaryProof = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: summaryProof,
          child: PocketApp(controller: app, initialTab: 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('School supplies'), findsOneWidget);
      expect(find.text('₱12.34'), findsOneWidget);
      expect(app.ledger.total(EntryKind.expense, month: '2026-10'), 2234);
      expect(app.ledger.total(EntryKind.expense, categoryId: 'other'), 1000);
      expect(
        app.ledger.total(EntryKind.expense, categoryId: 'school_supplies'),
        1234,
      );
      expect(app.ledger.encode(), stored);
      expect(tester.takeException(), isNull);
      await capture(tester, summaryProof, 'school-summary-026');
    },
  );
}
