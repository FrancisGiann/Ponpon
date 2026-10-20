import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';

// Artificial 0.2.5 fixtures: its untouched defaults predate School supplies.
Ledger _legacyEmpty() => Ledger.empty().copy(
  categories: defaultCategories
      .where((c) => c.id != schoolSuppliesCategory.id)
      .toList(),
);

Ledger _legacyBackup() =>
    _legacyEmpty().copy(openings: {Wallet.cash: 10000, Wallet.gcash: 0});

void main() {
  test(
    'REGRESSION empty 0.2.5 ledger can restore a nonzero opening balance',
    () {
      final current = _legacyEmpty();
      final before = current.encode();
      final imported = _legacyBackup();

      final preview = previewRestore(current, imported);

      expect(preview.ledger.openings[Wallet.cash], 10000);
      expect(preview.ledger.calculate(Wallet.cash).balance, 10000);
      expect(preview.ledger.entries, isEmpty);
      expect(preview.ledger.allowance, isNull);
      expect(current.encode(), before);
    },
  );

  test(
    'legacy pristine restore preserves local welcome and widget visibility',
    () {
      final empty = _legacyEmpty();
      final current = empty.copy(
        preferences: empty.preferences.copy(
          welcomed: true,
          balanceWidgetVisible: true,
        ),
      );
      final imported = _legacyBackup().copy(
        preferences: const Preferences(
          welcomed: false,
          balanceWidgetVisible: false,
        ),
      );

      final preview = previewRestore(current, imported);

      expect(preview.ledger.openings[Wallet.cash], 10000);
      expect(preview.ledger.preferences.welcomed, isTrue);
      expect(preview.ledger.preferences.balanceWidgetVisible, isTrue);
    },
  );

  test('current pristine defaults still restore an older backup', () {
    final preview = previewRestore(Ledger.empty(), _legacyBackup());

    expect(preview.ledger.openings[Wallet.cash], 10000);
    expect(preview.ledger.calculate(Wallet.cash).balance, 10000);
  });

  for (final change in ['renamed', 'archived']) {
    test('a $change existing category remains conflict protected', () {
      final old = _legacyEmpty();
      final current = old.copy(
        categories: [
          for (final category in old.categories)
            if (category.id == 'food')
              change == 'renamed'
                  ? category.copy(name: 'Meals')
                  : category.copy(archived: true)
            else
              category,
        ],
      );
      final before = current.encode();

      expect(
        () => previewRestore(current, _legacyBackup()),
        throwsA(isA<LedgerException>()),
      );
      expect(current.encode(), before);
    });
  }

  test(
    'an extra custom category does not make an existing ledger pristine',
    () {
      final old = _legacyEmpty();
      final current = old.copy(
        categories: [
          ...old.categories,
          const Category(
            id: 'restore_compat_custom',
            name: 'Fixture custom category',
            icon: 'other',
          ),
        ],
      );
      final before = current.encode();

      expect(
        () => previewRestore(current, _legacyBackup()),
        throwsA(isA<LedgerException>()),
      );
      expect(current.encode(), before);
    },
  );

  test('a nonzero existing opening balance remains conflict protected', () {
    final current = _legacyEmpty().copy(
      openings: {Wallet.cash: 5000, Wallet.gcash: 0},
    );
    final before = current.encode();

    expect(
      () => previewRestore(current, _legacyBackup()),
      throwsA(isA<LedgerException>()),
    );
    expect(current.encode(), before);
    expect(current.calculate(Wallet.cash).balance, 5000);
  });
}
