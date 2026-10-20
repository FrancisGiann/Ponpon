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

  Future<bool> setBill(Bill value) => commit((l) {
    Bill.fromJson(value.toJson());
    final previous = l.bill(value.id);
    if (previous == null && l.bills.length >= 100) {
      throw const LedgerException(
        'Keep up to 100 bills, including paused bills.',
      );
    }
    if (previous != null &&
        (previous.startDate != value.startDate ||
            previous.frequency != value.frequency) &&
        l.entries.any((e) => e.billId == value.id)) {
      throw const LedgerException(
        'This bill has payment history. Pause it and create a new bill to change its recurrence.',
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

  Future<bool> recordBillPayment(
    Bill reviewed,
    String dueDate,
    Wallet wallet,
    Category category, {
    required bool confirmed,
  }) {
    if (!confirmed) return Future.value(false);
    return commit(
      (l) {
        final bill = l.bill(reviewed.id);
        if (bill == null ||
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
  }
}
