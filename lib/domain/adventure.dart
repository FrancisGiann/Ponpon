import 'ledger.dart';

enum AdventureBadge { firstEntry, finishedBill, finalLoanRepayment }

extension AdventureBadgeDetails on AdventureBadge {
  String get title => switch (this) {
    AdventureBadge.firstEntry => 'First steps',
    AdventureBadge.finishedBill => 'Bill pathfinder',
    AdventureBadge.finalLoanRepayment => 'Kind return',
  };

  String get description => switch (this) {
    AdventureBadge.firstEntry => 'Record your first everyday entry.',
    AdventureBadge.finishedBill => 'Finish a fixed-term bill.',
    AdventureBadge.finalLoanRepayment => 'Record the final loan repayment.',
  };

  String get asset => switch (this) {
    AdventureBadge.firstEntry => 'assets/adventure/pixel_entry.png',
    AdventureBadge.finishedBill => 'assets/adventure/pixel_bills.png',
    AdventureBadge.finalLoanRepayment => 'assets/adventure/pixel_loans.png',
  };
}

/// Badge progress is derived from the active ledger so restore and undo stay
/// consistent without persisting duplicate achievement state.
class AdventureBadges {
  static Set<AdventureBadge> earned(Ledger ledger) => {
    if (ledger.active.any(
      (entry) =>
          entry.adjustment == null &&
          entry.billId == null &&
          entry.loanId == null,
    ))
      AdventureBadge.firstEntry,
    if (ledger.bills.any(
      (bill) =>
          bill.paymentCount != null &&
          bill.paidInstallments(ledger) >= bill.paymentCount!,
    ))
      AdventureBadge.finishedBill,
    if (ledger.activeLoans.any((loan) => loan.completed(ledger)))
      AdventureBadge.finalLoanRepayment,
  };

  static bool has(Ledger ledger, AdventureBadge badge) =>
      earned(ledger).contains(badge);
}

enum AdventureRewardKind { saved, billCompleted, loanCompleted }

class AdventureRewardEvent {
  const AdventureRewardEvent({
    required this.id,
    required this.kind,
    this.badge,
  });

  final int id;
  final AdventureRewardKind kind;
  final AdventureBadge? badge;

  String get title => switch (kind) {
    AdventureRewardKind.saved => 'Entry saved',
    AdventureRewardKind.billCompleted => 'Bill plan complete',
    AdventureRewardKind.loanCompleted => 'Loan repaid',
  };
}
