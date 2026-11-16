import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';

Loan _loan({
  required String id,
  required int principal,
  bool funded = false,
  int alreadyRepaid = 0,
}) => Loan(
  id: id,
  borrower: 'Ari',
  principalCentavos: principal,
  date: '2026-11-01',
  funded: funded,
  alreadyRepaidCentavos: alreadyRepaid,
  createdAt: 100,
  updatedAt: 100,
);

Entry _issue(String loanId, int amount) => Entry(
  id: 'issue_$loanId',
  kind: EntryKind.expense,
  centavos: amount,
  date: '2026-11-01',
  wallet: Wallet.cash,
  note: 'Loan to Ari',
  createdAt: 100,
  updatedAt: 100,
  loanId: loanId,
  loanAction: LoanAction.issued,
);

Entry _repayment(String loanId, String id, int amount, Wallet wallet) => Entry(
  id: id,
  kind: EntryKind.income,
  centavos: amount,
  date: '2026-11-02',
  wallet: wallet,
  createdAt: 200,
  updatedAt: 200,
  loanId: loanId,
  loanAction: LoanAction.repayment,
);

void main() {
  test('schema 5 migration preserves wallets, entries and balances', () {
    final before = Ledger.empty()
        .copy(openings: {Wallet.cash: 12345, Wallet.gcash: 4500})
        .put(
          Entry(
            id: 'schema5_expense',
            kind: EntryKind.expense,
            centavos: 2345,
            date: '2026-10-30',
            wallet: Wallet.cash,
            categoryId: 'food',
            createdAt: 10,
            updatedAt: 10,
          ),
        )
        .put(
          Entry(
            id: 'schema5_income',
            kind: EntryKind.income,
            centavos: 900,
            date: '2026-10-31',
            wallet: Wallet.gcash,
            categoryId: 'income',
            createdAt: 11,
            updatedAt: 11,
          ),
        );
    final snapshot = before.toJson()
      ..['schemaVersion'] = 5
      ..remove('loans');

    final migrated = Ledger.decode(jsonEncode(snapshot));

    expect(migrated.loans, isEmpty);
    expect(
      migrated.entries.map((entry) => entry.toJson()).toList(),
      before.entries.map((entry) => entry.toJson()).toList(),
    );
    expect(
      migrated.calculate(Wallet.cash).balance,
      before.calculate(Wallet.cash).balance,
    );
    expect(
      migrated.calculate(Wallet.gcash).balance,
      before.calculate(Wallet.gcash).balance,
    );
    expect(migrated.toJson()['schemaVersion'], schemaVersion);
  });

  test(
    'funded loans debit source wallet and stay outside income and spending',
    () {
      var ledger = Ledger.empty().copy(
        openings: {Wallet.cash: 100000, Wallet.gcash: 0},
      );
      final loan = _loan(id: 'funded', principal: 40000, funded: true);
      ledger = ledger.saveLoan(loan, issuance: _issue(loan.id, 40000));

      expect(ledger.calculate(Wallet.cash).balance, 60000);
      expect(ledger.total(EntryKind.expense), 0);
      expect(ledger.total(EntryKind.income), 0);
      expect(ledger.outstandingLoanPrincipal, 40000);
      expect(ledger.loanProjectionBalance, 100000);

      final decoded = Ledger.decode(ledger.encode());
      expect(decoded.loans.single.toJson(), loan.toJson());
      expect(decoded.entries.single.toJson(), ledger.entries.single.toJson());
    },
  );

  test(
    'existing loan balance carries prior repayments without wallet movement',
    () {
      final original = Ledger.empty().copy(
        openings: {Wallet.cash: 10000, Wallet.gcash: 0},
      );
      final loan = _loan(
        id: 'existing',
        principal: 50000,
        alreadyRepaid: 12000,
      );
      final ledger = original.saveLoan(loan);

      expect(ledger.calculate(Wallet.cash).balance, 10000);
      expect(ledger.entries, isEmpty);
      expect(ledger.loan(loan.id)!.remainingCentavos(ledger), 38000);
      expect(ledger.loanProjectionBalance, 48000);
    },
  );

  test(
    'repayments credit wallet and correction or removal reverses both sides',
    () {
      final loan = _loan(id: 'repay', principal: 50000, funded: true);
      var ledger = Ledger.empty()
          .copy(openings: {Wallet.cash: 50000, Wallet.gcash: 0})
          .saveLoan(loan, issuance: _issue(loan.id, 50000));
      ledger = ledger.putLoanRepayment(
        loan,
        _repayment(loan.id, 'repay_1', 15000, Wallet.gcash),
      );
      expect(ledger.calculate(Wallet.gcash).balance, 15000);
      expect(ledger.total(EntryKind.income), 0);
      expect(ledger.loan(loan.id)!.remainingCentavos(ledger), 35000);

      final edited = _repayment(
        loan.id,
        'repay_1',
        10000,
        Wallet.cash,
      ).copyWithForTest();
      ledger = ledger.putLoanRepayment(ledger.loan(loan.id)!, edited);
      expect(ledger.calculate(Wallet.gcash).balance, 0);
      expect(ledger.calculate(Wallet.cash).balance, 10000);
      expect(ledger.loan(loan.id)!.remainingCentavos(ledger), 40000);

      ledger = ledger.deleteLoanRepayment('repay_1', 300);
      expect(ledger.calculate(Wallet.cash).balance, 0);
      expect(ledger.loan(loan.id)!.remainingCentavos(ledger), 50000);
      ledger = ledger.undo(301);
      expect(ledger.calculate(Wallet.cash).balance, 10000);
      expect(ledger.loan(loan.id)!.remainingCentavos(ledger), 40000);
      expect(
        () => ledger.delete('repay_1', 302),
        throwsA(isA<LedgerException>()),
      );
    },
  );

  test('loan removal and undo reverse all linked movements atomically', () {
    final loan = _loan(id: 'remove', principal: 30000, funded: true);
    var ledger = Ledger.empty()
        .copy(openings: {Wallet.cash: 90000, Wallet.gcash: 0})
        .saveLoan(loan, issuance: _issue(loan.id, 30000));
    ledger = ledger.putLoanRepayment(
      loan,
      _repayment(loan.id, 'remove_repay', 5000, Wallet.gcash),
    );
    final balanceBefore = ledger.activeWalletBalance;

    ledger = ledger.removeLoan(loan.id, 400);
    expect(ledger.activeWalletBalance, 90000);
    expect(ledger.outstandingLoanPrincipal, 0);
    expect(ledger.active.where((entry) => entry.loanId == loan.id), isEmpty);

    ledger = Ledger.decode(ledger.encode()).undo(401);
    expect(ledger.activeWalletBalance, balanceBefore);
    expect(ledger.outstandingLoanPrincipal, 25000);
    expect(ledger.active.where((entry) => entry.loanId == loan.id).length, 2);
  });

  test(
    'stored final repayment celebrates once and undo restores the due amount',
    () async {
      final app = AppController(
        store: MemoryLedgerStore(Ledger.empty()),
        clock: () => DateTime(2026, 11, 16, 12),
      );
      addTearDown(app.dispose);
      app.ledger = Ledger.empty().copy(
        openings: {Wallet.cash: 25000, Wallet.gcash: 0},
      );

      expect(
        await app.addLoan(
          borrower: 'Ari',
          principalCentavos: 25000,
          date: '2026-11-01',
          alreadyExisting: false,
          fundingWallet: Wallet.cash,
        ),
        isTrue,
      );
      final loan = app.ledger.activeLoans.single;
      expect(
        await app.recordLoanRepayment(
          reviewed: loan,
          centavos: 25000,
          date: '2026-11-16',
          wallet: Wallet.gcash,
        ),
        isTrue,
      );
      expect(app.ledger.loan(loan.id)!.completed(app.ledger), isTrue);
      expect(app.celebratedLoanId, loan.id);
      expect(app.ledger.calculate(Wallet.gcash).balance, 25000);
      expect(app.ledger.loanProjectionBalance, 25000);

      expect(await app.undo(), isTrue);
      expect(app.celebratedLoanId, isNull);
      expect(app.ledger.loan(loan.id)!.remainingCentavos(app.ledger), 25000);
      expect(app.ledger.calculate(Wallet.gcash).balance, 0);
    },
  );
}

extension on Entry {
  Entry copyWithForTest() => Entry(
    id: id,
    kind: kind,
    centavos: centavos,
    date: date,
    wallet: wallet,
    categoryId: categoryId,
    note: note,
    createdAt: createdAt,
    updatedAt: 300,
    loanId: loanId,
    loanAction: loanAction,
  );
}
