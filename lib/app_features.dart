part of 'app_controller.dart';

extension BillsAndBalance on AppController {
  BalanceCheck checkBalance(Wallet wallet, int actual) {
    if (ledger.wallet(wallet)?.archived != false ||
        actual.abs() > maxCentavos) {
      throw const LedgerException(
        'Choose an active wallet and a valid actual balance.',
      );
    }
    return BalanceCheck(
      wallet: wallet,
      expected: ledger.calculate(wallet).balance,
      actual: actual,
    );
  }

  Future<bool> confirmBalanceCheck(
    BalanceCheck check, {
    required bool confirmed,
  }) {
    if (!confirmed || check.difference == 0) return Future.value(false);
    return commit(
      (l) {
        if (l.wallet(check.wallet)?.archived != false ||
            l.entry(check.id) != null) {
          throw const LedgerException(
            'Start a fresh balance check for an active wallet.',
          );
        }
        if (l.calculate(check.wallet).balance != check.expected) {
          throw const LedgerException(
            'This wallet changed. Check the balance again before confirming.',
          );
        }
        final adjustment = BalanceAdjustment.fromJson(
          BalanceAdjustment(
            expected: check.expected,
            actual: check.actual,
          ).toJson(),
        );
        final now = clock().millisecondsSinceEpoch;
        return l.put(
          Entry(
            id: check.id,
            kind: adjustment.difference > 0
                ? EntryKind.income
                : EntryKind.expense,
            centavos: adjustment.difference.abs(),
            date: dayKey(clock()),
            wallet: check.wallet,
            note: 'Balance adjustment',
            createdAt: now,
            updatedAt: now,
            adjustment: adjustment,
          ),
        );
      },
      message: 'Balance adjustment recorded',
      undo: true,
    );
  }

  Future<bool> setBill(Bill value, {Bill? reviewed}) => commit((l) {
    Bill.fromJson(value.toJson());
    final previous = l.bill(value.id);
    if (previous?.deleted == true ||
        reviewed != null &&
            (previous == null || !sameBill(previous, reviewed))) {
      throw const LedgerException(
        'This bill changed. Review it again before saving.',
      );
    }
    if (previous == null &&
        l.bills.where((bill) => !bill.deleted).length >= maxActiveBills) {
      throw const LedgerException('Keep up to 100 active or paused bills.');
    }
    if (previous == null && l.bills.length >= maxBillRecords) {
      throw const LedgerException(
        'This ledger has too many bill records. Export a backup before starting another bill.',
      );
    }
    final history = l.entries.where((e) => e.billId == value.id);
    if (previous != null &&
        (previous.startDate != value.startDate ||
            previous.frequency != value.frequency) &&
        history.isNotEmpty) {
      throw const LedgerException(
        'This bill has payment history. Pause it and create a new bill to change its first due date or frequency.',
      );
    }
    if (previous != null &&
        previous.paymentCount != value.paymentCount &&
        history.any((entry) => !value.containsDue(entry.billDueDate!))) {
      throw const LedgerException(
        'The new installment count would remove a payment from this bill’s history.',
      );
    }
    return l.copy(
      bills: [
        for (final bill in l.bills)
          if (bill.id == value.id) value else bill,
        if (previous == null) value,
      ],
    );
  }, message: 'Bill saved');

  Future<bool> deleteBill(Bill reviewed, List<Entry> reviewedPayments) =>
      commit(
        (l) => l.removeBill(
          reviewed,
          reviewedPayments,
          clock().millisecondsSinceEpoch,
        ),
        message: 'Bill deleted and payments reversed',
        undo: true,
      );

  Future<bool> recordBillPayment(
    Bill reviewed,
    String dueDate,
    Wallet wallet,
    Category category, {
    required bool confirmed,
  }) async {
    if (!confirmed) return false;
    final beforeBill = ledger.bill(reviewed.id);
    final wasComplete =
        beforeBill?.paymentCount != null &&
        beforeBill!.paidInstallments(ledger) >= beforeBill.paymentCount!;
    final hadFinishedBillBadge = AdventureBadges.has(
      ledger,
      AdventureBadge.finishedBill,
    );
    final restoresDeletedPayment =
        ledger.entry(reviewed.paymentId(dueDate))?.deleted == true;
    final result = await commit(
      (l) {
        final bill = l.bill(reviewed.id);
        if (bill == null ||
            bill.deleted ||
            !bill.enabled ||
            jsonEncode(bill.toJson()) != jsonEncode(reviewed.toJson()) ||
            bill.nextDue(l) != dueDate) {
          throw const LedgerException(
            'This bill changed or was already recorded. Review its next due date.',
          );
        }
        if (l.wallet(wallet)?.archived != false ||
            l.category(category.id)?.archived != false ||
            l.category(category.id)!.isIncome) {
          throw const LedgerException(
            'Choose an active wallet and expense category.',
          );
        }
        final id = bill.paymentId(dueDate);
        final old = l.entry(id);
        if (old != null && !old.deleted) {
          throw const LedgerException('This bill payment is already recorded.');
        }
        final now = clock().millisecondsSinceEpoch;
        return l.put(
          Entry(
            id: id,
            kind: EntryKind.expense,
            centavos: bill.centavos,
            date: dayKey(clock()),
            wallet: wallet,
            categoryId: category.id,
            note: '${bill.name} · due ${shortDate(dueDate)}',
            createdAt: old?.createdAt ?? now,
            updatedAt: max(now, old?.updatedAt ?? 0),
            billId: bill.id,
            billDueDate: dueDate,
          ),
          restoringPayment: old?.deleted == true,
        );
      },
      message: 'Bill payment recorded',
      undo: true,
    );
    final savedBill = ledger.bill(reviewed.id);
    final completedNow =
        result &&
        !wasComplete &&
        !restoresDeletedPayment &&
        savedBill?.paymentCount != null &&
        savedBill!.paidInstallments(ledger) >= savedBill.paymentCount!;
    if (completedNow) {
      showAdventureReward(
        AdventureRewardKind.billCompleted,
        badge: hadFinishedBillBadge ? null : AdventureBadge.finishedBill,
      );
      await _hapticIfEnabled();
    }
    return result;
  }
}

extension Loans on AppController {
  Future<bool> addLoan({
    required String borrower,
    required int principalCentavos,
    required String date,
    String? dueDate,
    String note = '',
    required bool alreadyExisting,
    int alreadyRepaidCentavos = 0,
    Wallet? fundingWallet,
  }) {
    final now = clock().millisecondsSinceEpoch;
    final id = newId();
    final activityId = newId();
    return commit(
      (l) {
        if (!alreadyExisting && fundingWallet == null) {
          throw const LedgerException('Choose a wallet to fund this loan.');
        }
        final loan = Loan(
          id: id,
          borrower: borrower.trim(),
          principalCentavos: principalCentavos,
          date: date,
          dueDate: dueDate,
          note: note.trim(),
          funded: !alreadyExisting,
          alreadyRepaidCentavos: alreadyExisting ? alreadyRepaidCentavos : 0,
          createdAt: now,
          updatedAt: now,
        );
        final issue = alreadyExisting
            ? null
            : Entry(
                id: activityId,
                kind: EntryKind.expense,
                centavos: principalCentavos,
                date: date,
                wallet: fundingWallet!,
                note: 'Loan to ${borrower.trim()}',
                createdAt: now,
                updatedAt: now,
                loanId: id,
                loanAction: LoanAction.issued,
              );
        return l.saveLoan(loan, issuance: issue);
      },
      message: 'Loan added',
      undo: true,
    );
  }

  Future<bool> updateLoan(Loan reviewed, Loan value) => commit(
    (l) {
      final old = l.loan(value.id);
      if (old == null ||
          old.deleted ||
          !sameLoan(old, reviewed) ||
          old.funded &&
              (value.principalCentavos != old.principalCentavos ||
                  value.date != old.date)) {
        throw const LedgerException(
          'The original amount and date are fixed for a funded loan.',
        );
      }
      return l.saveLoan(
        value.copy(updatedAt: clock().millisecondsSinceEpoch),
        editing: true,
      );
    },
    message: 'Loan updated',
    undo: true,
  );

  Future<bool> recordLoanRepayment({
    required Loan reviewed,
    required int centavos,
    required String date,
    required Wallet wallet,
    String note = '',
  }) async {
    final wasComplete = reviewed.completed(ledger);
    final hadFinalLoanBadge = AdventureBadges.has(
      ledger,
      AdventureBadge.finalLoanRepayment,
    );
    final now = clock().millisecondsSinceEpoch;
    final repayment = Entry(
      id: newId(),
      kind: EntryKind.income,
      centavos: centavos,
      date: date,
      wallet: wallet,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      loanId: reviewed.id,
      loanAction: LoanAction.repayment,
    );
    final result = await commit(
      (l) => l.putLoanRepayment(reviewed, repayment),
      message: 'Repayment recorded',
      undo: true,
    );
    final completedNow =
        result &&
        !wasComplete &&
        ledger.loan(reviewed.id)?.completed(ledger) == true;
    if (completedNow) {
      celebratedLoanId = reviewed.id;
      showAdventureReward(
        AdventureRewardKind.loanCompleted,
        badge: hadFinalLoanBadge ? null : AdventureBadge.finalLoanRepayment,
      );
      publish();
      await _hapticIfEnabled();
    }
    return result;
  }

  Future<bool> correctLoanRepayment({
    required Entry previous,
    required int centavos,
    required String date,
    required Wallet wallet,
    String note = '',
  }) => commit(
    (l) {
      final loan = l.loan(previous.loanId ?? '');
      if (!sameEntry(l.entry(previous.id), previous) ||
          previous.deleted ||
          loan == null ||
          loan.deleted ||
          previous.loanAction != LoanAction.repayment) {
        throw const LedgerException('This repayment is no longer available.');
      }
      return l.putLoanRepayment(
        loan,
        Entry(
          id: previous.id,
          kind: EntryKind.income,
          centavos: centavos,
          date: date,
          wallet: wallet,
          note: note.trim(),
          createdAt: previous.createdAt,
          updatedAt: max(clock().millisecondsSinceEpoch, previous.updatedAt),
          loanId: loan.id,
          loanAction: LoanAction.repayment,
        ),
      );
    },
    message: 'Repayment corrected',
    undo: true,
  );

  Future<bool> removeLoan(String id) => commit(
    (l) => l.removeLoan(id, clock().millisecondsSinceEpoch),
    message: 'Loan removed',
    undo: true,
  );

  Future<bool> removeLoanRepayment(Entry entry) => commit(
    (l) {
      if (!sameEntry(l.entry(entry.id), entry)) {
        throw const LedgerException(
          'This repayment changed. Review the loan activity.',
        );
      }
      return l.deleteLoanRepayment(entry.id, clock().millisecondsSinceEpoch);
    },
    message: 'Repayment removed',
    undo: true,
  );

  Future<bool> restoreLoanRepayment(Entry entry) => commit(
    (l) {
      if (!sameEntry(l.entry(entry.id), entry)) {
        throw const LedgerException(
          'This repayment changed. Review the loan activity.',
        );
      }
      return l.restoreLoanRepayment(entry.id, clock().millisecondsSinceEpoch);
    },
    message: 'Repayment restored',
    undo: true,
  );
}
