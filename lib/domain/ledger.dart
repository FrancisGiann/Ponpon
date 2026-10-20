import 'dart:convert';
import 'dart:math';

part 'wallet.dart';
part 'allowance.dart';
part 'bills.dart';

const schemaVersion = 5;
const _keepAllowance = Object();
const maxCentavos = 99999999999;
const maxBackupBytes = 5 * 1024 * 1024;

class LedgerException implements Exception {
  const LedgerException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum EntryKind { expense, income, transfer }

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

int parseMoney(String input, {bool signed = false, bool allowZero = false}) {
  final value = input.trim();
  final pattern = signed
      ? r'^-?\d{1,9}(?:\.\d{0,2})?$'
      : r'^\d{1,9}(?:\.\d{0,2})?$';
  if (!RegExp(pattern).hasMatch(value)) {
    throw const LedgerException(
      'Enter an amount with at most two decimal places.',
    );
  }
  final negative = value.startsWith('-');
  final parts = (negative ? value.substring(1) : value).split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '00' : parts[1].padRight(2, '0'));
  if (cents > maxCentavos || (!allowZero && cents == 0)) {
    throw const LedgerException(
      'Enter an amount greater than zero, up to ₱999,999,999.99.',
    );
  }
  return negative ? -cents : cents;
}

String money(int cents, {bool symbol = true}) {
  final absolute = cents.abs();
  final whole = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${cents < 0 ? '−' : ''}${symbol ? '₱' : ''}$whole.${(absolute % 100).toString().padLeft(2, '0')}';
}

String moneyInput(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String monthKey(DateTime date) => dayKey(date).substring(0, 7);
DateTime localDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const LedgerException('A transaction date is invalid.');
  }
  final parts = value.split('-').map(int.parse).toList();
  final result = DateTime(parts[0], parts[1], parts[2]);
  if (dayKey(result) != value || result.year < 1900 || result.year > 2200) {
    throw const LedgerException('A transaction date is invalid.');
  }
  return result;
}

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
String shortDate(String value) {
  final date = localDay(value);
  return '${date.day} ${monthNames[date.month - 1].substring(0, 3)} ${date.year}';
}

Map<String, dynamic> object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const LedgerException('The backup contains an invalid record.');
  }
  return value;
}

String stringField(Map<String, dynamic> map, String key, {int max = 500}) {
  final value = map[key];
  if (value is! String || value.length > max || value.contains('\u0000')) {
    throw LedgerException('The backup contains an invalid $key.');
  }
  return value;
}

int intField(
  Map<String, dynamic> map,
  String key, {
  int min = 0,
  int max = maxCentavos,
}) {
  final value = map[key];
  if (value is! int || value < min || value > max) {
    throw LedgerException('The backup contains an invalid $key.');
  }
  return value;
}

String idField(Map<String, dynamic> map, String key) {
  final value = stringField(map, key, max: 80);
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(value)) {
    throw const LedgerException('The backup contains an invalid identifier.');
  }
  return value;
}

bool boolField(Map<String, dynamic> map, String key, {bool fallback = false}) {
  if (map[key] == null) return fallback;
  if (map[key] is! bool) {
    throw LedgerException('The backup contains an invalid $key.');
  }
  return map[key] as bool;
}

Wallet walletField(dynamic value) {
  if (value is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(value)) {
    throw const LedgerException(
      'The backup contains an invalid wallet identifier.',
    );
  }
  return Wallet.reference(value);
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    this.archived = false,
  });
  final String id;
  final String name;
  final String icon;
  final bool archived;
  // Existing category IDs and records stay intact. The income pictogram also
  // classifies user-created income categories without a backup schema change.
  bool get isIncome => id == 'income' || icon == 'income';
  Category copy({String? name, String? icon, bool? archived}) => Category(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    archived: archived ?? this.archived,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'archived': archived,
  };
  factory Category.fromJson(dynamic value) {
    final map = object(value);
    final name = stringField(map, 'name', max: 30).trim();
    if (name.isEmpty) throw const LedgerException('A category needs a name.');
    final icon = stringField(map, 'icon', max: 30);
    if (!categoryIcons.contains(icon)) {
      throw const LedgerException('A category icon is unknown.');
    }
    return Category(
      id: idField(map, 'id'),
      name: name,
      icon: icon,
      archived: boolField(map, 'archived'),
    );
  }
}

const categoryIcons = [
  'food',
  'travel',
  'bills',
  'shopping',
  'health',
  'fun',
  'home',
  'income',
  'other',
  'school',
];
const schoolSuppliesCategory = Category(
  id: 'school_supplies',
  name: 'School supplies',
  icon: 'school',
);
const defaultIncomeCategories = [
  Category(id: 'income', name: 'General income', icon: 'income'),
  Category(id: 'income_allowance', name: 'Allowance', icon: 'income'),
  Category(id: 'income_salary', name: 'Salary', icon: 'income'),
  Category(id: 'income_gift', name: 'Gift', icon: 'income'),
  Category(id: 'income_other', name: 'Other income', icon: 'income'),
];
const defaultCategories = [
  Category(id: 'food', name: 'Food', icon: 'food'),
  Category(id: 'travel', name: 'Travel', icon: 'travel'),
  Category(id: 'bills', name: 'Bills', icon: 'bills'),
  Category(id: 'shopping', name: 'Shopping', icon: 'shopping'),
  Category(id: 'health', name: 'Health', icon: 'health'),
  Category(id: 'fun', name: 'Leisure', icon: 'fun'),
  ...defaultIncomeCategories,
  schoolSuppliesCategory,
  Category(id: 'other', name: 'Other', icon: 'other'),
];

// Stable display-only partition: preserve every other category's relative order.
// Match identity/type so renamed Other stays last and income choices stay intact.
List<T> otherExpenseLast<T>(
  Iterable<T> items,
  Category Function(T) categoryOf,
) {
  final values = items.toList();
  bool isOther(T item) {
    final category = categoryOf(item);
    return category.id == 'other' && !category.isIncome;
  }

  return [...values.where((item) => !isOther(item)), ...values.where(isOther)];
}

class Entry {
  const Entry({
    required this.id,
    required this.kind,
    required this.centavos,
    required this.date,
    required this.wallet,
    required this.createdAt,
    required this.updatedAt,
    this.toWallet,
    this.categoryId,
    this.note = '',
    this.deletedAt,
    this.scheduleId,
    this.occurrenceDate,
    this.billId,
    this.billDueDate,
    this.adjustment,
  });
  final String id;
  final EntryKind kind;
  final int centavos;
  final String date;
  final Wallet wallet;
  final Wallet? toWallet;
  final String? categoryId;
  final String note;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String? scheduleId, occurrenceDate;
  final String? billId, billDueDate;
  final BalanceAdjustment? adjustment;
  bool get deleted => deletedAt != null;
  Entry withDeletion(int? timestamp) => Entry(
    id: id,
    kind: kind,
    centavos: centavos,
    date: date,
    wallet: wallet,
    toWallet: toWallet,
    categoryId: categoryId,
    note: note,
    createdAt: createdAt,
    updatedAt: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    deletedAt: timestamp,
    scheduleId: scheduleId,
    occurrenceDate: occurrenceDate,
    billId: billId,
    billDueDate: billDueDate,
    adjustment: adjustment,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'centavos': centavos,
    'date': date,
    'wallet': wallet.name,
    'toWallet': toWallet?.name,
    'categoryId': categoryId,
    'note': note,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'scheduleId': scheduleId,
    'occurrenceDate': occurrenceDate,
    if (billId != null) 'billId': billId,
    if (billDueDate != null) 'billDueDate': billDueDate,
    if (adjustment != null) 'adjustment': adjustment!.toJson(),
  };
  factory Entry.fromJson(dynamic value) {
    final map = object(value);
    final kindValue = stringField(map, 'kind', max: 10);
    final kind = EntryKind.values.where((k) => k.name == kindValue).firstOrNull;
    if (kind == null) {
      throw const LedgerException(
        'The backup contains an unknown transaction type.',
      );
    }
    final date = stringField(map, 'date', max: 10);
    localDay(date);
    final wallet = walletField(map['wallet']);
    final toWallet = map['toWallet'] == null
        ? null
        : walletField(map['toWallet']);
    final category = map['categoryId'] == null
        ? null
        : idField(map, 'categoryId');
    final adjustment = map['adjustment'] == null
        ? null
        : BalanceAdjustment.fromJson(map['adjustment']);
    if (kind == EntryKind.transfer
        ? (toWallet == null ||
              wallet == toWallet ||
              category != null ||
              adjustment != null)
        : (toWallet != null ||
              (adjustment == null ? category == null : category != null))) {
      throw const LedgerException(
        'A transaction has invalid category or transfer wallets.',
      );
    }
    final createdAt = intField(map, 'createdAt', max: 9000000000000000);
    final updatedAt = intField(map, 'updatedAt', max: 9000000000000000);
    if (updatedAt < createdAt) {
      throw const LedgerException('A transaction has invalid change dates.');
    }
    final origin = map['scheduleId'] == null
        ? null
        : idField(map, 'scheduleId');
    final occurrence = map['occurrenceDate'] == null
        ? null
        : stringField(map, 'occurrenceDate', max: 10);
    if ((origin == null) != (occurrence == null)) {
      throw const LedgerException('An allowance occurrence is invalid.');
    }
    if (origin != null) {
      localDay(occurrence!);
      if (origin.length > 32 ||
          map['id'] != 'allow_${origin}_${occurrence.replaceAll('-', '')}') {
        throw const LedgerException(
          'An allowance occurrence identifier is invalid.',
        );
      }
    }
    final billId = map['billId'] == null ? null : idField(map, 'billId');
    final billDate = map['billDueDate'] == null
        ? null
        : stringField(map, 'billDueDate', max: 10);
    if ((billId == null) != (billDate == null)) {
      throw const LedgerException('A bill payment origin is invalid.');
    }
    if (billId != null) {
      localDay(billDate!);
      if (billId.length > 32 ||
          kind != EntryKind.expense ||
          adjustment != null ||
          origin != null ||
          map['id'] != 'bill_${billId}_${billDate.replaceAll('-', '')}') {
        throw const LedgerException('A bill payment identifier is invalid.');
      }
    }
    if (adjustment != null &&
        (origin != null ||
            intField(map, 'centavos', min: 1) != adjustment.difference.abs() ||
            kind !=
                (adjustment.difference > 0
                    ? EntryKind.income
                    : EntryKind.expense))) {
      throw const LedgerException('A balance adjustment is inconsistent.');
    }
    return Entry(
      billId: billId,
      billDueDate: billDate,
      adjustment: adjustment,
      scheduleId: origin,
      occurrenceDate: occurrence,
      id: idField(map, 'id'),
      kind: kind,
      centavos: intField(map, 'centavos', min: 1),
      date: date,
      wallet: wallet,
      toWallet: toWallet,
      categoryId: category,
      note: stringField(map, 'note'),
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: map['deletedAt'] == null
          ? null
          : intField(map, 'deletedAt', max: 9000000000000000),
    );
  }
}

class Preferences {
  const Preferences({
    this.welcomed = false,
    this.theme = 'system',
    this.reduceMotion = false,
    this.haptics = true,
    this.privatePreview = true,
    this.balanceWidgetVisible = false,
    this.widgetCategories = const ['food', 'travel', 'bills', 'shopping'],
    this.quickWallets = const ['cash', 'gcash'],
  });
  final bool welcomed;
  final String theme;
  final bool reduceMotion;
  final bool haptics;
  final bool privatePreview;
  final bool balanceWidgetVisible;
  final List<String> widgetCategories, quickWallets;
  Preferences copy({
    bool? welcomed,
    String? theme,
    bool? reduceMotion,
    bool? haptics,
    bool? privatePreview,
    bool? balanceWidgetVisible,
    List<String>? widgetCategories,
    List<String>? quickWallets,
  }) => Preferences(
    welcomed: welcomed ?? this.welcomed,
    theme: theme ?? this.theme,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    haptics: haptics ?? this.haptics,
    privatePreview: privatePreview ?? this.privatePreview,
    balanceWidgetVisible: balanceWidgetVisible ?? this.balanceWidgetVisible,
    quickWallets: List.unmodifiable(quickWallets ?? this.quickWallets),
    widgetCategories: List.unmodifiable(
      widgetCategories ?? this.widgetCategories,
    ),
  );
  Map<String, dynamic> toJson() => {
    'welcomed': welcomed,
    'theme': theme,
    'reduceMotion': reduceMotion,
    'haptics': haptics,
    'privatePreview': privatePreview,
    'balanceWidgetVisible': balanceWidgetVisible,
    'widgetCategories': widgetCategories,
    'quickWallets': quickWallets,
  };
  factory Preferences.fromJson(dynamic value) {
    final map = object(value);
    final theme = stringField(map, 'theme', max: 10);
    if (!['system', 'light', 'dark'].contains(theme)) {
      throw const LedgerException('The backup theme is invalid.');
    }
    final ids = map['widgetCategories'];
    if (ids is! List ||
        ids.length > 4 ||
        ids.any((id) => id is! String) ||
        ids.toSet().length != ids.length) {
      throw const LedgerException('The widget category selection is invalid.');
    }
    final quick = map['quickWallets'] ?? ['cash', 'gcash'];
    if (quick is! List ||
        quick.length > 20 ||
        quick.any((id) => id is! String) ||
        quick.toSet().length != quick.length) {
      throw const LedgerException('The preferred wallets are invalid.');
    }
    return Preferences(
      quickWallets: List<String>.unmodifiable(quick),
      welcomed: boolField(map, 'welcomed'),
      theme: theme,
      reduceMotion: boolField(map, 'reduceMotion'),
      haptics: boolField(map, 'haptics', fallback: true),
      privatePreview: boolField(map, 'privatePreview', fallback: true),
      balanceWidgetVisible: boolField(
        map,
        'balanceWidgetVisible',
        fallback: false,
      ),
      widgetCategories: List<String>.unmodifiable(ids),
    );
  }
}

bool sameEntry(Entry? a, Entry? b) =>
    jsonEncode(a?.toJson()) == jsonEncode(b?.toJson());

class Change {
  const Change({required this.after, this.before});
  final Entry? before;
  final Entry after;
  Map<String, dynamic> toJson() => {
    'before': before?.toJson(),
    'after': after.toJson(),
  };
  factory Change.fromJson(dynamic value) {
    final map = object(value);
    final after = Entry.fromJson(map['after']);
    final before = map['before'] == null ? null : Entry.fromJson(map['before']);
    if (before != null && before.id != after.id) {
      throw const LedgerException('A change record is invalid.');
    }
    return Change(before: before, after: after);
  }
}

class WalletCalculation {
  const WalletCalculation(
    this.opening,
    this.income,
    this.expenses,
    this.incoming,
    this.outgoing, [
    this.adjustments = 0,
  ]);
  final int opening, income, expenses, incoming, outgoing, adjustments;
  int get balance =>
      opening + income - expenses + incoming - outgoing + adjustments;
}

class Ledger {
  Ledger({
    required List<Category> categories,
    required List<Entry> entries,
    required Map<Wallet, int> openings,
    required Map<String, int> budgets,
    Preferences? preferences,
    List<Change> changes = const [],
    List<Wallet> wallets = Wallet.values,
    List<Bill> bills = const [],
    this.allowance,
  }) : categories = List.unmodifiable(categories),
       entries = List.unmodifiable(entries),
       openings = Map.unmodifiable(openings),
       budgets = Map.unmodifiable(budgets),
       preferences = preferences ?? const Preferences(),
       changes = List.unmodifiable(changes),
       wallets = List.unmodifiable(wallets),
       bills = List.unmodifiable(bills);
  factory Ledger.empty() => Ledger(
    categories: defaultCategories,
    entries: [],
    openings: {Wallet.cash: 0, Wallet.gcash: 0},
    budgets: {},
  );
  final List<Category> categories;
  final List<Entry> entries;
  final Map<Wallet, int> openings;
  final Map<String, int> budgets;
  final Preferences preferences;
  final List<Change> changes;
  final List<Wallet> wallets;
  final AllowanceSchedule? allowance;
  final List<Bill> bills;
  Bill? bill(String id) => bills.where((b) => b.id == id).firstOrNull;
  late final Map<String, Set<String>> _paidBillDates = () {
    final dates = <String, Set<String>>{};
    for (final entry in active) {
      if (entry.billId != null && entry.billDueDate != null) {
        dates
            .putIfAbsent(entry.billId!, () => <String>{})
            .add(entry.billDueDate!);
      }
    }
    return dates;
  }();
  Set<String> billPaidDates(String id) =>
      Set.unmodifiable(_paidBillDates[id] ?? const <String>{});
  // Ledger snapshots are immutable. Derived indexes belong to one snapshot and
  // disappear naturally when an edit/restore creates its replacement.
  late final Map<String, Wallet> _walletIndex = {
    for (final w in wallets) w.id: w,
  };
  late final Map<String, Category> _categoryIndex = {
    for (final c in categories) c.id: c,
  };
  late final Map<String, Entry> _entryIndex = {
    for (final e in entries) e.id: e,
  };
  Wallet? wallet(Wallet? ref) => _walletIndex[ref?.id];
  bool hasWalletHistory(Wallet wallet) =>
      (openings[wallet] ?? 0) != 0 ||
      allowance?.wallet == wallet ||
      entries.any((e) => e.wallet == wallet || e.toWallet == wallet) ||
      changes.any(
        (c) =>
            c.after.wallet == wallet ||
            c.after.toWallet == wallet ||
            c.before?.wallet == wallet ||
            c.before?.toWallet == wallet,
      );
  late final List<Wallet> availableWallets = List.unmodifiable(
    wallets.where((w) => !w.archived),
  );
  late final int activeWalletBalance = availableWallets.fold(
    0,
    (sum, wallet) => sum + calculate(wallet).balance,
  );
  late final List<Wallet> quickWallets = List.unmodifiable(
    preferences.quickWallets
        .map((id) => _walletIndex[id])
        .whereType<Wallet>()
        .where((w) => !w.archived),
  );
  late final List<Entry> active = List.unmodifiable(
    entries.where((e) => !e.deleted).toList()..sort((a, b) {
      final date = b.date.compareTo(a.date);
      return date == 0 ? b.createdAt.compareTo(a.createdAt) : date;
    }),
  );
  late final List<Category> availableCategories = List.unmodifiable(
    otherExpenseLast(categories.where((c) => !c.archived), (c) => c),
  );
  Category? category(String? id) => _categoryIndex[id];
  List<Category> categoriesFor(EntryKind kind) {
    if (kind == EntryKind.transfer) return const [];
    if (kind == EntryKind.expense) {
      return otherExpenseLast([
        ...availableCategories.where((c) => !c.isIncome),
        if (category(schoolSuppliesCategory.id) == null) schoolSuppliesCategory,
      ], (c) => c);
    }
    // Missing built-ins are offered to older ledgers and inserted atomically
    // with a saved entry. Merely changing type never changes ledger history.
    return [
      for (final builtin in defaultIncomeCategories)
        if (category(builtin.id) == null)
          builtin
        else if (!category(builtin.id)!.archived &&
            category(builtin.id)!.isIncome)
          category(builtin.id)!.name == 'Income' && builtin.id == 'income'
              ? category(builtin.id)!.copy(name: 'General income')
              : category(builtin.id)!,
      ...availableCategories.where(
        (c) => c.isIncome && !defaultIncomeCategories.any((b) => b.id == c.id),
      ),
    ];
  }

  Entry? entry(String id) => _entryIndex[id];
  final Map<Wallet, WalletCalculation> _walletCalculations = {};
  final Map<(EntryKind, String?, String?, String?), int> _totals = {};
  Ledger copy({
    List<Category>? categories,
    List<Entry>? entries,
    Map<Wallet, int>? openings,
    Map<String, int>? budgets,
    Preferences? preferences,
    List<Change>? changes,
    List<Wallet>? wallets,
    List<Bill>? bills,
    Object? allowance = _keepAllowance,
  }) => Ledger(
    categories: categories ?? this.categories,
    entries: entries ?? this.entries,
    openings: openings ?? this.openings,
    budgets: budgets ?? this.budgets,
    preferences: preferences ?? this.preferences,
    changes: changes ?? this.changes,
    wallets: wallets ?? this.wallets,
    bills: bills ?? this.bills,
    allowance: identical(allowance, _keepAllowance)
        ? this.allowance
        : allowance as AllowanceSchedule?,
  );
  WalletCalculation calculate(Wallet wallet) => _walletCalculations.putIfAbsent(
    wallet,
    () {
      var income = 0, expenses = 0, incoming = 0, outgoing = 0, adjustments = 0;
      for (final e in entries.where((e) => !e.deleted)) {
        if (e.adjustment != null) {
          if (e.wallet == wallet) adjustments += e.adjustment!.difference;
        } else if (e.kind == EntryKind.transfer) {
          if (e.wallet == wallet) outgoing += e.centavos;
          if (e.toWallet == wallet) incoming += e.centavos;
        } else if (e.wallet == wallet) {
          if (e.kind == EntryKind.income) {
            income += e.centavos;
          } else {
            expenses += e.centavos;
          }
        }
      }
      return WalletCalculation(
        openings[wallet] ?? 0,
        income,
        expenses,
        incoming,
        outgoing,
        adjustments,
      );
    },
  );

  int total(EntryKind kind, {String? month, String? date, String? categoryId}) {
    if (_totals.length >= 512) _totals.clear();
    return _totals.putIfAbsent(
      (kind, month, date, categoryId),
      () => entries
          .where(
            (e) =>
                !e.deleted &&
                e.adjustment == null &&
                e.kind == kind &&
                (month == null || e.date.startsWith(month)) &&
                (date == null || e.date == date) &&
                (categoryId == null || e.categoryId == categoryId),
          )
          .fold(0, (sum, e) => sum + e.centavos),
    );
  }

  Ledger put(
    Entry next, {
    bool editing = false,
    bool restoringPayment = false,
  }) {
    Entry.fromJson(next.toJson());
    final previous = entry(next.id);
    final retainsWallets =
        editing &&
        previous != null &&
        next.kind == previous.kind &&
        next.wallet == previous.wallet &&
        next.toWallet == previous.toWallet;
    if (wallet(next.wallet) == null ||
        next.toWallet != null && wallet(next.toWallet) == null ||
        !retainsWallets &&
            (wallet(next.wallet)?.archived != false ||
                (next.toWallet != null &&
                    wallet(next.toWallet)?.archived != false))) {
      throw const LedgerException('Choose active wallets before saving.');
    }
    if (restoringPayment &&
        (previous == null ||
            !previous.deleted ||
            next.billId == null ||
            previous.billId != next.billId ||
            previous.billDueDate != next.billDueDate)) {
      throw const LedgerException(
        'This bill payment cannot be recorded again.',
      );
    }
    if (previous != null && !editing && !restoringPayment) {
      if (sameEntry(previous, next)) return this;
      throw const LedgerException(
        'This entry was already saved. Open History to edit it.',
      );
    }
    if (editing && (previous == null || previous.deleted)) {
      throw const LedgerException('This entry is no longer available to edit.');
    }
    if (next.categoryId != null &&
        (category(next.categoryId) == null ||
            category(next.categoryId)!.archived)) {
      throw const LedgerException('Choose an available category.');
    }
    if (entries.length >= 20000 && previous == null) {
      throw const LedgerException(
        'This ledger is full. Export a backup before starting another ledger.',
      );
    }
    return copy(
      entries: [...entries.where((e) => e.id != next.id), next],
      changes: [
        ...changes,
        Change(before: previous, after: next),
      ].reversed.take(30).toList().reversed.toList(),
    );
  }

  Ledger delete(String id, int now) {
    final before = entry(id);
    if (before == null || before.deleted) return this;
    final after = before.withDeletion(max(now, before.updatedAt));
    return copy(
      entries: [
        for (final e in entries)
          if (e.id == id) after else e,
      ],
      changes: [
        ...changes,
        Change(before: before, after: after),
      ].reversed.take(30).toList().reversed.toList(),
    );
  }

  Ledger restoreDeleted(String id, int now) {
    final before = entry(id);
    if (before == null || !before.deleted) return this;
    final after = Entry(
      id: before.id,
      kind: before.kind,
      centavos: before.centavos,
      date: before.date,
      wallet: before.wallet,
      toWallet: before.toWallet,
      categoryId: before.categoryId,
      note: before.note,
      createdAt: before.createdAt,
      updatedAt: max(now, before.updatedAt),
      scheduleId: before.scheduleId,
      occurrenceDate: before.occurrenceDate,
      billId: before.billId,
      billDueDate: before.billDueDate,
      adjustment: before.adjustment,
    );
    return copy(
      entries: [
        for (final e in entries)
          if (e.id == id) after else e,
      ],
      changes: [
        ...changes,
        Change(before: before, after: after),
      ].reversed.take(30).toList().reversed.toList(),
    );
  }

  Ledger undo(int now) {
    if (changes.isEmpty) {
      throw const LedgerException('There is no transaction change to undo.');
    }
    final change = changes.last;
    if (!sameEntry(entry(change.after.id), change.after)) {
      throw const LedgerException(
        'This entry changed again. Review it in History.',
      );
    }
    final restored =
        change.before ??
        change.after.withDeletion(max(now, change.after.updatedAt));
    return copy(
      entries: [
        for (final e in entries)
          if (e.id == restored.id) restored else e,
      ],
      changes: changes.sublist(0, changes.length - 1),
    );
  }

  Map<String, dynamic> toJson() => {
    'application': 'pocket_entry',
    'schemaVersion': schemaVersion,
    'currency': 'PHP',
    'categories': categories.map((c) => c.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'wallets': wallets.map((w) => w.toJson()).toList(),
    'allowance': allowance?.toJson(),
    'bills': bills.map((b) => b.toJson()).toList(),
    'openings': {for (final w in wallets) w.name: openings[w] ?? 0},
    'budgets': budgets,
    'preferences': preferences.toJson(),
    'changes': changes.map((c) => c.toJson()).toList(),
  };
  String encode() => jsonEncode(toJson());
  factory Ledger.decode(String text) {
    if (utf8.encode(text).length > maxBackupBytes) {
      throw const LedgerException('Choose a Ponpon backup smaller than 5 MB.');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const LedgerException(
        'This file is not valid JSON. Choose a Ponpon backup.',
      );
    }
    var map = object(decoded);
    if (map['application'] != 'pocket_entry' || map['currency'] != 'PHP') {
      throw const LedgerException('Choose a PHP backup made by Ponpon.');
    }
    final version = map['schemaVersion'];
    if (version is! int) {
      throw const LedgerException('The backup schema version is invalid.');
    }
    if (version == 1) map = migrateV1(map);
    if (version == 1 || version == 2) {
      map = migrateV2(map);
    } else if (version != 3 && version != 4 && version != schemaVersion) {
      throw const LedgerException(
        'This backup version is not supported. Your current data is unchanged.',
      );
    }
    final rawWallets = map['wallets'];
    if (rawWallets is! List || rawWallets.isEmpty || rawWallets.length > 20) {
      throw const LedgerException('Keep one to twenty wallets.');
    }
    final wallets = rawWallets.map(Wallet.fromJson).toList();
    final walletIds = wallets.map((w) => w.id).toSet();
    if (wallets.map((w) => w.label.toLowerCase()).toSet().length !=
        wallets.length) {
      throw const LedgerException('Wallet names must be distinct.');
    }
    if (walletIds.length != wallets.length) {
      throw const LedgerException(
        'Wallet identifiers or active wallets are invalid.',
      );
    }
    final allowance = map['allowance'] == null
        ? null
        : AllowanceSchedule.fromJson(map['allowance']);
    if (allowance != null &&
        (!walletIds.contains(allowance.wallet.id) ||
            allowance.enabled &&
                wallets.where((w) => w == allowance.wallet).single.archived)) {
      throw const LedgerException(
        'The allowance wallet is missing or archived.',
      );
    }
    final rawCategories = map['categories'],
        rawEntries = map['entries'],
        rawChanges = map['changes'];
    if (rawCategories is! List ||
        rawCategories.isEmpty ||
        rawCategories.length > 100 ||
        rawEntries is! List ||
        rawEntries.length > 20000 ||
        rawChanges is! List ||
        rawChanges.length > 30) {
      throw const LedgerException(
        'The backup has invalid or excessive records.',
      );
    }
    final rawBills = map['bills'] ?? <dynamic>[];
    if (rawBills is! List || rawBills.length > 100) {
      throw const LedgerException('Keep up to 100 bills.');
    }
    final bills = rawBills.map(Bill.fromJson).toList();
    if (bills.map((b) => b.id).toSet().length != bills.length) {
      throw const LedgerException('The backup contains duplicate bills.');
    }
    final categories = rawCategories.map(Category.fromJson).toList();
    final entries = rawEntries.map(Entry.fromJson).toList();
    final changes = rawChanges.map(Change.fromJson).toList();
    if (categories.map((c) => c.id).toSet().length != categories.length ||
        entries.map((e) => e.id).toSet().length != entries.length) {
      throw const LedgerException('The backup contains duplicate identifiers.');
    }
    if (!categories.any((c) => !c.archived)) {
      throw const LedgerException('Keep at least one available category.');
    }
    final categoryIds = categories.map((c) => c.id).toSet();
    for (final e in [
      ...entries,
      ...changes.expand((c) => [if (c.before != null) c.before!, c.after]),
    ]) {
      if (!walletIds.contains(e.wallet.id) ||
          e.toWallet != null && !walletIds.contains(e.toWallet!.id)) {
        throw const LedgerException(
          'A transaction references a missing wallet.',
        );
      }
      if (e.billId != null) {
        final origin = bills.where((b) => b.id == e.billId).firstOrNull;
        if (origin == null || !origin.containsDue(e.billDueDate!)) {
          throw const LedgerException(
            'A bill payment origin is missing or invalid.',
          );
        }
      }
      if (e.scheduleId != null && e.scheduleId != allowance?.id) {
        throw const LedgerException('An allowance origin is missing.');
      }
      if (e.categoryId != null && !categoryIds.contains(e.categoryId)) {
        throw const LedgerException(
          'A transaction references a missing category.',
        );
      }
    }
    if (changes.any((c) => !entries.any((e) => e.id == c.after.id))) {
      throw const LedgerException('A change references a missing transaction.');
    }
    final openingMap = object(map['openings']);
    if (openingMap.keys.toSet().difference(walletIds).isNotEmpty) {
      throw const LedgerException(
        'The backup contains an unknown opening wallet.',
      );
    }
    final openings = {
      for (final w in wallets)
        w: intField(openingMap, w.name, min: -maxCentavos),
    };
    final budgetMap = object(map['budgets']);
    if (budgetMap.length > 3600) {
      throw const LedgerException('The backup has too many budgets.');
    }
    final budgets = <String, int>{};
    for (final key in budgetMap.keys) {
      if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(key)) {
        throw const LedgerException('A budget month is invalid.');
      }
      localDay('$key-01');
      budgets[key] = intField(budgetMap, key);
    }
    final preferences = Preferences.fromJson(map['preferences']);
    if (preferences.widgetCategories.any((id) => !categoryIds.contains(id))) {
      throw const LedgerException('A widget category is missing.');
    }
    if (preferences.quickWallets.any(
      (id) => !wallets.any((w) => w.id == id && !w.archived),
    )) {
      throw const LedgerException('A preferred wallet is missing or archived.');
    }
    return Ledger(
      wallets: wallets,
      allowance: allowance,
      bills: bills,
      categories: categories,
      entries: entries,
      openings: openings,
      budgets: budgets,
      preferences: preferences,
      changes: changes,
    );
  }
}

Map<String, dynamic> migrateV1(Map<String, dynamic> old) {
  final migrated = Map<String, dynamic>.from(old);
  migrated['schemaVersion'] = 2;
  migrated['changes'] = <dynamic>[];
  migrated['preferences'] =
      migrated['preferences'] ?? const Preferences().toJson();
  if (old['entries'] is List) {
    migrated['entries'] = (old['entries'] as List).map((value) {
      final entry = Map<String, dynamic>.from(object(value));
      entry.putIfAbsent('deletedAt', () => null);
      entry['updatedAt'] = entry['updatedAt'] ?? entry['createdAt'];
      return entry;
    }).toList();
  }
  if (old['categories'] is List) {
    migrated['categories'] = (old['categories'] as List).map((value) {
      final category = Map<String, dynamic>.from(object(value));
      category['archived'] = category['archived'] ?? false;
      return category;
    }).toList();
  }
  return migrated;
}

Map<String, dynamic> migrateV2(Map<String, dynamic> old) => {
  ...old,
  'schemaVersion': 3,
  'wallets': Wallet.values.map((w) => w.toJson()).toList(),
  'allowance': null,
};

class RestorePreview {
  const RestorePreview({
    required this.ledger,
    required this.added,
    required this.skipped,
    required this.base,
  });
  final Ledger ledger;
  final int added, skipped;
  final String base;
}

RestorePreview previewRestore(Ledger current, Ledger imported) {
  final currentCategories = jsonEncode(
    current.categories.map((c) => c.toJson()).toList(),
  );
  final defaultCategorySets = [
    jsonEncode(defaultCategories.map((c) => c.toJson()).toList()),
    jsonEncode(
      defaultCategories
          .where((c) => c.id != schoolSuppliesCategory.id)
          .map((c) => c.toJson())
          .toList(),
    ),
  ];
  final pristine =
      current.entries.isEmpty &&
      current.allowance == null &&
      current.bills.isEmpty &&
      jsonEncode(current.wallets.map((w) => w.toJson()).toList()) ==
          jsonEncode(Wallet.values.map((w) => w.toJson()).toList()) &&
      current.budgets.isEmpty &&
      current.openings.values.every((v) => v == 0) &&
      defaultCategorySets.contains(currentCategories);
  if (pristine) {
    return RestorePreview(
      ledger: imported.copy(
        preferences: imported.preferences.copy(
          welcomed: current.preferences.welcomed,
          balanceWidgetVisible: current.preferences.balanceWidgetVisible,
        ),
        allowance: imported.allowance?.copy(enabled: false),
        bills: imported.bills.map((b) => b.copy(remind: false)).toList(),
        changes: imported.changes,
      ),
      added: imported.entries.length,
      skipped: 0,
      base: current.encode(),
    );
  }
  final categories = [...current.categories];
  for (final c in imported.categories) {
    final existing = current.category(c.id);
    if (existing == null) {
      categories.add(c);
    } else if (jsonEncode(existing.toJson()) != jsonEncode(c.toJson())) {
      throw const LedgerException(
        'A category changed since this backup. Use a fresh backup; nothing has been restored.',
      );
    }
  }
  final entries = [...current.entries];
  var skipped = 0, added = 0;
  for (final e in imported.entries) {
    final existing = current.entry(e.id);
    if (existing == null) {
      entries.add(e);
      added++;
    } else if (sameEntry(existing, e)) {
      skipped++;
    } else {
      throw const LedgerException(
        'An entry changed since this backup. It will not be duplicated or overwritten. Use a fresh backup.',
      );
    }
  }
  final wallets = [...current.wallets];
  final openings = {...current.openings};
  for (final w in imported.wallets) {
    final old = current.wallet(w);
    if (old == null) {
      wallets.add(w);
      openings[w] = imported.openings[w]!;
    } else if (jsonEncode(old.toJson()) != jsonEncode(w.toJson()) ||
        current.openings[w] != imported.openings[w]) {
      throw const LedgerException(
        'A wallet or opening balance differs. Nothing has been restored.',
      );
    }
  }
  var allowance = current.allowance;
  if (imported.allowance != null) {
    if (allowance == null) {
      allowance = imported.allowance!.copy(enabled: false);
    } else if (jsonEncode(allowance.toJson()) !=
        jsonEncode(imported.allowance!.toJson())) {
      throw const LedgerException(
        'Allowance schedules differ. Nothing has been restored.',
      );
    }
  }
  final bills = [...current.bills];
  for (final bill in imported.bills) {
    final existing = current.bill(bill.id);
    if (existing == null) {
      bills.add(bill.copy(remind: false));
    } else if (jsonEncode(existing.copy(remind: false).toJson()) !=
        jsonEncode(bill.copy(remind: false).toJson())) {
      throw const LedgerException(
        'Bill schedules differ. Nothing has been restored.',
      );
    }
  }
  final budgets = {...current.budgets};
  for (final item in imported.budgets.entries) {
    if (budgets.containsKey(item.key) && budgets[item.key] != item.value) {
      throw const LedgerException(
        'A budget differs from this backup. Nothing has been restored.',
      );
    }
    budgets[item.key] = item.value;
  }
  final merged = current.copy(
    categories: categories,
    entries: entries,
    budgets: budgets,
    wallets: wallets,
    openings: openings,
    allowance: allowance,
    bills: bills,
  );
  Ledger.decode(merged.encode());
  return RestorePreview(
    ledger: merged,
    added: added,
    skipped: skipped,
    base: current.encode(),
  );
}

class Draft {
  Draft({
    String? id,
    this.amount = '',
    this.kind = EntryKind.expense,
    String? date,
    this.categoryId,
    this.note = '',
    this.from = Wallet.cash,
    this.to = Wallet.gcash,
    this.editingId,
  }) : id = id ?? newId(),
       date = date ?? dayKey(DateTime.now());
  final String id;
  String amount;
  EntryKind kind;
  String date;
  String? categoryId;
  String note;
  Wallet from, to;
  String? editingId;
  bool get dirty => amount.isNotEmpty || note.isNotEmpty || editingId != null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'kind': kind.name,
    'date': date,
    'categoryId': categoryId,
    'note': note,
    'from': from.name,
    'to': to.name,
    'editingId': editingId,
  };
  factory Draft.fromEntry(Entry e) => Draft(
    id: e.id,
    amount: moneyInput(e.centavos),
    kind: e.kind,
    date: e.date,
    categoryId: e.categoryId,
    note: e.note,
    from: e.wallet,
    to: e.toWallet ?? Wallet.gcash,
    editingId: e.id,
  );
  factory Draft.fromJson(dynamic value) {
    final map = object(value);
    final date = stringField(map, 'date', max: 10);
    localDay(date);
    final amount = stringField(map, 'amount', max: 12);
    if (amount.isNotEmpty &&
        !RegExp(r'^\d{0,9}(?:\.\d{0,2})?$').hasMatch(amount)) {
      throw const LedgerException('The saved amount is invalid.');
    }
    final kind = EntryKind.values
        .where((k) => k.name == map['kind'])
        .firstOrNull;
    if (kind == null) {
      throw const LedgerException('The saved entry type is invalid.');
    }
    return Draft(
      id: idField(map, 'id'),
      amount: amount,
      kind: kind,
      date: date,
      categoryId: map['categoryId'] == null ? null : idField(map, 'categoryId'),
      note: stringField(map, 'note'),
      from: walletField(map['from']),
      to: walletField(map['to'] ?? (map['from'] == 'cash' ? 'gcash' : 'cash')),
      editingId: map['editingId'] == null ? null : idField(map, 'editingId'),
    );
  }
}
