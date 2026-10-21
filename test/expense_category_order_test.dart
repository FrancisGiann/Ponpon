import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/data/native_bridge.dart';
import 'package:pocket_entry/domain/ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Stored School and custom expenses display before Other without edits',
    () {
      const renamedOther = Category(
        id: 'other',
        name: 'Miscellaneous',
        icon: 'other',
      );
      const custom = Category(id: 'custom', name: 'Other', icon: 'home');
      final ledger = Ledger.empty().copy(
        categories: [
          renamedOther,
          defaultIncomeCategories[2],
          custom,
          defaultIncomeCategories[3],
          schoolSuppliesCategory,
        ],
        preferences: const Preferences(
          widgetCategories: ['other', 'school_supplies'],
        ),
      );
      final before = ledger.encode();
      expect(ledger.categoriesFor(EntryKind.expense).map((c) => c.id), [
        'custom',
        'school_supplies',
        'other',
      ]);
      expect(ledger.availableCategories.map((c) => c.id), [
        'income_salary',
        'custom',
        'income_gift',
        'school_supplies',
        'other',
      ]);
      expect(ledger.categoriesFor(EntryKind.income).map((c) => c.id), [
        'income',
        'income_allowance',
        'income_salary',
        'income_gift',
        'income_other',
      ]);
      expect(
        ledger.categoriesFor(EntryKind.expense).last.name,
        'Miscellaneous',
      );
      expect(ledger.encode(), before);
      expect(ledger.categories.first, renamedOther);
      expect(Ledger.decode(before).categories.first.id, 'other');
    },
  );

  test(
    'Other display rule preserves income identities and summary amounts',
    () {
      const income = Category(
        id: 'other',
        name: 'Custom income',
        icon: 'income',
      );
      expect(otherExpenseLast([income, schoolSuppliesCategory], (c) => c), [
        income,
        schoolSuppliesCategory,
      ]);
      final totals = [
        (defaultCategories.last, 3000),
        (schoolSuppliesCategory, 1234),
        (defaultCategories.first, 1000),
      ];
      expect(otherExpenseLast(totals, (row) => row.$1), [
        totals[1],
        totals[2],
        totals[0],
      ]);
      expect(totals.first.$2, 3000);
    },
  );

  test('Category icon choices cannot change income or expense type', () {
    expect(categoryIconsFor(defaultIncomeCategories.first), ['income']);
    expect(
      categoryIconsFor(defaultCategories.first),
      isNot(contains('income')),
    );
    const userIncome = Category(
      id: 'salary_custom',
      name: 'Salary',
      icon: 'income',
    );
    expect(categoryIconsFor(userIncome), ['income']);
  });

  test(
    'Native quick-entry payload puts Other last without changing pins',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeBridge.channel, null),
      );
      final ledger = Ledger.empty().copy(
        preferences: const Preferences(
          widgetCategories: ['other', 'income_gift', 'school_supplies', 'food'],
        ),
      );
      final before = ledger.encode();
      await const NativeBridge().sync(ledger);
      final payload = calls.single.arguments as Map<dynamic, dynamic>;
      final categories = payload['categories'] as List<dynamic>;
      expect(categories.map((c) => (c as Map<dynamic, dynamic>)['id']), [
        'income_gift',
        'school_supplies',
        'food',
        'other',
      ]);
      expect(calls.single.method, 'syncAppearance');
      expect(ledger.quickCategories.map((c) => c.id), [
        'income_gift',
        'school_supplies',
        'food',
        'other',
      ]);
      expect(ledger.encode(), before);
      expect(ledger.preferences.widgetCategories.first, 'other');
    },
  );

  test(
    'Quick selection filters archived IDs and leaves stored order alone',
    () {
      final ledger = Ledger.empty().copy(
        categories: [
          ...defaultCategories,
          const Category(id: 'old', name: 'Old', icon: 'home', archived: true),
        ],
        preferences: const Preferences(
          widgetCategories: ['other', 'old', 'income_gift', 'food'],
        ),
      );
      final before = ledger.encode();
      expect(ledger.quickCategories.map((c) => c.id), [
        'income_gift',
        'food',
        'other',
      ]);
      expect(ledger.preferences.widgetCategories, [
        'other',
        'old',
        'income_gift',
        'food',
      ]);
      final restored = Ledger.decode(before);
      expect(restored.quickCategories.map((c) => c.id), [
        'income_gift',
        'food',
        'other',
      ]);
      expect(restored.preferences.widgetCategories, [
        'other',
        'old',
        'income_gift',
        'food',
      ]);
      expect(ledger.encode(), before);
    },
  );
}
