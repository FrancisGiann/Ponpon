part of 'ledger.dart';

String previousDay(String day) {
  final d = localDay(day);
  return dayKey(DateTime(d.year, d.month, d.day - 1));
}

String nextDay(String day) {
  final d = localDay(day);
  return dayKey(DateTime(d.year, d.month, d.day + 1));
}

class AllowanceSchedule {
  AllowanceSchedule({
    required this.id,
    required this.centavos,
    required this.wallet,
    required List<int> days,
    required this.startDate,
    required this.processedThrough,
    this.enabled = false,
  }) : days = List.unmodifiable(days.toList()..sort());
  final String id, startDate, processedThrough;
  final int centavos;
  final Wallet wallet;
  final List<int> days;
  final bool enabled;
  AllowanceSchedule copy({
    int? centavos,
    Wallet? wallet,
    List<int>? days,
    String? startDate,
    String? processedThrough,
    bool? enabled,
  }) => AllowanceSchedule(
    id: id,
    centavos: centavos ?? this.centavos,
    wallet: wallet ?? this.wallet,
    days: days ?? this.days,
    startDate: startDate ?? this.startDate,
    processedThrough: processedThrough ?? this.processedThrough,
    enabled: enabled ?? this.enabled,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'centavos': centavos,
    'wallet': wallet.id,
    'days': days,
    'startDate': startDate,
    'processedThrough': processedThrough,
    'enabled': enabled,
  };
  factory AllowanceSchedule.fromJson(dynamic v) {
    final m = object(v), id = idField(object(v), 'id');
    final days = m['days'];
    final start = stringField(m, 'startDate', max: 10),
        through = stringField(m, 'processedThrough', max: 10);
    localDay(start);
    localDay(through);
    if (id.length > 32 ||
        days is! List ||
        days.isEmpty ||
        days.length > 7 ||
        days.any((d) => d is! int || d < 1 || d > 7) ||
        days.toSet().length != days.length) {
      throw const LedgerException('The allowance schedule is invalid.');
    }
    return AllowanceSchedule(
      id: id,
      centavos: intField(m, 'centavos', min: 1),
      wallet: walletField(m['wallet']),
      days: List<int>.from(days),
      startDate: start,
      processedThrough: through,
      enabled: boolField(m, 'enabled'),
    );
  }
  String occurrenceId(String day) => 'allow_${id}_${day.replaceAll('-', '')}';
  String? nextOccurrence(String today) {
    if (processedThrough == '2200-12-31') return null;
    var day = today.compareTo(processedThrough) > 0
        ? today
        : nextDay(processedThrough);
    if (day.compareTo(startDate) < 0) day = startDate;
    for (var i = 0; i < 7; i++) {
      if (days.contains(localDay(day).weekday)) return day;
      if (day == '2200-12-31') return null;
      day = nextDay(day);
    }
    return null;
  }
}

class AllowanceCatchUp {
  const AllowanceCatchUp(this.ledger, this.count, {this.paused = false});
  final Ledger ledger;
  final int count;
  final bool paused;
}

AllowanceCatchUp catchUpAllowance(Ledger original, DateTime now) {
  final s = original.allowance, today = dayKey(now);
  if (s == null ||
      !s.enabled ||
      today.compareTo(s.processedThrough) <= 0 ||
      today.compareTo(s.startDate) < 0) {
    return AllowanceCatchUp(original, 0);
  }
  var day = nextDay(s.processedThrough);
  if (day.compareTo(s.startDate) < 0) day = s.startDate;
  // Compare calendar dates in UTC only to count days, never shift a stored date.
  final a = localDay(day), b = localDay(today);
  final span =
      DateTime.utc(
        b.year,
        b.month,
        b.day,
      ).difference(DateTime.utc(a.year, a.month, a.day)).inDays +
      1;
  if (span > 31) {
    return AllowanceCatchUp(
      original.copy(allowance: s.copy(enabled: false, processedThrough: today)),
      0,
      paused: true,
    );
  }
  final wallet = original.wallet(s.wallet);
  if (wallet == null || wallet.archived) {
    throw const LedgerException('Choose an active allowance wallet.');
  }
  var ledger = original;
  var count = 0;
  while (day.compareTo(today) <= 0) {
    if (s.days.contains(localDay(day).weekday) &&
        ledger.entry(s.occurrenceId(day)) == null) {
      final builtin = ledger.category('income_allowance');
      var category = builtin != null
          ? (!builtin.archived && builtin.isIncome ? builtin : null)
          : null;
      category ??= ledger.availableCategories
          .where((c) => c.isIncome && c.name.toLowerCase() == 'allowance')
          .firstOrNull;
      if (category == null &&
          builtin == null &&
          ledger.categories.length < 100) {
        category = defaultIncomeCategories.firstWhere(
          (c) => c.id == 'income_allowance',
        );
        ledger = ledger.copy(categories: [...ledger.categories, category]);
      }
      category ??= ledger.availableCategories
          .where((c) => c.isIncome)
          .firstOrNull;
      if (category == null) {
        throw const LedgerException(
          'Choose an active income category before recording allowance.',
        );
      }
      final timestamp = now.millisecondsSinceEpoch;
      ledger = ledger.put(
        Entry(
          id: s.occurrenceId(day),
          kind: EntryKind.income,
          centavos: s.centavos,
          date: day,
          wallet: wallet,
          categoryId: category.id,
          note: 'Scheduled allowance',
          createdAt: timestamp,
          updatedAt: timestamp,
          scheduleId: s.id,
          occurrenceDate: day,
        ),
      );
      count++;
    }
    if (day == today) break;
    day = nextDay(day);
  }
  return AllowanceCatchUp(
    ledger.copy(allowance: s.copy(processedThrough: today)),
    count,
  );
}
