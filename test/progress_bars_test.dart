import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/adventure.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'bills_balance_test.dart' show bill;
import 'ui_test.dart' show configure, loadFonts;

void main() {
  setUpAll(loadFonts);

  testWidgets('budget and installment bars fill their full track height', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    Future<void> showBudget(int spent, int budget) => tester.pumpWidget(
      CupertinoApp(
        home: VisualStyleScope(
          style: VisualStyle.adventure,
          child: Center(
            child: SizedBox(
              width: 300,
              child: BudgetBar(spent: spent, budget: budget),
            ),
          ),
        ),
      ),
    );

    for (final (spent, expected) in [(0, 0.0), (250, .25), (1500, 1.0)]) {
      await showBudget(spent, 1000);
      final track = tester.getSize(
        find.byKey(const ValueKey('budget-progress-track')),
      );
      final fill = tester.getSize(
        find.byKey(const ValueKey('budget-progress-fill')),
      );
      expect(track.height, 7);
      expect(fill.height, 7);
      expect(fill.width, closeTo(track.width * expected, .1));
    }

    final plan = bill.copy(
      frequency: BillFrequency.monthly,
      paymentCount: 3,
      startDate: '2026-09-01',
    );
    var ledger = Ledger.empty().copy(bills: [plan]);
    final dates = [for (var i = 0; i < 3; i++) plan.occurrence(i)!];
    for (var paid = 0; paid <= 3; paid++) {
      if (paid > 0) {
        final date = dates[paid - 1];
        ledger = ledger.put(
          Entry(
            id: plan.paymentId(date),
            kind: EntryKind.expense,
            centavos: plan.centavos,
            date: date,
            wallet: Wallet.cash,
            categoryId: 'bills',
            note: plan.name,
            createdAt: paid,
            updatedAt: paid,
            billId: plan.id,
            billDueDate: date,
          ),
        );
      }
      await tester.pumpWidget(
        CupertinoApp(
          home: VisualStyleScope(
            style: VisualStyle.adventure,
            child: Center(
              child: SizedBox(
                width: 300,
                child: AdventureBillsProgress(ledger: ledger),
              ),
            ),
          ),
        ),
      );
      final track = tester.getSize(
        find.byKey(ValueKey('bill-progress-track-${plan.id}')),
      );
      final fill = tester.getSize(
        find.byKey(ValueKey('bill-progress-fill-${plan.id}')),
      );
      expect(track.height, 8);
      expect(fill.height, 8);
      expect(fill.width, closeTo(track.width * paid / 3, .1));
      expect(find.text('$paid of 3'), findsOneWidget);
    }
  });

  testWidgets(
    'loan list and detail fills update after save, correction, and undo',
    (tester) async {
      configure(tester, const Size(390, 844));
      const loan = Loan(
        id: 'progress_loan',
        borrower: 'Ari',
        principalCentavos: 10000,
        date: '2026-11-01',
        funded: false,
        alreadyRepaidCentavos: 0,
        createdAt: 1,
        updatedAt: 1,
      );
      final ledger = Ledger.empty().copy(
        openings: {Wallet.cash: 20000},
        loans: const [loan],
        preferences: const Preferences(
          visualStyle: VisualStyle.adventure,
          reduceMotion: true,
          haptics: false,
        ),
      );
      final app = AppController(
        store: MemoryLedgerStore(ledger),
        clock: () => DateTime(2026, 11, 16, 12),
      )..ledger = ledger;
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: HomeShell(app: app, initialTab: 3),
        ),
      );
      await tester.pumpAndSettle();

      void expectFill(String fillKey, String trackKey, double fraction) {
        final track = tester.getSize(find.byKey(ValueKey(trackKey)));
        final fill = tester.getSize(find.byKey(ValueKey(fillKey)));
        expect(track.height, 7);
        expect(fill.height, 7);
        expect(fill.width, closeTo(track.width * fraction, .1));
      }

      expectFill('loan-progress-list-fill', 'loan-progress-list-track', 0);
      await app.recordLoanRepayment(
        reviewed: loan,
        centavos: 2500,
        date: '2026-11-02',
        wallet: Wallet.cash,
      );
      await tester.pumpAndSettle();
      expectFill('loan-progress-list-fill', 'loan-progress-list-track', .25);

      await tester.tap(find.text('Ari').first);
      await tester.pumpAndSettle();
      expectFill(
        'loan-progress-detail-fill',
        'loan-progress-detail-track',
        .25,
      );

      final correct = find.text('Correct');
      await tester.ensureVisible(correct);
      await tester.tap(correct);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).first, '50.00');
      await tester.tap(find.text('Save repayment'));
      await tester.pumpAndSettle();
      expectFill('loan-progress-detail-fill', 'loan-progress-detail-track', .5);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expectFill(
        'loan-progress-detail-fill',
        'loan-progress-detail-track',
        .25,
      );
      expect(app.ledger.loan(loan.id)!.paidCentavos(app.ledger), 2500);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectFill('loan-progress-list-fill', 'loan-progress-list-track', .25);
      final current = app.ledger.loan(loan.id)!;
      expect(
        await app.recordLoanRepayment(
          reviewed: current,
          centavos: 7500,
          date: '2026-11-03',
          wallet: Wallet.cash,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      expectFill('loan-progress-list-fill', 'loan-progress-list-track', 1);
      await tester.tap(find.text('Ari').first);
      await tester.pumpAndSettle();
      expectFill('loan-progress-detail-fill', 'loan-progress-detail-track', 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
