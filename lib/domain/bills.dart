part of 'ledger.dart';

enum BillFrequency { once, weekly, monthly, yearly }

const maxBillPayments = 20000;
const maxActiveBills = 100;
const maxBillRecords = 20000;

class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.centavos,
    required this.startDate,
    this.frequency = BillFrequency.monthly,
    this.paymentCount,
    this.enabled = true,
    this.remind = false,
    this.deletedAt,
  });
  final String id, name, startDate;
  final int centavos;
  final BillFrequency frequency;
  final int? paymentCount;
  final bool enabled, remind;
  final int? deletedAt;
  bool get deleted => deletedAt != null;

  Bill copy({
    String? name,
    int? centavos,
    String? startDate,
    BillFrequency? frequency,
    Object? paymentCount = _keepBillPaymentCount,
    bool? enabled,
    bool? remind,
    Object? deletedAt = _keepBillDeletedAt,
  }) => Bill(
    id: id,
    name: name ?? this.name,
    centavos: centavos ?? this.centavos,
    startDate: startDate ?? this.startDate,
    frequency: frequency ?? this.frequency,
    paymentCount: identical(paymentCount, _keepBillPaymentCount)
        ? this.paymentCount
        : paymentCount as int?,
    enabled: enabled ?? this.enabled,
    remind: remind ?? this.remind,
    deletedAt: identical(deletedAt, _keepBillDeletedAt)
        ? this.deletedAt
        : deletedAt as int?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'centavos': centavos,
    'startDate': startDate,
    'frequency': frequency.name,
    'paymentCount': paymentCount,
    'enabled': enabled,
    'remind': remind,
    if (deletedAt != null) 'deletedAt': deletedAt,
  };
  factory Bill.fromJson(dynamic value) {
    final map = object(value);
    final id = idField(map, 'id');
    final name = stringField(map, 'name', max: 60).trim();
    final start = stringField(map, 'startDate', max: 10);
    localDay(start);
    final frequency = BillFrequency.values
        .where((f) => f.name == map['frequency'])
        .firstOrNull;
    if (id.length > 32 || name.isEmpty || frequency == null) {
      throw const LedgerException('A bill has invalid details.');
    }
    final rawPaymentCount = map['paymentCount'];
    final paymentCount = rawPaymentCount == null
        ? null
        : intField(map, 'paymentCount', min: 1, max: maxBillPayments);
    if (paymentCount != null &&
        frequency != BillFrequency.weekly &&
        frequency != BillFrequency.monthly) {
      throw const LedgerException(
        'Fixed installment plans support weekly or monthly bills.',
      );
    }
    final bill = Bill(
      id: id,
      name: name,
      startDate: start,
      centavos: intField(map, 'centavos', min: 1, max: maxCentavos),
      frequency: frequency,
      paymentCount: paymentCount,
      enabled: boolField(map, 'enabled', fallback: true),
      remind: boolField(map, 'remind'),
      deletedAt: map['deletedAt'] == null
          ? null
          : intField(map, 'deletedAt', max: 9000000000000000),
    );
    if (paymentCount != null && bill.lastDueDate == null) {
      throw const LedgerException(
        'The installment plan ends outside the supported date range.',
      );
    }
    return bill;
  }

  String paymentId(String dueDate) =>
      'bill_${id}_${dueDate.replaceAll('-', '')}';

  // Anchor to the original day, so Jan 31 -> Feb 28 -> Mar 31 (not Mar 28).
  String? occurrence(int index) {
    final count = paymentCount;
    if (index < 0 ||
        index > maxBillPayments ||
        count != null && index >= count ||
        frequency == BillFrequency.once && index > 0) {
      return null;
    }
    final anchor = localDay(startDate);
    final DateTime date;
    switch (frequency) {
      case BillFrequency.once:
        date = anchor;
      case BillFrequency.weekly:
        date = DateTime(anchor.year, anchor.month, anchor.day + 7 * index);
      case BillFrequency.monthly:
        final month = DateTime(anchor.year, anchor.month + index);
        date = DateTime(
          month.year,
          month.month,
          min(anchor.day, DateTime(month.year, month.month + 1, 0).day),
        );
      case BillFrequency.yearly:
        final year = anchor.year + index;
        date = DateTime(
          year,
          anchor.month,
          min(anchor.day, DateTime(year, anchor.month + 1, 0).day),
        );
    }
    return date.year > 2200 ? null : dayKey(date);
  }

  int? occurrenceIndex(String value) {
    final date = localDay(value), anchor = localDay(startDate);
    if (value.compareTo(startDate) < 0) return null;
    final index = switch (frequency) {
      BillFrequency.once => 0,
      BillFrequency.weekly =>
        DateTime.utc(date.year, date.month, date.day)
                .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
                .inDays ~/
            7,
      BillFrequency.monthly =>
        (date.year - anchor.year) * 12 + date.month - anchor.month,
      BillFrequency.yearly => date.year - anchor.year,
    };
    return occurrence(index) == value ? index : null;
  }

  bool containsDue(String value) => occurrenceIndex(value) != null;

  int? lastOccurrenceIndexOnOrBefore(String value) {
    final date = localDay(value), anchor = localDay(startDate);
    if (value.compareTo(startDate) < 0) return null;
    var index = switch (frequency) {
      BillFrequency.once => 0,
      BillFrequency.weekly =>
        DateTime.utc(date.year, date.month, date.day)
                .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
                .inDays ~/
            7,
      BillFrequency.monthly =>
        (date.year - anchor.year) * 12 + date.month - anchor.month,
      BillFrequency.yearly => date.year - anchor.year,
    };
    index = min(index, maxBillPayments);
    final count = paymentCount;
    if (count != null) index = min(index, count - 1);
    while (index >= 0) {
      final due = occurrence(index);
      if (due != null && due.compareTo(value) <= 0) return index;
      index--;
    }
    return null;
  }

  String? nextDue(Ledger ledger) {
    if (!enabled || deleted) return null;
    final paid = ledger._paidBillDates[id] ?? const <String>{};
    for (var i = 0; i <= paid.length; i++) {
      final date = occurrence(i);
      if (date == null || !paid.contains(date)) return date;
    }
    return null;
  }

  int paidInstallments(Ledger ledger) =>
      ledger.billPaidDates(id).where(containsDue).length;

  int remainingCentavos(Ledger ledger) =>
      ((paymentCount ?? 0) - paidInstallments(ledger)) * centavos;

  String? get lastDueDate {
    final count = paymentCount;
    return count == null ? null : occurrence(count - 1);
  }
}

class BillDueGroup {
  const BillDueGroup({
    required this.bill,
    required this.lastDueIndex,
    required this.paidIndices,
  });

  final Bill bill;
  final int lastDueIndex;
  final List<int> paidIndices;
  int get unpaidCount => lastDueIndex + 1 - paidIndices.length;
  int get totalCentavos => bill.centavos * unpaidCount;

  String dueDateAt(int unpaidIndex) {
    if (unpaidIndex < 0 || unpaidIndex >= unpaidCount) {
      throw RangeError.index(unpaidIndex, this, 'unpaidIndex');
    }
    var low = unpaidIndex;
    var high = unpaidIndex + paidIndices.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      final paidThrough = _upperBound(paidIndices, middle);
      final unpaidThrough = middle + 1 - paidThrough;
      if (unpaidThrough >= unpaidIndex + 1) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return bill.occurrence(low)!;
  }

  static int _upperBound(List<int> values, int target) {
    var low = 0, high = values.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (values[middle] <= target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

class BillDueOccurrence {
  const BillDueOccurrence({required this.bill, required this.dueDate});
  final Bill bill;
  final String dueDate;
  int get centavos => bill.centavos;
}

class SafeToSpendSummary {
  SafeToSpendSummary({
    required this.activeWalletCount,
    required this.walletBalanceCentavos,
    required this.throughDate,
    required List<BillDueGroup> dueBills,
  }) : dueBills = List.unmodifiable(dueBills);

  final int activeWalletCount, walletBalanceCentavos;
  final DateTime throughDate;
  final List<BillDueGroup> dueBills;
  int get duePaymentCount =>
      dueBills.fold(0, (sum, group) => sum + group.unpaidCount);
  int get dueCentavos =>
      dueBills.fold(0, (sum, group) => sum + group.totalCentavos);
  int? get safeCentavos =>
      activeWalletCount == 0 ? null : walletBalanceCentavos - dueCentavos;
  String? get nearestDueDate =>
      dueBills.isEmpty ? null : dueBills.first.dueDateAt(0);

  BillDueOccurrence occurrenceAt(int index) {
    if (index < 0 || index >= duePaymentCount) {
      throw RangeError.index(index, this, 'index');
    }
    var offset = index;
    for (final group in dueBills) {
      if (offset < group.unpaidCount) {
        return BillDueOccurrence(
          bill: group.bill,
          dueDate: group.dueDateAt(offset),
        );
      }
      offset -= group.unpaidCount;
    }
    throw StateError('The due payment index is inconsistent.');
  }
}

extension SafeToSpend on Ledger {
  SafeToSpendSummary safeToSpend(DateTime now) {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final through = DateTime(today.year, today.month, today.day + 7);
    final throughKey = dayKey(through);
    final dueBills = <BillDueGroup>[];

    for (final bill in bills) {
      if (!bill.enabled || bill.deleted) continue;
      final lastDueIndex = bill.lastOccurrenceIndexOnOrBefore(throughKey);
      if (lastDueIndex == null) continue;
      final paidIndices = [
        for (final paidDate in billPaidDates(bill.id))
          if (paidDate.compareTo(throughKey) <= 0)
            if (bill.occurrenceIndex(paidDate) case final int index) index,
      ]..sort();
      final group = BillDueGroup(
        bill: bill,
        lastDueIndex: lastDueIndex,
        paidIndices: List.unmodifiable(paidIndices),
      );
      if (group.unpaidCount > 0) dueBills.add(group);
    }

    dueBills.sort((a, b) {
      final date = a.dueDateAt(0).compareTo(b.dueDateAt(0));
      return date != 0 ? date : a.bill.id.compareTo(b.bill.id);
    });
    return SafeToSpendSummary(
      activeWalletCount: availableWallets.length,
      walletBalanceCentavos: activeWalletBalance,
      throughDate: through,
      dueBills: dueBills,
    );
  }
}

class BalanceAdjustment {
  const BalanceAdjustment({required this.expected, required this.actual});
  final int expected, actual;
  int get difference => actual - expected;
  Map<String, dynamic> toJson() => {'expected': expected, 'actual': actual};
  factory BalanceAdjustment.fromJson(dynamic value) {
    final map = object(value);
    final result = BalanceAdjustment(
      expected: intField(
        map,
        'expected',
        min: -9000000000000000,
        max: 9000000000000000,
      ),
      actual: intField(map, 'actual', min: -maxCentavos),
    );
    if (result.difference == 0 || result.difference.abs() > maxCentavos) {
      throw const LedgerException(
        'This balance difference cannot be recorded.',
      );
    }
    return result;
  }
}

class BalanceCheck {
  BalanceCheck({
    required this.wallet,
    required this.expected,
    required this.actual,
  }) : id = newId();
  final String id;
  final Wallet wallet;
  final int expected, actual;
  int get difference => actual - expected;
}
