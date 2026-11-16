part of 'ledger.dart';

enum LoanAction { issued, repayment }

const maxLoans = 100;

class Loan {
  const Loan({
    required this.id,
    required this.borrower,
    required this.principalCentavos,
    required this.date,
    required this.funded,
    required this.alreadyRepaidCentavos,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
    this.note = '',
    this.deletedAt,
  });

  final String id, borrower, date, note;
  final int principalCentavos, alreadyRepaidCentavos, createdAt, updatedAt;
  final bool funded;
  final String? dueDate;
  final int? deletedAt;
  bool get deleted => deletedAt != null;

  Loan copy({
    String? borrower,
    int? principalCentavos,
    String? date,
    bool? funded,
    int? alreadyRepaidCentavos,
    int? updatedAt,
    Object? dueDate = _keepLoanDueDate,
    String? note,
    Object? deletedAt = _keepLoanDeletedAt,
  }) => Loan(
    id: id,
    borrower: borrower ?? this.borrower,
    principalCentavos: principalCentavos ?? this.principalCentavos,
    date: date ?? this.date,
    funded: funded ?? this.funded,
    alreadyRepaidCentavos: alreadyRepaidCentavos ?? this.alreadyRepaidCentavos,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dueDate: identical(dueDate, _keepLoanDueDate)
        ? this.dueDate
        : dueDate as String?,
    note: note ?? this.note,
    deletedAt: identical(deletedAt, _keepLoanDeletedAt)
        ? this.deletedAt
        : deletedAt as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'borrower': borrower,
    'principalCentavos': principalCentavos,
    'date': date,
    'dueDate': dueDate,
    'note': note,
    'funded': funded,
    'alreadyRepaidCentavos': alreadyRepaidCentavos,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  factory Loan.fromJson(dynamic value) {
    final map = object(value);
    final id = idField(map, 'id');
    final borrower = stringField(map, 'borrower', max: 60).trim();
    final date = stringField(map, 'date', max: 10);
    localDay(date);
    final dueDate = map['dueDate'] == null
        ? null
        : stringField(map, 'dueDate', max: 10);
    if (dueDate != null) localDay(dueDate);
    final principal = intField(map, 'principalCentavos', min: 1);
    final alreadyRepaid = intField(
      map,
      'alreadyRepaidCentavos',
      max: principal,
    );
    final funded = boolField(map, 'funded');
    final createdAt = intField(map, 'createdAt', max: 9000000000000000);
    final updatedAt = intField(map, 'updatedAt', max: 9000000000000000);
    if (id.length > 32 ||
        borrower.isEmpty ||
        updatedAt < createdAt ||
        funded && alreadyRepaid != 0) {
      throw const LedgerException('A loan has invalid details.');
    }
    return Loan(
      id: id,
      borrower: borrower,
      principalCentavos: principal,
      date: date,
      dueDate: dueDate,
      note: stringField(map, 'note', max: 500),
      funded: funded,
      alreadyRepaidCentavos: alreadyRepaid,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: map['deletedAt'] == null
          ? null
          : intField(map, 'deletedAt', max: 9000000000000000),
    );
  }

  List<Entry> activities(Ledger ledger) =>
      List.unmodifiable(ledger.active.where((entry) => entry.loanId == id));

  int paidCentavos(Ledger ledger) =>
      alreadyRepaidCentavos +
      activities(ledger)
          .where((entry) => entry.loanAction == LoanAction.repayment)
          .fold(0, (sum, entry) => sum + entry.centavos);

  int remainingCentavos(Ledger ledger) =>
      principalCentavos - paidCentavos(ledger);

  bool completed(Ledger ledger) => remainingCentavos(ledger) == 0;
}
