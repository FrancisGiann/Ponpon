import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/adventure.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/entry_page.dart';
import 'package:pocket_entry/ui/pixel_adventure.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'bills_balance_test.dart' as bill_data;
import 'ui_test.dart' show configure, fixture, loadFonts, synthetic;

void main() {
  setUpAll(loadFonts);

  test('Adventure style round trips without overriding the chosen theme', () {
    for (final theme in ['system', 'light', 'dark']) {
      final saved = Preferences(
        theme: theme,
        visualStyle: VisualStyle.adventure,
      );
      final loaded = Preferences.fromJson(saved.toJson());
      expect(loaded.visualStyle, VisualStyle.adventure);
      expect(loaded.effectiveTheme, theme);
    }
  });

  testWidgets('Adventure home and badge collection fit narrow large type', (
    tester,
  ) async {
    configure(tester, const Size(320, 640), scale: 1.6);
    final base = synthetic(populated: false).copy(
      preferences: synthetic(populated: false).preferences
          .copy(visualStyle: VisualStyle.adventure),
    );
    final app = fixture(base);
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.byType(PixelAdventureHero), findsOneWidget);
    expect(find.byKey(const ValueKey('adventure-balance')), findsOneWidget);
    expect(find.byKey(const ValueKey('adventure-add-entry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('adventure-badge-shortcut')));
    await tester.pumpAndSettle();
    expect(find.text('Badge collection'), findsOneWidget);
    expect(find.text('First steps'), findsOneWidget);
    expect(find.text('Locked'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pixel Adventure keeps balance and Add visible above the map', (
    tester,
  ) async {
    configure(tester, const Size(320, 640), scale: 1.6);
    final base = synthetic(populated: false);
    final app = fixture(
      base.copy(
        preferences: base.preferences.copy(visualStyle: VisualStyle.adventure),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();

    final balance = tester.getRect(
      find.byKey(const ValueKey('adventure-balance')),
    );
    final add = tester.getRect(
      find.byKey(const ValueKey('adventure-add-entry')),
    );
    final hero = tester.getRect(
      find.byKey(const ValueKey('adventure-overworld')),
    );
    final plan = tester.getRect(
      find.byKey(const ValueKey('adventure-destination-plan')),
    );
    final loans = tester.getRect(
      find.byKey(const ValueKey('adventure-destination-loans')),
    );
    final nav = tester.getRect(find.byKey(const ValueKey('home-tab-bar')));
    expect(balance.top, lessThan(add.top));
    expect(hero.top, lessThan(balance.top));
    expect(add.bottom, lessThan(hero.bottom));
    expect(hero.bottom, lessThan(plan.top));
    expect(plan.bottom, lessThan(loans.top));
    expect(plan.top, lessThan(nav.top));
    expect(loans.top, greaterThan(plan.top));
    expect(add.width, greaterThanOrEqualTo(250));
    expect(find.bySemanticsLabel('Add an entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget privacy preference does not hide in-app balance', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final base = synthetic();
    final app = fixture(
      base.copy(
        preferences: base.preferences.copy(
          visualStyle: VisualStyle.adventure,
          balanceWidgetVisible: false,
        ),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();

    final balance = tester.widget<Text>(
      find.byKey(const ValueKey('adventure-balance')),
    );
    expect(app.ledger.preferences.balanceWidgetVisible, isFalse);
    expect(balance.data, money(app.ledger.activeWalletBalance));
  });

  testWidgets('Adventure menu and persistent tabs open their destinations', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final base = synthetic(populated: false);
    final app = fixture(
      base.copy(
        preferences: base.preferences.copy(visualStyle: VisualStyle.adventure),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: HomeShell(app: app),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('History tab'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('History tab, selected'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Today tab'));
    await tester.pumpAndSettle();

    for (final (destination, navLabel) in [
      ('Open monthly plan and bill progress', 'Plan tab, selected'),
      ('Open loan repayment tracker', 'Loans tab, selected'),
    ]) {
      final route = find.bySemanticsLabel(destination);
      await tester.ensureVisible(route);
      await tester.tap(route);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(navLabel), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Today tab'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Today tab, selected'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pixel Adventure has distinct journal, plan, roster and entry', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final base = synthetic(populated: false);
    final app = fixture(
      base.copy(
        preferences: base.preferences.copy(
          visualStyle: VisualStyle.adventure,
          reduceMotion: true,
        ),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: HomeShell(app: app, initialTab: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adventure-journal')), findsOneWidget);
    expect(find.text('JOURNAL'), findsOneWidget);
    expect(find.text('Find a note, wallet or amount'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Plan tab'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('adventure-plan-dashboard')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('plan-spending-card')), findsOneWidget);
    expect(find.text('FIXED-TERM BILLS'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('adventure-plan-breakdown-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No expenses yet'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Loans tab'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adventure-loan-roster')), findsOneWidget);
    expect(find.byKey(const ValueKey('loan-projection-hud')), findsOneWidget);
    expect(find.text('No borrowers yet'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Today tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adventure-add-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(EntryPage), findsOneWidget);
    expect(find.text('QUICK CATEGORIES · INVENTORY'), findsOneWidget);
    expect(find.byKey(const ValueKey('key-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-kind-expense')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Adventure tab motion is short and dormant pages keep state', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final base = synthetic(populated: false, reduced: false);
    final app = fixture(
      base.copy(
        preferences: base.preferences.copy(
          visualStyle: VisualStyle.adventure,
          reduceMotion: false,
        ),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: HomeShell(app: app, initialTab: 2),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('adventure-plan-breakdown-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No expenses yet'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('History tab'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey('adventure-journal')), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Plan tab'));
    await tester.pumpAndSettle();
    expect(find.text('No expenses yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Adventure entry uses forest HUD, tactile keys and confirmation',
    (tester) async {
      configure(tester, const Size(320, 640), scale: 1.6);
      final base = synthetic(theme: 'dark', populated: false, reduced: false);
      final app = fixture(
        base.copy(
          preferences: base.preferences.copy(
            visualStyle: VisualStyle.adventure,
            reduceMotion: false,
            haptics: false,
          ),
        ),
      );
      addTearDown(app.dispose);
      app.startDraft(categoryId: 'food');
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: EntryPage(controller: app),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in [
        'adventure-entry-kind-panel',
        'adventure-entry-amount-hud',
        'adventure-entry-category-panel',
        'adventure-entry-keypad-panel',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.text('QUICK CATEGORIES · INVENTORY'), findsOneWidget);
      expect(find.text('SAVE TO WALLET'), findsOneWidget);
      expect(find.bySemanticsLabel('Add a note'), findsOneWidget);
      expect(
        tester
            .widget<CupertinoPageScaffold>(find.byType(CupertinoPageScaffold))
            .backgroundColor,
        const Color(0xFF10251F),
      );
      expect(
        tester
            .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher).first)
            .duration,
        const Duration(milliseconds: 150),
      );
      final digit = find.byKey(const ValueKey('key-1'));
      await tester.ensureVisible(digit);
      await tester.tap(digit);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Amount in Philippine pesos, 1'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Adventure style picker shows an illustrated current-style card',
    (tester) async {
      configure(tester, const Size(320, 640));
      final app = fixture(synthetic(populated: false));
      addTearDown(app.dispose);
      await tester.pumpWidget(
        PocketApp(
          controller: app,
          testHome: VisualStylePage(app: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('PonPon Adventure'),
        280,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('style-adventure'));
      expect(card, findsOneWidget);
      expect(find.text('TODAY · PONPON VILLAGE'), findsOneWidget);
      expect(find.text('WALLET BALANCE'), findsOneWidget);
      expect(find.text('PREVIEW'), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(app.ledger.preferences.visualStyle, VisualStyle.adventure);
      expect(find.text('CURRENT'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('CURRENT')).style!.color,
        const Color(0xFF18352D),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Badge state derives from active ledger records and undoable history',
    () {
      final ordinary = Entry(
        id: 'existing_entry',
        kind: EntryKind.expense,
        centavos: 1200,
        date: '2026-10-12',
        wallet: Wallet.cash,
        categoryId: 'food',
        createdAt: 1,
        updatedAt: 1,
      );
      final base = Ledger.empty().put(ordinary);
      expect(AdventureBadges.has(base, AdventureBadge.firstEntry), isTrue);
      expect(
        AdventureBadges.has(
          base.delete(ordinary.id, 2),
          AdventureBadge.firstEntry,
        ),
        isFalse,
      );

      final plan = bill_data.bill.copy(paymentCount: 1);
      final paidBill = base
          .copy(bills: [plan])
          .put(
            Entry(
              id: plan.paymentId(plan.startDate),
              kind: EntryKind.expense,
              centavos: plan.centavos,
              date: plan.startDate,
              wallet: Wallet.cash,
              categoryId: 'bills',
              note: plan.name,
              createdAt: 2,
              updatedAt: 2,
              billId: plan.id,
              billDueDate: plan.startDate,
            ),
          );
      expect(
        AdventureBadges.has(paidBill, AdventureBadge.finishedBill),
        isTrue,
      );

      const loan = Loan(
        id: 'badge_loan',
        borrower: 'Ari',
        principalCentavos: 1000,
        date: '2026-10-12',
        funded: false,
        alreadyRepaidCentavos: 0,
        createdAt: 1,
        updatedAt: 1,
      );
      final paidLoan = base
          .saveLoan(loan)
          .putLoanRepayment(
            loan,
            Entry(
              id: 'badge_payment',
              kind: EntryKind.income,
              centavos: 1000,
              date: '2026-10-12',
              wallet: Wallet.cash,
              createdAt: 2,
              updatedAt: 2,
              loanId: loan.id,
              loanAction: LoanAction.repayment,
            ),
          );
      expect(
        AdventureBadges.has(paidLoan, AdventureBadge.finalLoanRepayment),
        isTrue,
      );
    },
  );

  test(
    'Failed saves do not unlock badges; success unlocks once and undo clears',
    () async {
      final base = synthetic(populated: false).copy(
        preferences: synthetic(populated: false).preferences
            .copy(visualStyle: VisualStyle.adventure),
      );
      final app = fixture(base);
      addTearDown(app.dispose);
      final store = app.store as MemoryLedgerStore;
      app.startDraft(categoryId: 'food');
      app.draft!.amount = '12.00';
      store.failWrites = true;
      expect(await app.saveDraft(Wallet.cash), isFalse);
      expect(app.adventureReward, isNull);
      expect(
        AdventureBadges.has(app.ledger, AdventureBadge.firstEntry),
        isFalse,
      );
      store.failWrites = false;
      expect(await app.saveDraft(Wallet.cash), isTrue);
      expect(app.adventureReward?.kind, AdventureRewardKind.saved);
      expect(app.adventureReward?.badge, AdventureBadge.firstEntry);
      expect(
        AdventureBadges.has(app.ledger, AdventureBadge.firstEntry),
        isTrue,
      );
      expect(await app.undo(), isTrue);
      expect(app.adventureReward, isNull);
      expect(
        AdventureBadges.has(app.ledger, AdventureBadge.firstEntry),
        isFalse,
      );
    },
  );

  test(
    'Restored history qualifies silently without replaying a reward',
    () async {
      final current = synthetic(populated: false).copy(
        preferences: synthetic(populated: false).preferences
            .copy(visualStyle: VisualStyle.adventure),
      );
      const previouslyCompletedLoan = Loan(
        id: 'restored_full_loan',
        borrower: 'Mika',
        principalCentavos: 4000,
        date: '2026-10-02',
        funded: false,
        alreadyRepaidCentavos: 4000,
        createdAt: 1,
        updatedAt: 1,
      );
      final imported = synthetic().copy(
        loans: const [previouslyCompletedLoan],
        preferences: synthetic().preferences.copy(
          visualStyle: VisualStyle.adventure,
        ),
      );
      final app = fixture(current);
      addTearDown(app.dispose);
      expect(await app.restore(previewRestore(current, imported)), isTrue);
      expect(
        AdventureBadges.has(app.ledger, AdventureBadge.firstEntry),
        isTrue,
      );
      expect(
        AdventureBadges.has(app.ledger, AdventureBadge.finalLoanRepayment),
        isTrue,
      );
      expect(app.adventureReward, isNull);
    },
  );

  testWidgets('Milestone reward punches in with seeded sparkles', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final base = synthetic(populated: false, reduced: false).copy(
      preferences: synthetic(populated: false, reduced: false).preferences.copy(
        visualStyle: VisualStyle.adventure,
        reduceMotion: false,
        haptics: false,
      ),
    );
    final app = fixture(base);
    addTearDown(app.dispose);
    await tester.pumpWidget(PocketApp(controller: app));
    await tester.pumpAndSettle();
    app.startDraft(categoryId: 'food');
    app.draft!.amount = '8.00';
    expect(await app.saveDraft(Wallet.cash), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(const ValueKey('adventure-reward-art')), findsOneWidget);
    expect(find.byKey(const ValueKey('adventure-sparkles')), findsOneWidget);
    final early = tester.widget<Transform>(
      find.byKey(const ValueKey('adventure-reward-art')),
    );
    final earlyScale = early.transform.getMaxScaleOnAxis();
    await tester.pump(const Duration(milliseconds: 340));
    final punch = tester.widget<Transform>(
      find.byKey(const ValueKey('adventure-reward-art')),
    );
    final punchScale = punch.transform.getMaxScaleOnAxis();
    expect(earlyScale, inInclusiveRange(.3, 1.25));
    expect(punchScale, greaterThan(earlyScale));
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Entry saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Only a final fixed-term payment raises the bill reward', () async {
    final plan = bill_data.bill.copy(paymentCount: 1);
    final ledger = bill_data.fixture().copy(
      bills: [plan],
      preferences: bill_data.fixture().preferences.copy(
        visualStyle: VisualStyle.adventure,
        haptics: false,
      ),
    );
    final app = bill_data.controller(ledger);
    expect(
      await app.recordBillPayment(
        plan,
        plan.startDate,
        Wallet.cash,
        ledger.category('bills')!,
        confirmed: true,
      ),
      isTrue,
    );
    expect(app.adventureReward?.kind, AdventureRewardKind.billCompleted);
    expect(app.adventureReward?.badge, AdventureBadge.finishedBill);
    expect(await app.undo(), isTrue);
    expect(app.adventureReward, isNull);
    expect(
      AdventureBadges.has(app.ledger, AdventureBadge.finishedBill),
      isFalse,
    );
  });

  test('Only a stored final repayment raises the loan reward', () async {
    final ledger = synthetic(populated: false).copy(
      preferences: synthetic(populated: false).preferences
          .copy(visualStyle: VisualStyle.adventure, haptics: false),
    );
    final app = fixture(ledger);
    addTearDown(app.dispose);
    expect(
      await app.addLoan(
        borrower: 'Ari',
        principalCentavos: 10000,
        date: '2026-11-01',
        alreadyExisting: true,
      ),
      isTrue,
    );
    final loan = app.ledger.activeLoans.single;
    expect(app.adventureReward, isNull);
    expect(
      await app.recordLoanRepayment(
        reviewed: loan,
        centavos: 10000,
        date: '2026-11-02',
        wallet: Wallet.cash,
      ),
      isTrue,
    );
    expect(app.adventureReward?.kind, AdventureRewardKind.loanCompleted);
    expect(app.adventureReward?.badge, AdventureBadge.finalLoanRepayment);
    expect(await app.undo(), isTrue);
    expect(app.adventureReward, isNull);
    expect(
      AdventureBadges.has(app.ledger, AdventureBadge.finalLoanRepayment),
      isFalse,
    );
  });
}
