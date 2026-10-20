import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show configure, fixture, loadFonts;

const _days = [1, 2, 3, 4, 5, 6, 7];

AllowanceSchedule _schedule({
  String through = '2026-10-01',
  List<int> days = _days,
  bool enabled = true,
}) => AllowanceSchedule(
  id: 'allowance_fix_edge',
  centavos: 10000,
  wallet: Wallet.cash,
  days: days,
  startDate: '2026-10-01',
  processedThrough: through,
  enabled: enabled,
);

Ledger _withSchedule(
  AllowanceSchedule schedule, {
  List<Category>? categories,
}) => Ledger.empty().copy(
  allowance: schedule,
  categories: categories ?? defaultCategories,
);

void main() {
  setUpAll(loadFonts);

  test(
    'Missing built-in allowance category is added only for a due receipt',
    () {
      final categories = defaultCategories
          .where((c) => c.id != 'income_allowance')
          .toList();
      final before = _withSchedule(_schedule(), categories: categories);
      final due = catchUpAllowance(before, DateTime(2026, 10, 2));
      expect(due.count, 1);
      expect(
        due.ledger.category('income_allowance')!.toJson(),
        defaultIncomeCategories[1].toJson(),
      );
      expect(due.ledger.active.single.categoryId, 'income_allowance');

      final noOccurrence = _withSchedule(
        _schedule(days: const [6]),
        categories: categories,
      );
      final noDue = catchUpAllowance(noOccurrence, DateTime(2026, 10, 2));
      expect(noDue.count, 0);
      expect(
        noDue.ledger.categories.map((c) => c.toJson()),
        noOccurrence.categories.map((c) => c.toJson()),
      );
      expect(noDue.ledger.entries, isEmpty);
    },
  );

  test(
    'Renamed built-in is kept; archived built-in falls back to active income',
    () {
      final renamed = _withSchedule(
        _schedule(),
        categories: [
          for (final c in defaultCategories)
            if (c.id == 'income_allowance')
              c.copy(name: 'Allowance stipend')
            else
              c,
        ],
      );
      final renamedResult = catchUpAllowance(renamed, DateTime(2026, 10, 2));
      expect(renamedResult.ledger.active.single.categoryId, 'income_allowance');
      expect(
        renamedResult.ledger.category('income_allowance')!.name,
        'Allowance stipend',
      );

      final archived = _withSchedule(
        _schedule(),
        categories: [
          for (final c in defaultCategories)
            if (c.id == 'income_allowance') c.copy(archived: true) else c,
        ],
      );
      final archivedResult = catchUpAllowance(archived, DateTime(2026, 10, 2));
      expect(archivedResult.ledger.active.single.categoryId, 'income');
      expect(
        archivedResult.ledger.category('income_allowance')!.archived,
        isTrue,
      );
    },
  );

  test('At category cap allowance uses active income; no-due check never hits cap error', () {
    final categories = <Category>[
      ...defaultCategories.where((c) => c.id != 'income_allowance'),
    ];
    categories.addAll([
      for (var i = 0; categories.length + i < 100; i++)
        Category(id: 'allow_cap_$i', name: 'Extra $i', icon: 'other'),
    ]);
    expect(categories.length, 100);

    final due = catchUpAllowance(
      _withSchedule(_schedule(), categories: categories),
      DateTime(2026, 10, 2),
    );
    expect(due.count, 1);
    expect(due.ledger.categories.length, 100);
    expect(due.ledger.active.single.categoryId, 'income');

    final noDue = catchUpAllowance(
      _withSchedule(_schedule(days: const [6]), categories: categories),
      DateTime(2026, 10, 2),
    );
    expect(noDue.count, 0);
    expect(noDue.ledger.categories.length, 100);
    expect(noDue.ledger.entries, isEmpty);
  });

  test(
    'Allowance cursor stays monotonic across rollback disable and re-enable',
    () async {
      final scanned = catchUpAllowance(
        _withSchedule(_schedule(days: const [1])),
        DateTime(2026, 10, 12),
      ).ledger;
      expect(scanned.active.map((e) => e.date), ['2026-10-12', '2026-10-05']);
      var now = DateTime(2026, 10, 12);
      final app = AppController(
        store: MemoryLedgerStore(scanned),
        clock: () => now,
      );
      addTearDown(app.dispose);
      await app.initialize();

      now = DateTime(2026, 10, 9);
      expect(
        await app.setAllowance(
          centavos: 10000,
          wallet: Wallet.cash,
          days: _days,
          startDate: '2026-10-09',
          enabled: false,
        ),
        isTrue,
      );
      expect(app.ledger.allowance!.processedThrough, '2026-10-12');
      now = DateTime(2026, 10, 10);
      expect(
        await app.setAllowance(
          centavos: 10000,
          wallet: Wallet.cash,
          days: _days,
          startDate: '2026-10-10',
          enabled: true,
        ),
        isTrue,
      );
      expect(app.ledger.allowance!.processedThrough, '2026-10-12');
      expect(app.ledger.entries.length, 2);
      expect(app.ledger.entry(_schedule().occurrenceId('2026-10-10')), isNull);
    },
  );

  testWidgets('History amount search accepts canonical 1000 and 1000.00', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(
      Ledger.empty().put(
        const Entry(
          id: 'history_amount_edge',
          kind: EntryKind.expense,
          centavos: 100000,
          date: '2026-10-12',
          wallet: Wallet.cash,
          categoryId: 'food',
          createdAt: 1,
          updatedAt: 1,
        ),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: HistoryPage(app: app),
      ),
    );
    await tester.pumpAndSettle();
    for (final query in ['1000', '1000.00']) {
      await tester.enterText(find.byType(CupertinoSearchTextField), query);
      await tester.pumpAndSettle();
      expect(find.byType(EntryRow), findsOneWidget, reason: query);
    }
  });
}
