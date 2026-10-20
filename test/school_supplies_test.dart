import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/entry_page.dart';

import 'ui_test.dart' show configure, fixture, loadFonts, synthetic;

void main() {
  setUpAll(loadFonts);

  test('School supplies is an expense choice for old ledgers without mutating them', () {
    final old = synthetic().copy(
      categories: defaultCategories
          .where((category) => category.id != schoolSuppliesCategory.id)
          .toList(),
    );
    final encoded = old.encode();
    final decoded = Ledger.decode(encoded);

    expect(decoded.categoriesFor(EntryKind.expense).last.id, 'other');
    expect(
      decoded.categoriesFor(EntryKind.expense).reversed.skip(1).first.toJson(),
      schoolSuppliesCategory.toJson(),
    );
    expect(decoded.categoriesFor(EntryKind.income).map((c) => c.id), [
      'income',
      'income_allowance',
      'income_salary',
      'income_gift',
      'income_other',
    ]);
    expect(decoded.encode(), encoded);

    final app = fixture(decoded);
    addTearDown(app.dispose);
    app.startDraft(categoryId: 'school_supplies');
    expect(app.draft!.kind, EntryKind.expense);
    expect(app.draft!.categoryId, 'school_supplies');
    app.changeDraftKind(EntryKind.income);
    expect(app.draft!.categoryId, 'income');
    app.changeDraftKind(EntryKind.expense);
    expect(app.draft!.categoryId, isNull);
    expect(app.ledger.encode(), encoded);
  });

  test(
    'Saving materializes School supplies and preserves Other history exactly',
    () async {
      final old = synthetic().copy(
        categories: defaultCategories
            .where((category) => category.id != schoolSuppliesCategory.id)
            .toList(),
      );
      final other = Entry(
        id: 'existing_other',
        kind: EntryKind.expense,
        centavos: 2345,
        date: '2026-10-11',
        wallet: Wallet.cash,
        categoryId: 'other',
        note: 'unchanged other entry',
        createdAt: 12,
        updatedAt: 12,
      );
      final original = old.put(other);
      final before = original.entry(other.id)!.toJson();
      final app = fixture(original);
      addTearDown(app.dispose);

      app.startDraft(categoryId: 'school_supplies');
      app.draft!.amount = '12.34';
      expect(await app.saveDraft(Wallet.gcash), isTrue);
      final saved = app.ledger.active.first;
      expect(saved.kind, EntryKind.expense);
      expect(saved.centavos, 1234);
      expect(saved.wallet, Wallet.gcash);
      expect(saved.categoryId, 'school_supplies');
      expect(
        app.ledger.total(EntryKind.expense, categoryId: 'school_supplies'),
        1234,
      );
      expect(app.ledger.entry(other.id)!.toJson(), before);
      expect(
        Ledger.decode(app.ledger.encode()).entry(saved.id)!.toJson(),
        saved.toJson(),
      );
      expect(await app.undo(), isTrue);
      expect(
        app.ledger.total(EntryKind.expense, categoryId: 'school_supplies'),
        0,
      );
      expect(app.ledger.entry(other.id)!.toJson(), before);
    },
  );

  test(
    'Renamed School definition is respected and archived one is not offered',
    () {
      final renamed = synthetic(populated: false).copy(
        categories: [
          for (final c in defaultCategories)
            if (c.id == 'school_supplies') c.copy(name: 'Books') else c,
        ],
      );
      expect(
        renamed
            .categoriesFor(EntryKind.expense)
            .singleWhere((c) => c.id == 'school_supplies')
            .name,
        'Books',
      );
      final legacyCustom = renamed.copy(
        categories: [
          for (final c in renamed.categories)
            if (c.id == 'school_supplies')
              const Category(
                id: 'school_supplies',
                name: 'School supplies',
                icon: 'income',
              )
            else
              c,
        ],
      );
      final legacyBytes = legacyCustom.encode();
      expect(
        legacyCustom
            .categoriesFor(EntryKind.expense)
            .any((c) => c.id == 'school_supplies'),
        isFalse,
      );
      expect(
        legacyCustom
            .categoriesFor(EntryKind.income)
            .any((c) => c.id == 'school_supplies'),
        isTrue,
      );
      final legacyApp = fixture(legacyCustom);
      addTearDown(legacyApp.dispose);
      legacyApp.startDraft(categoryId: 'school_supplies');
      expect(legacyApp.draft!.kind, EntryKind.income);
      expect(legacyApp.ledger.encode(), legacyBytes);
      final archived = renamed.copy(
        categories: [
          for (final c in renamed.categories)
            if (c.id == 'school_supplies') c.copy(archived: true) else c,
        ],
      );
      expect(
        archived
            .categoriesFor(EntryKind.expense)
            .any((c) => c.id == 'school_supplies'),
        isFalse,
      );
    },
  );

  test(
    'Widget pinning on an older ledger materializes the category atomically',
    () async {
      final old = synthetic(populated: false).copy(
        categories: defaultCategories
            .where((category) => category.id != schoolSuppliesCategory.id)
            .toList(),
        preferences: synthetic(populated: false).preferences
            .copy(widgetCategories: ['income_gift', 'food']),
      );
      final app = fixture(old);
      addTearDown(app.dispose);
      final value = old.preferences.copy(
        widgetCategories: ['income_gift', 'food', 'school_supplies'],
      );
      expect(await app.preferences(value), isTrue);
      expect(app.ledger.category('school_supplies')!.name, 'School supplies');
      expect(app.ledger.preferences.widgetCategories, [
        'income_gift',
        'food',
        'school_supplies',
      ]);
    },
  );

  test(
    'Category cap rejects School save and pin without changing ledger or draft',
    () async {
      final base = synthetic();
      final categories = <Category>[
        ...defaultCategories.where((c) => c.id != schoolSuppliesCategory.id),
      ];
      categories.addAll([
        for (var i = 0; categories.length + i < 100; i++)
          Category(id: 'cap_$i', name: 'Extra $i', icon: 'other'),
      ]);
      expect(categories.length, 100);
      final full = base.copy(categories: categories);
      final app = fixture(full);
      addTearDown(app.dispose);
      final before = full.encode();
      final beforeEntries = full.entries.map((e) => e.toJson()).toList();
      final beforeChanges = full.changes.map((c) => c.toJson()).toList();

      expect(
        await app.preferences(
          full.preferences.copy(widgetCategories: ['school_supplies']),
        ),
        isFalse,
      );
      expect(
        app.storageError,
        'Keep up to 100 categories. Use an existing category before adding another.',
      );
      expect(app.ledger.encode(), before);

      app.startDraft(categoryId: 'school_supplies');
      app.draft!.amount = '7.50';
      final draftId = app.draft!.id;
      expect(await app.saveDraft(Wallet.cash), isFalse);
      expect(app.storageError, contains('Use an existing category'));
      expect(app.ledger.encode(), before);
      expect(app.ledger.entries.map((e) => e.toJson()), beforeEntries);
      expect(app.ledger.changes.map((c) => c.toJson()), beforeChanges);
      expect(app.draft!.id, draftId);
      expect(app.draft!.categoryId, 'school_supplies');
    },
  );

  testWidgets('Full expense picker offers School supplies on an old ledger', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final old = synthetic(populated: false).copy(
      categories: defaultCategories
          .where((category) => category.id != schoolSuppliesCategory.id)
          .toList(),
    );
    final app = fixture(old);
    addTearDown(app.dispose);
    app.startDraft();
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: EntryPage(controller: app),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('All categories'));
    await tester.pumpAndSettle();
    expect(find.text('School supplies'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('School supplies')).dy,
      lessThan(tester.getTopLeft(find.text('Other')).dy),
    );
    await tester.tap(find.text('School supplies'));
    await tester.pumpAndSettle();
    expect(app.draft!.categoryId, 'school_supplies');
    await tester.tap(find.byKey(const ValueKey('key-1')));
    await tester.tap(find.byKey(const ValueKey('key-2')));
    await tester.tap(find.byKey(const ValueKey('save-gcash')));
    await tester.pumpAndSettle();
    expect(app.ledger.active.single.centavos, 1200);
    expect(app.ledger.active.single.wallet, Wallet.gcash);
    expect(app.ledger.active.single.categoryId, 'school_supplies');
    expect(
      app.ledger.total(EntryKind.expense, categoryId: 'school_supplies'),
      1200,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
