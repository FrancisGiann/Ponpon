import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show configure, loadFonts;

void main() {
  setUpAll(loadFonts);

  testWidgets('Loans tab records an existing loan and final repayment', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = AppController(
      store: MemoryLedgerStore(Ledger.empty()),
      clock: () => DateTime(2026, 11, 16, 12),
    );
    addTearDown(app.dispose);
    app.ledger = Ledger.empty().copy(
      openings: {Wallet.cash: 10000, Wallet.gcash: 0},
      preferences: const Preferences(welcomed: true, reduceMotion: true),
    );

    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: HomeShell(app: app, initialTab: 3),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loans tab, selected'), findsOneWidget);
    expect(find.text('Projected balance'), findsOneWidget);

    await tester.tap(
      find
          .descendant(of: find.byType(LoansPage), matching: find.byType(Press))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'Ari');
    await tester.enterText(find.byType(CupertinoTextField).at(1), '50.00');
    await tester.tap(find.text('Already existed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(2), '10.00');
    await tester.tap(find.text('Save loan'));
    await tester.pumpAndSettle();

    expect(app.ledger.loans.single.funded, isFalse);
    expect(app.ledger.loans.single.alreadyRepaidCentavos, 1000);
    expect(app.ledger.entries, isEmpty);
    expect(app.ledger.calculate(Wallet.cash).balance, 10000);
    expect(find.text('Ari'), findsOneWidget);
    await tester.tap(find.text('Ari'));
    await tester.pumpAndSettle();
    expect(find.text('₱40.00 remaining · ₱50.00 original'), findsOneWidget);

    await tester.tap(find.text('Record repayment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, '40.00');
    await tester.tap(
      find.descendant(
        of: find.byType(LoanPaymentPage),
        matching: find.widgetWithText(GroupRow, 'Received in'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(SheetFrame).last,
            matching: find.text('GCash'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save repayment'));
    await tester.pumpAndSettle();

    expect(app.ledger.loans.single.completed(app.ledger), isTrue);
    expect(app.ledger.calculate(Wallet.gcash).balance, 4000);
    expect(app.ledger.total(EntryKind.income), 0);
    expect(app.celebratedLoanId, app.ledger.loans.single.id);
    expect(find.text('Loan paid in full'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bill-celebration-completed')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
