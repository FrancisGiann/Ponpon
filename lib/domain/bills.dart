part of 'ledger.dart';

enum BillFrequency { once, weekly, monthly, yearly }

const maxBillPayments = 20000;

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
  });
  final String id, name, startDate;
  final int centavos;
  final BillFrequency frequency;
  final int? paymentCount;
  final bool enabled, remind;

  Bill copy({
    String? name,
    int? centavos,
    String? startDate,
    BillFrequency? frequency,
    Object? paymentCount = _keepBillPaymentCount,
    bool? enabled,
    bool? remind,
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
      centavos: intField(map, 'centavos', min: 1),
      frequency: frequency,
      paymentCount: paymentCount,
      enabled: boolField(map, 'enabled', fallback: true),
      remind: boolField(map, 'remind'),
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

  bool containsDue(String value) {
    final date = localDay(value), anchor = localDay(startDate);
    if (value.compareTo(startDate) < 0) return false;
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
    return occurrence(index) == value;
  }

  String? nextDue(Ledger ledger) {
    if (!enabled) return null;
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
