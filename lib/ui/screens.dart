import 'package:flutter/cupertino.dart';

import '../app_controller.dart';
import '../data/native_bridge.dart';
import '../domain/ledger.dart';
import 'design.dart';
import 'entry_page.dart';

part 'wallet_screens.dart';
part 'allowance_page.dart';
part 'bills_balance.dart';
part 'style_page.dart';

Future<void> openEntry(
  BuildContext context,
  AppController app, {
  String? categoryId,
  Entry? editing,
}) async {
  if (app.busy) return;
  if (editing != null &&
      app.draft?.dirty == true &&
      app.draft?.editingId != editing.id) {
    final discard = await confirm(
      context,
      title: 'An entry is unfinished',
      message: 'Discard the unfinished entry to edit this one?',
      action: 'Discard entry',
      destructive: true,
    );
    if (!discard || !context.mounted) return;
    await app.discardDraft();
    if (!context.mounted) return;
  }
  if (app.draft == null || !app.draft!.dirty) {
    app.startDraft(categoryId: categoryId, editing: editing);
  }
  if (context.mounted) {
    await pushPocket<void>(context, EntryPage(controller: app), modal: true);
    app.publish();
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final p = Palette.of(context);
      final largeType = MediaQuery.textScalerOf(context).scale(1) > 1.25;
      return CupertinoPageScaffold(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.asset(
                                  'assets/branding/ponpon-icon.png',
                                  width: largeType ? 56 : 80,
                                  height: largeType ? 56 : 80,
                                  cacheWidth: 160,
                                  semanticLabel: 'Ponpon wallet app icon',
                                ),
                              ),
                              SizedBox(height: largeType ? 14 : 28),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Ponpon',
                                  textAlign: TextAlign.center,
                                  style: textStyle(
                                    context,
                                    size: 35,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Budget & Expenses',
                                textAlign: TextAlign.center,
                                style: textStyle(
                                  context,
                                  size: largeType ? 17 : 21,
                                  color: p.secondary,
                                ),
                              ),
                              SizedBox(height: largeType ? 20 : 34),
                              Surface(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    GroupRow(
                                      'Record it in a moment',
                                      subtitle: 'Enter an amount. Tap Paid with Cash or Paid with GCash to finish.',
                                      icon: CupertinoIcons.hand_draw,
                                    ),
                                    GroupRow(
                                      'Start from your home screen',
                                      subtitle: 'A category widget takes you straight to the keypad.',
                                      icon: CupertinoIcons.square_grid_2x2,
                                    ),
                                    GroupRow(
                                      'Private by design',
                                      subtitle: 'Offline records. No account or wallet login.',
                                      icon: CupertinoIcons.lock,
                                      last: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ErrorLine(app.storageError),
                    PrimaryButton(
                      'Get started',
                      onPressed: app.busy
                          ? null
                          : () => app.preferences(
                              app.ledger.preferences.copy(welcomed: true),
                            ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Philippine pesos · Manual wallet tracking',
                      textAlign: TextAlign.center,
                      style: textStyle(context, size: 12, color: p.secondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app, this.initialTab = 0});
  final AppController app;
  final int initialTab;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int tab = widget.initialTab;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final p = Palette.of(context);
      return CupertinoPageScaffold(
        backgroundColor: p.background,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: tab,
                      children: [
                        TodayPage(
                          app: widget.app,
                          onHistory: () => setState(() => tab = 1),
                        ),
                        HistoryPage(app: widget.app),
                        PlanPage(app: widget.app),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(p.navRadius),
                      border: p.border,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Press(
                              onPressed: () => setState(() => tab = i),
                              color: tab == i ? p.tint : null,
                              label:
                                  '${['Today', 'History', 'Plan'][i]} tab${tab == i ? ', selected' : ''}',
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              radius: p.controlCorner(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    [
                                      CupertinoIcons.house,
                                      CupertinoIcons.list_bullet,
                                      CupertinoIcons.chart_bar,
                                    ][i],
                                    color: tab == i ? p.accent : p.secondary,
                                    size: 23,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ['Today', 'History', 'Plan'][i],
                                    style: textStyle(
                                      context,
                                      size: 11,
                                      weight: tab == i
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: tab == i ? p.accent : p.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.app, required this.onHistory});
  final AppController app;
  final VoidCallback onHistory;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context), l = app.ledger, now = app.clock();
    final month = monthKey(now);
    final spent = l.total(EntryKind.expense, month: month);
    final budget = l.budgets[month] ?? 0;
    final recent = l.active.take(4).toList();
    final shortcuts = l.availableCategories
        .where((c) => c.id != 'income')
        .take(4)
        .toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PageHeading(
          'Today',
          subtitle: shortDate(dayKey(now)),
          trailing: Press(
            label: 'Settings',
            color: p.surface,
            padding: const EdgeInsets.all(12),
            radius: p.controlCorner(24),
            onPressed: () => pushPocket<void>(context, SettingsPage(app: app)),
            child: Icon(CupertinoIcons.gear_alt, color: p.ink, size: 22),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (app.notice != null) ...[
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.notice!,
                        style: textStyle(context, size: 14, color: p.secondary),
                      ),
                      Press(
                        onPressed: () {
                          app.notice = null;
                          app.publish();
                        },
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              HomeBalances(app: app),
              if (l.bills.isNotEmpty) ...[
                const SizedBox(height: 16),
                Surface(
                  padding: EdgeInsets.zero,
                  child: GroupRow(
                    'Upcoming bills',
                    subtitle: 'Review due dates and record payments',
                    icon: CupertinoIcons.calendar,
                    last: true,
                    onTap: () => pushPocket<void>(context, BillsPage(app: app)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                'Add an entry',
                icon: CupertinoIcons.plus,
                onPressed: () => openEntry(context, app),
              ),
              if (app.draft?.dirty == true)
                Press(
                  onPressed: () => openEntry(context, app),
                  child: Text(
                    'Resume unfinished entry',
                    style: textStyle(context, size: 13, color: p.accent),
                  ),
                ),
              if (shortcuts.isNotEmpty) ...[
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final large =
                        MediaQuery.textScalerOf(context).scale(1) > 1.25;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in shortcuts)
                          SizedBox(
                            width:
                                (constraints.maxWidth - (large ? 8 : 24)) /
                                (large ? 2 : 4),
                            child: Press(
                              key: ValueKey('quick-category-${c.id}'),
                              label: 'Add ${c.name} entry',
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 2,
                              ),
                              onPressed: () =>
                                  openEntry(context, app, categoryId: c.id),
                              child: Column(
                                children: [
                                  IconTile(
                                    categoryIcon(c.icon),
                                    color: categoryColor(context, c.icon),
                                    size: 44,
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle(
                                      context,
                                      size: 12,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent entries',
                      style: textStyle(
                        context,
                        size: 20,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Press(
                    onPressed: onHistory,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    child: Text(
                      'See all',
                      style: textStyle(context, size: 14, color: p.accent),
                    ),
                  ),
                ],
              ),
              if (recent.isEmpty)
                const QuietMessage(
                  'A fresh start',
                  'Tap a category or add your first entry. Opening balances and a budget can wait.',
                  icon: CupertinoIcons.square_pencil,
                )
              else
                Surface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Spent today',
                                style: textStyle(
                                  context,
                                  size: 13,
                                  color: p.secondary,
                                ),
                              ),
                            ),
                            Text(
                              money(
                                l.total(EntryKind.expense, date: dayKey(now)),
                              ),
                              style: textStyle(
                                context,
                                size: 15,
                                weight: FontWeight.w600,
                                tabular: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Rule(),
                      for (var i = 0; i < recent.length; i++) ...[
                        EntryRow(
                          entry: recent[i],
                          ledger: l,
                          onTap: () => pushPocket<void>(
                            context,
                            EntryDetailPage(app: app, id: recent[i].id),
                          ),
                        ),
                        if (i < recent.length - 1)
                          const Padding(
                            padding: EdgeInsets.only(left: 70),
                            child: Rule(),
                          ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      monthNames[now.month - 1],
                      style: textStyle(
                        context,
                        size: 20,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    money(spent),
                    style: textStyle(
                      context,
                      size: 17,
                      weight: FontWeight.w600,
                      tabular: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (budget > 0) ...[
                BudgetBar(spent: spent, budget: budget),
                const SizedBox(height: 10),
                Text(
                  spent <= budget
                      ? '${money(budget - spent)} left of ${money(budget)}'
                      : '${money(spent - budget)} over your budget',
                  style: textStyle(
                    context,
                    size: 13,
                    color: spent <= budget ? p.secondary : p.danger,
                  ),
                ),
              ] else
                Text(
                  'Set a monthly budget in Plan whenever you’re ready.',
                  style: textStyle(context, size: 13, color: p.secondary),
                ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }
}

class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.spent, required this.budget});
  final int spent, budget;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fraction = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: '${money(spent)} spent of ${money(budget)} budget',
      child: Container(
        height: 7,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.line,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: Container(color: spent > budget ? p.danger : p.accent),
          ),
        ),
      ),
    );
  }
}

class HomeBalances extends StatelessWidget {
  const HomeBalances({super.key, required this.app});
  final AppController app;
  List<Wallet> get displayWallets {
    final ledger = app.ledger;
    final active = ledger.availableWallets;
    return [
      ...active.where((w) => ledger.calculate(w).balance != 0),
      ...active.where((w) => ledger.calculate(w).balance == 0),
    ];
  }

  Future<void> showWallets(BuildContext context) {
    final wallets = displayWallets;
    return showPocketSheet<void>(
      context: context,
      builder: (ctx) => SheetFrame(
        title: 'Your wallets',
        subtitle: 'Active wallets · balances from manual records',
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < wallets.length; i++)
                    HomeWalletBalanceRow(
                      app: app,
                      wallet: wallets[i],
                      actionLabel: 'Manage wallets',
                      last: i == wallets.length - 1,
                      onTap: () {
                        Navigator.pop(ctx);
                        pushPocket<void>(context, WalletsPage(app: app));
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              'Manage wallets',
              onPressed: () {
                Navigator.pop(ctx);
                pushPocket<void>(context, WalletsPage(app: app));
              },
            ),
            const SizedBox(height: 12),
            Text(
              'These are tracked records. Check your actual wallets separately. Hidden wallets are excluded here; their history is kept.',
              style: textStyle(ctx, size: 13, color: Palette.of(ctx).secondary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = app.ledger, p = Palette.of(context), wallets = displayWallets;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.25;
    final visible = wallets
        .take(wallets.length <= 3 ? 3 : (large ? 1 : 2))
        .toList();
    final remaining = wallets.length - visible.length;
    return Surface(
      key: const ValueKey('home-balances'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total tracked balance',
                    style: textStyle(
                      context,
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                Press(
                  key: const ValueKey('home-view-wallets'),
                  label: wallets.isEmpty
                      ? 'Add or restore wallets'
                      : 'View all ${wallets.length} active wallet balances. $remaining more wallets beyond this preview.',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  onPressed: wallets.isEmpty
                      ? () => pushPocket<void>(context, WalletsPage(app: app))
                      : () => showWallets(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            wallets.isEmpty ? 'Wallets' : 'View all',
                            style: textStyle(
                              context,
                              size: 14,
                              color: p.accent,
                            ),
                          ),
                          if (remaining > 0)
                            Text(
                              '+$remaining more',
                              style: textStyle(
                                context,
                                size: 11,
                                color: p.secondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: p.accent,
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            child: Semantics(
              label: wallets.isEmpty
                  ? 'No active wallets. Add or restore a wallet to see a tracked balance.'
                  : 'Total tracked balance ${money(l.activeWalletBalance)} across ${wallets.length} active wallets. Calculated from manual records.',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          wallets.isEmpty ? '—' : money(l.activeWalletBalance),
                          key: const ValueKey('home-total-balance'),
                          style: textStyle(
                            context,
                            size: large ? 36 : 44,
                            weight: FontWeight.w600,
                            tabular: true,
                            color: l.activeWalletBalance < 0 ? p.danger : p.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      wallets.isEmpty
                          ? 'No active wallets'
                          : 'Active wallets · manual records',
                      style: textStyle(context, size: 12, color: p.secondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < visible.length; i++) ...[
            if (i == 0) const Rule(),
            HomeWalletBalanceRow(
              app: app,
              wallet: visible[i],
              last: i == visible.length - 1,
              onTap: () => showWallets(context),
            ),
          ],
        ],
      ),
    );
  }
}

class HomeWalletBalanceRow extends StatelessWidget {
  const HomeWalletBalanceRow({
    super.key,
    required this.app,
    required this.wallet,
    required this.onTap,
    this.actionLabel = 'View wallet balances',
    this.last = false,
  });
  final AppController app;
  final Wallet wallet;
  final VoidCallback onTap;
  final String actionLabel;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final balance = app.ledger.calculate(wallet).balance;
    final p = Palette.of(context);
    return Column(
      children: [
        Press(
          key: ValueKey('home-wallet-${wallet.id}'),
          label:
              '${wallet.label} tracked balance ${money(balance)}. $actionLabel.',
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          onPressed: onTap,
          radius: 0,
          child: Row(
            children: [
              IconTile(
                walletIcon(wallet.icon),
                color: walletColor(context, wallet),
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final stacked =
                        MediaQuery.textScalerOf(context).scale(1) > 1.25 ||
                        wallet.label.length > 18 ||
                        bounds.maxWidth < 230;
                    final name = Text(
                      wallet.label,
                      style: textStyle(
                        context,
                        size: 14,
                        weight: FontWeight.w500,
                      ),
                    );
                    final value = Text(
                      money(balance),
                      key: ValueKey('home-wallet-value-${wallet.id}'),
                      style: textStyle(
                        context,
                        size: 17,
                        weight: FontWeight.w600,
                        tabular: true,
                        color: balance < 0 ? p.danger : p.ink,
                      ),
                    );
                    return stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [name, const SizedBox(height: 5), value],
                          )
                        : Row(
                            children: [
                              Expanded(child: name),
                              const SizedBox(width: 10),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: value,
                                ),
                              ),
                            ],
                          );
                  },
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Padding(padding: EdgeInsets.only(left: 62), child: Rule()),
      ],
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.app});
  final AppController app;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  EntryKind? kind;
  Wallet? wallet;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = widget.app.ledger;
    final entries = l.active
        .where(
          (e) =>
              (kind == null || (e.adjustment == null && kind == e.kind)) &&
              (wallet == null || wallet == e.wallet || wallet == e.toWallet) &&
              ('${e.adjustment != null ? 'Balance adjustment' : l.category(e.categoryId)?.name ?? 'Transfer'} ${e.note} ${money(e.centavos)} ${moneyInput(e.centavos)} ${l.wallet(e.wallet)!.label} ${l.wallet(e.toWallet)?.label ?? ''}'
                  .toLowerCase()
                  .contains(query.toLowerCase())),
        )
        .toList();
    return Column(
      children: [
        PageHeading(
          'History',
          subtitle: 'Every entry, easy to change.',
          trailing: Press(
            label: 'Add entry from History',
            onPressed: () => openEntry(context, widget.app),
            padding: const EdgeInsets.all(12),
            child: Icon(CupertinoIcons.plus, color: p.accent, size: 24),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: CupertinoSearchTextField(
            placeholder: 'Category, note or amount',
            placeholderStyle: textStyle(context, size: 15, color: p.secondary),
            style: textStyle(context, size: 15),
            decoration: BoxDecoration(
              color: p.surface,
              border: p.border,
              borderRadius: BorderRadius.circular(p.controlCorner(9)),
            ),
            itemColor: p.secondary,
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final choice in [null, ...EntryKind.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Press(
                      onPressed: () => setState(() => kind = choice),
                      color: kind == choice ? p.tint : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      radius: p.controlCorner(12),
                      child: Text(
                        choice == null
                            ? 'All'
                            : switch (choice) {
                                EntryKind.expense => 'Expenses',
                                EntryKind.income => 'Income',
                                EntryKind.transfer => 'Transfers',
                              },
                        style: textStyle(
                          context,
                          size: 13,
                          weight: FontWeight.w600,
                          color: kind == choice ? p.accent : p.secondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Wallet',
                  style: textStyle(context, size: 12, color: p.secondary),
                ),
                const SizedBox(width: 8),
                for (final choice in [null, ...l.wallets])
                  Press(
                    onPressed: () => setState(() => wallet = choice),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Text(
                      choice?.label ?? 'All',
                      style: textStyle(
                        context,
                        size: 12,
                        color: wallet == choice ? p.accent : p.secondary,
                        weight: wallet == choice
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? SingleChildScrollView(
                  child: QuietMessage(
                    l.entries.isEmpty
                        ? 'Nothing recorded yet'
                        : 'No matching entries',
                    l.entries.isEmpty
                        ? 'Your first entry will appear here.'
                        : 'Try another filter or search.',
                    action: l.entries.isEmpty
                        ? PrimaryButton(
                            'Add an entry',
                            onPressed: () => openEntry(context, widget.app),
                          )
                        : null,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final heading = i == 0 || entries[i - 1].date != e.date;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (heading)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                            child: Text(
                              e.date == dayKey(widget.app.clock())
                                  ? 'Today'
                                  : shortDate(e.date),
                              style: textStyle(
                                context,
                                size: 13,
                                color: p.secondary,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Surface(
                          padding: EdgeInsets.zero,
                          roundTop: heading,
                          roundBottom:
                              i == entries.length - 1 ||
                              entries[i + 1].date != e.date,
                          child: Column(
                            children: [
                              EntryRow(
                                entry: e,
                                ledger: l,
                                onTap: () => pushPocket<void>(
                                  context,
                                  EntryDetailPage(app: widget.app, id: e.id),
                                ),
                              ),
                              if (i < entries.length - 1 &&
                                  entries[i + 1].date == e.date)
                                const Padding(
                                  padding: EdgeInsets.only(left: 70),
                                  child: Rule(),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class PlanPage extends StatefulWidget {
  const PlanPage({super.key, required this.app});
  final AppController app;
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late DateTime month = DateTime(
    widget.app.clock().year,
    widget.app.clock().month,
  );
  String? error;
  Future<void> edit() async {
    final existing = widget.app.ledger.budgets[monthKey(month)] ?? 0;
    final value = await textPrompt(
      context,
      title: 'Monthly budget',
      value: existing == 0 ? '' : moneyInput(existing),
      hint: 'Amount in PHP',
      amount: true,
      maxLength: 12,
      message:
          'A spending limit for ${monthNames[month.month - 1]}. Enter 0 to remove it.',
    );
    if (value == null || !mounted) return;
    try {
      final cents = parseMoney(value, allowZero: true);
      await widget.app.setBudget(monthKey(month), cents);
      if (mounted) setState(() => error = widget.app.storageError);
    } on LedgerException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = widget.app.ledger;
    final key = monthKey(month);
    final spent = l.total(EntryKind.expense, month: key);
    final budget = l.budgets[key] ?? 0;
    final categories = otherExpenseLast(
      l.categories
          .map(
            (c) =>
                (c, l.total(EntryKind.expense, month: key, categoryId: c.id)),
          )
          .where((item) => item.$2 > 0)
          .toList()
        ..sort((a, b) => b.$2.compareTo(a.$2)),
      (item) => item.$1,
    );
    return ListView(
      key: const ValueKey('plan-scroll'),
      padding: EdgeInsets.zero,
      children: [
        const PageHeading('Plan', subtitle: 'A simple limit. A clearer month.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Press(
                    label: 'Previous month',
                    onPressed: month.year > 1900 || month.month > 1
                        ? () => setState(
                            () => month = DateTime(month.year, month.month - 1),
                          )
                        : null,
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      size: 18,
                      color: p.accent,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${monthNames[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                      style: textStyle(
                        context,
                        size: 17,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Press(
                    label: 'Next month',
                    onPressed: month.year < 2200 || month.month < 12
                        ? () => setState(
                            () => month = DateTime(month.year, month.month + 1),
                          )
                        : null,
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                      color: p.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Surface(
                key: const ValueKey('plan-spending-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly spending',
                      style: textStyle(context, size: 16, color: p.secondary),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      money(spent),
                      style: textStyle(
                        context,
                        size: 32,
                        weight: FontWeight.w600,
                        tabular: true,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (budget > 0) ...[
                      BudgetBar(spent: spent, budget: budget),
                      const SizedBox(height: 12),
                      Text(
                        spent <= budget
                            ? '${money(budget - spent)} left of ${money(budget)}'
                            : '${money(spent - budget)} over ${money(budget)}',
                        style: textStyle(
                          context,
                          size: 14,
                          color: spent <= budget ? p.secondary : p.danger,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SecondaryButton(
                      budget > 0 ? 'Edit budget' : 'Set a monthly budget',
                      icon: CupertinoIcons.slider_horizontal_3,
                      onPressed: widget.app.busy ? null : edit,
                    ),
                  ],
                ),
              ),
              ErrorLine(error),
              const SizedBox(height: 24),
              Text(
                'Where it went',
                style: textStyle(context, size: 19, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              if (categories.isEmpty)
                const QuietMessage(
                  'Room to begin',
                  'Recorded expenses will appear here by category.',
                  icon: CupertinoIcons.chart_bar,
                )
              else
                Surface(
                  key: const ValueKey('plan-category-card'),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < categories.length; i++)
                        GroupRow(
                          categories[i].$1.name,
                          icon: categoryIcon(categories[i].$1.icon),
                          trailing: Text(
                            money(categories[i].$2),
                            style: textStyle(
                              context,
                              size: 15,
                              weight: FontWeight.w600,
                              tabular: true,
                            ),
                          ),
                          last: i == categories.length - 1,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Only expenses count toward this budget. Income and transfers are kept separate.',
                style: textStyle(context, size: 13, color: p.secondary),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }
}

class PocketPage extends StatelessWidget {
  const PocketPage(this.title, {super.key, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: Palette.of(context).background,
    navigationBar: CupertinoNavigationBar(
      middle: Text(
        title,
        style: textStyle(context, size: 17, weight: FontWeight.w600),
      ),
      previousPageTitle: 'Back',
      trailing: trailing,
      backgroundColor: Palette.of(context).background,
      border: null,
    ),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: child,
        ),
      ),
    ),
  );
}

class EntryDetailPage extends StatelessWidget {
  const EntryDetailPage({super.key, required this.app, required this.id});
  final AppController app;
  final String id;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final e = app.ledger.entry(id);
      final p = Palette.of(context);
      if (e == null || e.deleted) {
        return const PocketPage(
          'Entry',
          child: QuietMessage(
            'This entry was deleted',
            'You can recover it in Settings → Recently deleted.',
          ),
        );
      }
      final category = app.ledger.category(e.categoryId);
      return PocketPage(
        'Entry',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                IconTile(
                  e.kind == EntryKind.transfer
                      ? CupertinoIcons.arrow_right_arrow_left
                      : categoryIcon(category?.icon),
                  color: e.kind == EntryKind.transfer
                      ? p.blue
                      : categoryColor(context, category?.icon),
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    e.adjustment != null
                        ? 'Balance adjustment'
                        : switch (e.kind) {
                            EntryKind.expense => 'Expense',
                            EntryKind.income => 'Income',
                            EntryKind.transfer => 'Transfer',
                          },
                    style: textStyle(
                      context,
                      size: 20,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  money(e.centavos),
                  style: textStyle(
                    context,
                    size: 40,
                    weight: FontWeight.w600,
                    tabular: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EntryFact('Date', shortDate(e.date)),
                  if (category != null) EntryFact('Category', category.name),
                  if (e.adjustment != null) ...[
                    EntryFact(
                      'Previously tracked',
                      money(e.adjustment!.expected),
                    ),
                    EntryFact('Actual at check', money(e.adjustment!.actual)),
                  ],
                  if (e.billId != null)
                    EntryFact('Bill due date', shortDate(e.billDueDate!)),
                  EntryFact(
                    e.adjustment != null
                        ? 'Wallet'
                        : e.kind == EntryKind.transfer
                        ? 'From'
                        : entryAction(e.kind),
                    app.ledger.wallet(e.wallet)!.label,
                  ),
                  if (e.toWallet != null)
                    EntryFact('To', app.ledger.wallet(e.toWallet)!.label),
                  if (e.occurrenceDate != null)
                    EntryFact(
                      'Allowance occurrence',
                      'Originally ${shortDate(e.occurrenceDate!)}. Editing or deleting will not repeat it.',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Note',
                    style: textStyle(context, size: 13, color: p.secondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.note.isEmpty ? 'No note added' : e.note,
                    style: textStyle(context, size: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (e.adjustment == null)
              PrimaryButton(
                'Edit entry',
                icon: CupertinoIcons.pencil,
                onPressed: app.busy
                    ? null
                    : () => openEntry(context, app, editing: e),
              ),
            const SizedBox(height: 12),
            Press(
              onPressed: app.busy
                  ? null
                  : () async {
                      final approved = await confirm(
                        context,
                        title: 'Delete this entry?',
                        message: 'You can undo this or recover it in Recently deleted.',
                        action: 'Delete entry',
                        destructive: true,
                      );
                      if (approved && context.mounted) {
                        final success = await app.delete(e);
                        if (success && context.mounted) Navigator.pop(context);
                      }
                    },
              child: Text(
                'Delete entry',
                style: textStyle(context, color: p.danger),
              ),
            ),
            ErrorLine(app.storageError),
          ],
        ),
      );
    },
  );
}

class EntryFact extends StatelessWidget {
  const EntryFact(this.label, this.value, {super.key, this.last = false});
  final String label, value;
  final bool last;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Semantics(
          label: '$label: $value',
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    MediaQuery.textScalerOf(context).scale(1) > 1.25 ||
                    value.length > 24 ||
                    constraints.maxWidth < 260;
                final caption = Text(
                  label,
                  style: textStyle(
                    context,
                    size: stacked ? 13 : 15,
                    color: Palette.of(context).secondary,
                  ),
                );
                final content = Text(
                  value,
                  key: ValueKey('entry-fact-$label'),
                  textAlign: stacked ? TextAlign.start : TextAlign.end,
                  style: textStyle(context, size: 16, weight: FontWeight.w500),
                );
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [caption, const SizedBox(height: 6), content],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: caption),
                          const SizedBox(width: 18),
                          Expanded(flex: 3, child: content),
                        ],
                      );
              },
            ),
          ),
        ),
      ),
      if (!last)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Rule(),
        ),
    ],
  );
}

class WalletsPage extends StatefulWidget {
  const WalletsPage({super.key, required this.app});
  final AppController app;
  @override
  State<WalletsPage> createState() => _WalletsPageState();
}

class _WalletsPageState extends State<WalletsPage> {
  String? error;
  Future<void> opening(Wallet wallet) async {
    final value = await textPrompt(
      context,
      title: '${wallet.label} opening balance',
      value: moneyInput(widget.app.ledger.openings[wallet] ?? 0),
      hint: 'Amount in PHP',
      amount: true,
      signed: true,
      maxLength: 13,
      message: 'The balance before your first recorded entry. This changes your tracked balance.',
    );
    if (value == null || !mounted) return;
    try {
      await widget.app.setOpening(
        wallet,
        parseMoney(value, signed: true, allowZero: true),
      );
      if (mounted) setState(() => error = widget.app.storageError);
    } on LedgerException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final p = Palette.of(context);
      return PocketPage(
        'Wallets',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Your money, in view.',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'These are tracked balances from all recorded entries. Check your actual wallets separately.',
              style: textStyle(context, size: 14, color: p.secondary),
            ),
            const SizedBox(height: 24),
            Surface(
              padding: EdgeInsets.zero,
              child: GroupRow(
                'Direct entry buttons',
                subtitle:
                    '${widget.app.ledger.quickWallets.length} selected · choose and arrange',
                icon: CupertinoIcons.square_grid_2x2,
                last: true,
                onTap: () => pushPocket<void>(
                  context,
                  DirectEntryButtonsPage(app: widget.app),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (widget.app.ledger.availableWallets.isEmpty)
              const QuietMessage(
                'No active wallets',
                'Add a wallet or restore one from Hidden wallets to record an entry.',
              ),
            for (final wallet in widget.app.ledger.availableWallets) ...[
              Builder(
                builder: (context) {
                  final calc = widget.app.ledger.calculate(wallet);
                  return Surface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  wallet.label,
                                  style: textStyle(
                                    context,
                                    size: 20,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  money(calc.balance),
                                  style: textStyle(
                                    context,
                                    size: 24,
                                    weight: FontWeight.w600,
                                    tabular: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Rule(),
                        GroupRow(
                          'Wallet settings',
                          subtitle: wallet.archived
                              ? 'Archived · history is kept'
                              : 'Name, icon, color and quick entry',
                          icon: walletIcon(wallet.icon),
                          onTap: () => pushPocket<void>(
                            context,
                            WalletEditorPage(app: widget.app, wallet: wallet),
                          ),
                        ),
                        GroupRow(
                          'Remove wallet',
                          subtitle: widget.app.ledger.hasWalletHistory(wallet)
                              ? 'Archive and keep recorded history'
                              : 'Recoverable from Hidden wallets',
                          icon: CupertinoIcons.minus_circle,
                          onTap: widget.app.busy
                              ? null
                              : () async {
                                  final ok = await confirmWalletRemoval(
                                    context,
                                    widget.app,
                                    wallet,
                                  );
                                  if (mounted && !ok) {
                                    setState(
                                      () => error = widget.app.storageError,
                                    );
                                  }
                                },
                        ),
                        GroupRow(
                          'Check balance',
                          subtitle:
                              'Compare with the actual amount in this wallet',
                          icon: CupertinoIcons.checkmark_circle,
                          onTap: widget.app.busy
                              ? null
                              : () => pushPocket<void>(
                                  context,
                                  BalanceCheckPage(
                                    app: widget.app,
                                    wallet: wallet,
                                  ),
                                ),
                        ),
                        GroupRow(
                          'Opening balance',
                          subtitle: 'Tap to change',
                          trailing: Text(
                            money(calc.opening),
                            style: textStyle(context, size: 14, tabular: true),
                          ),
                          onTap: widget.app.busy ? null : () => opening(wallet),
                        ),
                        GroupRow(
                          'Income',
                          trailing: Text(
                            '+${money(calc.income)}',
                            style: textStyle(
                              context,
                              size: 14,
                              color: p.green,
                              tabular: true,
                            ),
                          ),
                        ),
                        GroupRow(
                          'Expenses',
                          trailing: Text(
                            '−${money(calc.expenses)}',
                            style: textStyle(context, size: 14, tabular: true),
                          ),
                        ),
                        GroupRow(
                          'Transfers in',
                          trailing: Text(
                            '+${money(calc.incoming)}',
                            style: textStyle(context, size: 14, tabular: true),
                          ),
                        ),
                        GroupRow(
                          'Transfers out',
                          trailing: Text(
                            '−${money(calc.outgoing)}',
                            style: textStyle(context, size: 14, tabular: true),
                          ),
                          last: calc.adjustments == 0,
                        ),
                        if (calc.adjustments != 0)
                          GroupRow(
                            'Balance adjustments',
                            trailing: Text(
                              money(calc.adjustments),
                              style: textStyle(
                                context,
                                size: 14,
                                tabular: true,
                              ),
                            ),
                            last: true,
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
            ],
            Surface(
              padding: EdgeInsets.zero,
              child: GroupRow(
                'Hidden wallets',
                subtitle:
                    '${widget.app.ledger.wallets.where((w) => w.archived).length} archived or removed · restore anytime',
                icon: CupertinoIcons.archivebox,
                last: true,
                onTap: () => pushPocket<void>(
                  context,
                  HiddenWalletsPage(app: widget.app),
                ),
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              'Add a wallet',
              icon: CupertinoIcons.add,
              onPressed: widget.app.busy
                  ? null
                  : () => pushPocket<void>(
                      context,
                      WalletEditorPage(app: widget.app),
                    ),
            ),
            const SizedBox(height: 16),
            ErrorLine(error),
            PrimaryButton(
              'Record a transfer',
              icon: CupertinoIcons.arrow_right_arrow_left,
              onPressed: () {
                if (widget.app.draft?.dirty != true) {
                  widget.app.startDraft();
                  widget.app.draft!.kind = EntryKind.transfer;
                  widget.app.updateDraft();
                }
                openEntry(context, widget.app);
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Opening + income − expenses + transfers in − transfers out + balance adjustments. Wallets are manual records; this app never moves real money.',
              style: textStyle(context, size: 13, color: p.secondary),
            ),
          ],
        ),
      );
    },
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.app});
  final AppController app;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  bool fileBusy = false;
  bool reminderBusy = false;
  ReminderState reminder = const ReminderState();
  String? reminderError;
  int reminderRead = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadReminder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !reminderBusy) loadReminder();
  }

  Future<void> loadReminder() async {
    final bridge = widget.app.bridge;
    if (bridge == null) return;
    final read = ++reminderRead;
    try {
      final state = await bridge.reminderState();
      if (mounted && !reminderBusy && read == reminderRead) {
        setState(() {
          reminder = state;
          reminderError = state.enabled && !state.permitted
              ? 'Notifications are blocked. Allow Ponpon notifications in Android settings to resume your reminder.'
              : state.enabled && state.nextAtMilliseconds == null
              ? 'The reminder could not be scheduled. Turn it off and try again.'
              : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => reminderError =
              'Reminder settings could not load. Reopen Settings to retry.',
        );
      }
    }
  }

  String reminderTime(BuildContext context, int minute) {
    final hour = minute ~/ 60;
    final tail = (minute % 60).toString().padLeft(2, '0');
    if (MediaQuery.alwaysUse24HourFormatOf(context)) {
      return '${hour.toString().padLeft(2, '0')}:$tail';
    }
    final local = CupertinoLocalizations.of(context);
    return '${hour % 12 == 0 ? 12 : hour % 12}:$tail ${hour < 12 ? local.anteMeridiemAbbreviation : local.postMeridiemAbbreviation}';
  }

  Future<int?> chooseReminderTime() async {
    final now = widget.app.clock();
    var minute = reminder.minuteOfDay ?? now.hour * 60 + now.minute;
    final p = Palette.of(context);
    // The wheel's initial position is a placeholder; only Done chooses a time.
    return showPocketSheet<int>(
      context: context,
      builder: (ctx) => Container(
        color: p.surface,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    Expanded(
                      child: Text(
                        'Reminder time',
                        textAlign: TextAlign.center,
                        style: textStyle(
                          ctx,
                          size: 17,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.pop(ctx, minute),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(ctx),
                  initialDateTime: DateTime(
                    2026,
                    1,
                    1,
                    minute ~/ 60,
                    minute % 60,
                  ),
                  onDateTimeChanged: (value) =>
                      minute = value.hour * 60 + value.minute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> changeReminder(bool enabled, {bool changeTime = false}) async {
    if (reminderBusy || widget.app.busy) return;
    final bridge = widget.app.bridge;
    if (bridge == null) {
      setState(
        () =>
            reminderError = 'Daily reminders are available in the Android app.',
      );
      return;
    }
    setState(() {
      reminderRead++;
      reminderBusy = true;
      reminderError = null;
    });
    try {
      int? minute = reminder.minuteOfDay;
      if (enabled || changeTime) {
        minute = await chooseReminderTime();
        if (minute == null || !mounted) return;
      }
      if (enabled && !await bridge.requestReminderPermission()) {
        if (!mounted) return;
        reminder = await bridge.setReminder(
          enabled: false,
          minuteOfDay: minute,
        );
        if (mounted) {
          setState(
            () => reminderError = 'Notifications are blocked. The reminder stays off. Allow Ponpon notifications in Android settings, then try again.',
          );
        }
        return;
      }
      final state = await bridge.setReminder(
        enabled: enabled,
        minuteOfDay: minute,
      );
      if (mounted) {
        setState(() {
          reminder = state;
          if (enabled && state.nextAtMilliseconds == null) reminderError = 'The reminder could not be scheduled. Turn it off and try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => reminderError =
              'The reminder could not be changed. Reopen Settings to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => reminderBusy = false);
    }
  }

  Future<void> export() async {
    if (fileBusy) return;
    setState(() {
      fileBusy = true;
      error = null;
    });
    try {
      final bridge = widget.app.bridge;
      if (bridge == null) {
        throw const LedgerException(
          'File export is available in the Android app.',
        );
      }
      final success = await bridge.export(
        widget.app.ledger.encode(),
        'Ponpon-${dayKey(widget.app.clock())}.json',
      );
      if (success) {
        widget.app.feedback = 'Backup exported';
        widget.app.feedbackUndo = false;
        widget.app.publish();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not export. Choose another location and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> restore() async {
    if (fileBusy) return;
    setState(() {
      fileBusy = true;
      error = null;
    });
    try {
      final bridge = widget.app.bridge;
      if (bridge == null) {
        throw const LedgerException(
          'Backup restore is available in the Android app.',
        );
      }
      final text = await bridge.pickBackup();
      if (text == null || !mounted) return;
      final imported = Ledger.decode(text);
      final preview = previewRestore(widget.app.ledger, imported);
      final approved = await confirm(
        context,
        title: 'Restore this backup?',
        message:
            '${preview.added} entries to add. ${preview.skipped} already present.\n${preview.ledger.wallets.map((w) => '${w.label}: ${money(preview.ledger.calculate(w).balance)}').join(' · ')}\nImported allowance schedules are paused for review.\nChanged entries are never overwritten. A local recovery copy will be kept.',
        action: 'Restore backup',
      );
      if (approved) {
        await widget.app.restore(preview);
        if (mounted) setState(() => error = widget.app.storageError);
      }
    } on LedgerException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not read that file. Choose a valid Ponpon JSON backup.',
        );
      }
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> pinWidget({bool compact = false, bool balance = false}) async {
    try {
      final requested =
          await widget.app.bridge?.pinWidget(
            compact: compact,
            balance: balance,
          ) ??
          false;
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: Text(requested ? 'Add Ponpon' : 'Add from your home screen'),
            content: Text(
              requested
                  ? 'Confirm the ${balance
                        ? 'balance 2 × 2'
                        : compact
                        ? 'compact 2 × 2'
                        : 'larger'} widget in your launcher. ${balance ? 'Amounts stay hidden unless you enable Show balance on widget.' : 'It shows categories only.'} Your launcher controls the final grid size.'
                  : 'Long-press an empty area on your home screen, choose Widgets, then Ponpon${balance
                        ? ' · Balance (2 × 2)'
                        : compact
                        ? ' · Quick entry (2 × 2)'
                        : ''}. Your launcher controls the final grid size. You can also long-press the app icon for Quick add.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Use your launcher’s Widgets menu to add Ponpon.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final app = widget.app;
      final prefs = app.ledger.preferences;
      final p = Palette.of(context);
      return PocketPage(
        'Settings',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Make it yours',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  GroupRow(
                    'Wallets & opening balances',
                    icon: CupertinoIcons.money_dollar_circle,
                    onTap: () =>
                        pushPocket<void>(context, WalletsPage(app: app)),
                  ),
                  GroupRow(
                    'Scheduled allowance',
                    subtitle: 'Background recording with app-opening catch-up',
                    icon: CupertinoIcons.calendar,
                    onTap: () =>
                        pushPocket<void>(context, AllowancePage(app: app)),
                  ),
                  GroupRow(
                    'Upcoming bills',
                    subtitle: 'Due dates, reminders and recorded payments',
                    icon: CupertinoIcons.calendar,
                    onTap: () => pushPocket<void>(context, BillsPage(app: app)),
                  ),
                  GroupRow(
                    'Categories',
                    icon: CupertinoIcons.square_grid_2x2,
                    onTap: () =>
                        pushPocket<void>(context, CategoriesPage(app: app)),
                  ),
                  GroupRow(
                    'Compact home widget',
                    subtitle: '2 × 2 · categories only',
                    icon: CupertinoIcons.square_grid_2x2,
                    onTap: () => pinWidget(compact: true),
                  ),
                  GroupRow(
                    'Balance home widget',
                    subtitle: '2 × 2 · tap to add an entry',
                    icon: CupertinoIcons.money_dollar_circle,
                    onTap: () => pinWidget(balance: true),
                  ),
                  GroupRow(
                    'Home-screen widget',
                    subtitle: 'Categories only. No amounts or notes.',
                    icon: CupertinoIcons.rectangle_grid_1x2,
                    onTap: () => pinWidget(),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Appearance & feel',
              style: textStyle(context, size: 16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: GroupRow(
                'Visual style',
                subtitle: visualStyleName(prefs.visualStyle),
                icon: CupertinoIcons.paintbrush,
                last: true,
                onTap: () =>
                    pushPocket<void>(context, VisualStylePage(app: app)),
              ),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Appearance', style: textStyle(context)),
                        if (prefs.visualStyle == VisualStyle.midnight) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Midnight uses dark appearance. Your previous choice is kept.',
                            style: textStyle(
                              context,
                              size: 13,
                              color: p.secondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoSlidingSegmentedControl<String>(
                            groupValue:
                                prefs.visualStyle == VisualStyle.midnight
                                ? 'dark'
                                : prefs.theme,
                            disabledChildren:
                                prefs.visualStyle == VisualStyle.midnight
                                ? {'system', 'light', 'dark'}
                                : {},
                            onValueChanged: (value) {
                              if (!app.busy && value != null) {
                                app.preferences(prefs.copy(theme: value));
                              }
                            },
                            children: {
                              for (final value in ['system', 'light', 'dark'])
                                value: SegmentLabel(
                                  value[0].toUpperCase() + value.substring(1),
                                  key: ValueKey('theme-$value'),
                                ),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Rule(),
                  GroupRow(
                    'Haptics',
                    subtitle: 'A light tap when you enter and save.',
                    trailing: PocketSwitch(
                      label: 'Haptics',
                      value: prefs.haptics,
                      onChanged: app.busy
                          ? null
                          : (value) =>
                                app.preferences(prefs.copy(haptics: value)),
                    ),
                  ),
                  GroupRow(
                    'Reduce motion',
                    subtitle: 'Also follows Android’s animation setting.',
                    trailing: PocketSwitch(
                      label: 'Reduce motion',
                      value: prefs.reduceMotion,
                      onChanged: app.busy
                          ? null
                          : (value) => app.preferences(
                              prefs.copy(reduceMotion: value),
                            ),
                    ),
                  ),
                  GroupRow(
                    'Show balance on widget',
                    subtitle:
                        'Visible on your home screen. Tracked amounts only.',
                    trailing: PocketSwitch(
                      label: 'Show balance on widget',
                      value: prefs.balanceWidgetVisible,
                      onChanged: app.busy
                          ? null
                          : (value) => app.preferences(
                              prefs.copy(balanceWidgetVisible: value),
                            ),
                    ),
                  ),
                  GroupRow(
                    'Private app previews',
                    subtitle: 'Hides app previews and prevents screenshots.',
                    trailing: PocketSwitch(
                      label: 'Private app previews',
                      value: prefs.privatePreview,
                      onChanged: app.busy
                          ? null
                          : (value) => app.preferences(
                              prefs.copy(privatePreview: value),
                            ),
                    ),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Daily reminder',
              style: textStyle(context, size: 16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  GroupRow(
                    'Remind me to log',
                    subtitle:
                        'Anything to log today? Add your expenses or income.',
                    trailing: PocketSwitch(
                      label: 'Daily reminder',
                      value: reminder.enabled,
                      onChanged: app.busy || reminderBusy
                          ? null
                          : changeReminder,
                    ),
                  ),
                  GroupRow(
                    'Time',
                    subtitle: reminder.minuteOfDay == null
                        ? 'Choose a time when you turn it on.'
                        : '${reminderTime(context, reminder.minuteOfDay!)} · Your device’s local time',
                    icon: CupertinoIcons.clock,
                    onTap: app.busy || reminderBusy
                        ? null
                        : () => changeReminder(
                            reminder.enabled,
                            changeTime: true,
                          ),
                    last: reminder.permitted,
                  ),
                  if (!reminder.permitted)
                    GroupRow(
                      'Allow notifications',
                      subtitle:
                          'Open Ponpon’s notification settings in Android.',
                      icon: CupertinoIcons.bell,
                      onTap: reminderBusy
                          ? null
                          : () async {
                              try {
                                await app.bridge?.openNotificationSettings();
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => reminderError = 'Open Android Settings, then Ponpon notifications.',
                                  );
                                }
                              }
                            },
                      last: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'A quiet reminder, around your chosen time. Android may delay it to save battery. Tapping it opens Add entry; you choose the wallet.',
              style: textStyle(context, size: 12, color: p.secondary),
            ),
            ErrorLine(reminderError),
            const SizedBox(height: 24),
            Text(
              'Your data',
              style: textStyle(context, size: 16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  GroupRow(
                    'Export backup',
                    subtitle: fileBusy
                        ? 'Waiting for your file choice…'
                        : 'Save a complete JSON copy wherever you choose.',
                    icon: CupertinoIcons.square_arrow_up,
                    onTap: fileBusy || app.busy ? null : export,
                  ),
                  GroupRow(
                    'Restore backup',
                    subtitle:
                        'Validated merge. Existing entries stay protected.',
                    icon: CupertinoIcons.arrow_down_doc,
                    onTap: fileBusy || app.busy ? null : restore,
                  ),
                  GroupRow(
                    'Recover before last restore',
                    icon: CupertinoIcons.arrow_uturn_left,
                    onTap: app.busy
                        ? null
                        : () async {
                            final approved = await confirm(
                              context,
                              title: 'Recover the earlier ledger?',
                              message: 'Return to the local snapshot from before your last restore. Export the current ledger first if you want to keep newer changes.',
                              action: 'Recover earlier ledger',
                            );
                            if (approved) {
                              await app.recoverBeforeRestore();
                              if (mounted) {
                                setState(() => error = app.storageError);
                              }
                            }
                          },
                  ),
                  GroupRow(
                    'Recently deleted',
                    icon: CupertinoIcons.trash,
                    onTap: () =>
                        pushPocket<void>(context, DeletedPage(app: app)),
                  ),
                  GroupRow(
                    'Undo last transaction change',
                    subtitle: 'Saved across app restarts.',
                    icon: CupertinoIcons.arrow_uturn_left,
                    onTap: app.ledger.changes.isEmpty || app.busy
                        ? null
                        : () => app.undo(),
                    last: true,
                  ),
                ],
              ),
            ),
            ErrorLine(error ?? app.storageError),
            const SizedBox(height: 20),
            Text(
              'Records stay in this app’s private storage. There is no cloud or automatic backup. Uninstalling removes local data. Exported backups are readable JSON; store them somewhere private.',
              style: textStyle(context, size: 12, color: p.secondary),
            ),
            const SizedBox(height: 18),
            Text(
              'Ponpon 0.2.8 · Budget & Expenses\nPHP · Offline · Manual wallet tracking',
              style: textStyle(context, size: 12, color: p.secondary),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.app});
  final AppController app;
  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String? error;
  Future<void> edit(Category? category) async {
    final name = await textPrompt(
      context,
      title: category == null ? 'New category' : 'Rename category',
      value: category?.name ?? '',
      hint: 'Category name',
      maxLength: 30,
    );
    if (name == null || !mounted) return;
    if (name.trim().isEmpty) {
      setState(() => error = 'Give the category a short name.');
      return;
    }
    final duplicate = widget.app.ledger.categories.any(
      (c) =>
          c.id != category?.id &&
          c.name.toLowerCase() == name.trim().toLowerCase(),
    );
    if (duplicate) {
      setState(() => error = 'A category with this name already exists.');
      return;
    }
    await widget.app.category(
      category?.copy(name: name.trim()) ??
          Category(id: newId(), name: name.trim(), icon: 'other'),
    );
    if (mounted) setState(() => error = widget.app.storageError);
  }

  Future<void> options(Category c) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(c.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              edit(c);
            },
            child: const Text('Rename'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final icon = await showCupertinoModalPopup<String>(
                context: context,
                builder: (inner) => CupertinoActionSheet(
                  title: const Text('Category icon'),
                  actions: categoryIcons
                      .map(
                        (key) => CupertinoActionSheetAction(
                          onPressed: () => Navigator.pop(inner, key),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(categoryIcon(key), size: 22),
                              const SizedBox(width: 10),
                              Text(key[0].toUpperCase() + key.substring(1)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  cancelButton: CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(inner),
                    child: const Text('Cancel'),
                  ),
                ),
              );
              if (icon != null) await widget.app.category(c.copy(icon: icon));
            },
            child: const Text('Change icon'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: !c.archived,
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.app.category(c.copy(archived: !c.archived));
              if (mounted) setState(() => error = widget.app.storageError);
            },
            child: Text(c.archived ? 'Unarchive' : 'Archive'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final p = Palette.of(context);
      final l = widget.app.ledger;
      final managedCategories = otherExpenseLast([
        ...l.categories,
        if (l.category(schoolSuppliesCategory.id) == null)
          schoolSuppliesCategory,
      ], (c) => c);
      final widgetCategories = otherExpenseLast([
        ...l.availableCategories,
        if (l.category(schoolSuppliesCategory.id) == null)
          schoolSuppliesCategory,
      ], (c) => c);
      return PocketPage(
        'Categories',
        trailing: Press(
          label: 'Create category',
          onPressed: widget.app.busy ? null : () => edit(null),
          padding: const EdgeInsets.all(10),
          child: Icon(CupertinoIcons.plus, color: p.accent, size: 21),
        ),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Keep the familiar ones close.',
              style: textStyle(context, size: 25, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Tap a category to rename, change its icon or archive it. Archiving keeps your past entries.',
              style: textStyle(context, size: 14, color: p.secondary),
            ),
            const SizedBox(height: 22),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < managedCategories.length; i++)
                    GroupRow(
                      managedCategories[i].name,
                      subtitle: managedCategories[i].archived
                          ? 'Archived'
                          : null,
                      icon: categoryIcon(managedCategories[i].icon),
                      trailing: Icon(
                        l.preferences.widgetCategories.contains(
                              managedCategories[i].id,
                            )
                            ? CupertinoIcons.pin_fill
                            : CupertinoIcons.pin,
                        size: 18,
                        color: p.secondary,
                      ),
                      onTap: () => options(managedCategories[i]),
                      last: i == managedCategories.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Widget categories',
              style: textStyle(context, size: 17, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose up to four. Names are visible on your home screen; amounts and notes never are.',
              style: textStyle(context, size: 13, color: p.secondary),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final c in widgetCategories)
                    GroupRow(
                      c.name,
                      trailing: PocketSwitch(
                        label: '${c.name} on home widget',
                        value: l.preferences.widgetCategories.contains(c.id),
                        onChanged: widget.app.busy
                            ? null
                            : (value) async {
                                final ids = [...l.preferences.widgetCategories];
                                if (value && ids.length >= 4) {
                                  setState(
                                    () => error = 'Choose up to four widget categories. Turn one off first.',
                                  );
                                  return;
                                }
                                if (value) {
                                  ids.add(c.id);
                                } else {
                                  ids.remove(c.id);
                                }
                                await widget.app.preferences(
                                  l.preferences.copy(widgetCategories: ids),
                                );
                                if (mounted) {
                                  setState(
                                    () => error = widget.app.storageError,
                                  );
                                }
                              },
                      ),
                      last: c == widgetCategories.last,
                    ),
                ],
              ),
            ),
            ErrorLine(error),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}

class DeletedPage extends StatelessWidget {
  const DeletedPage({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final deleted = app.ledger.entries.where((e) => e.deleted).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
      return PocketPage(
        'Recently deleted',
        child: deleted.isEmpty
            ? const QuietMessage(
                'Nothing deleted',
                'Deleted entries stay recoverable here.',
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Deleted entries stay here until you restore them. They do not count toward balances or budgets.',
                    style: textStyle(
                      context,
                      size: 14,
                      color: Palette.of(context).secondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final e in deleted) ...[
                    Surface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          EntryRow(entry: e, ledger: app.ledger),
                          Press(
                            onPressed: app.busy
                                ? null
                                : () => app.restoreDeleted(e),
                            child: Text(
                              'Restore entry',
                              style: textStyle(
                                context,
                                size: 14,
                                color: Palette.of(context).accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ErrorLine(app.storageError),
                ],
              ),
      );
    },
  );
}
