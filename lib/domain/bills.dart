part of 'ledger.dart';

enum BillFrequency { once, weekly, monthly, yearly }

class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.centavos,
    required this.startDate,
    this.frequency = BillFrequency.monthly,
    this.enabled = true,
    this.remind = false,
  });
  final String id, name, startDate;
  final int centavos;
  final BillFrequency frequency;
  final bool enabled, remind;

  Bill copy({
    String? name,
    int? centavos,
    String? startDate,
    BillFrequency? frequency,
    bool? enabled,
    bool? remind,
  }) => Bill(
    id: id,
    name: name ?? this.name,
    centavos: centavos ?? this.centavos,
    startDate: startDate ?? this.startDate,
    frequency: frequency ?? this.frequency,
    enabled: enabled ?? this.enabled,
    remind: remind ?? this.remind,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'centavos': centavos,
    'startDate': startDate,
    'frequency': frequency.name,
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
    return Bill(
      id: id,
      name: name,
      startDate: start,
      centavos: intField(map, 'centavos', min: 1),
      frequency: frequency,
      enabled: boolField(map, 'enabled', fallback: true),
      remind: boolField(map, 'remind'),
    );
  }

  String paymentId(String dueDate) =>
      'bill_${id}_${dueDate.replaceAll('-', '')}';

  // Anchor to the original day, so Jan 31 -> Feb 28 -> Mar 31 (not Mar 28).
  String? occurrence(int index) {
    if (index < 0 ||
        index > 20000 ||
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
    return switch (frequency) {
      BillFrequency.once => value == startDate,
      BillFrequency.weekly =>
        DateTime.utc(date.year, date.month, date.day)
                    .difference(
                      DateTime.utc(anchor.year, anchor.month, anchor.day),
                    )
                    .inDays %
                7 ==
            0,
      BillFrequency.monthly =>
        occurrence(
              (date.year - anchor.year) * 12 + date.month - anchor.month,
            ) ==
            value,
      BillFrequency.yearly => occurrence(date.year - anchor.year) == value,
    };
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
