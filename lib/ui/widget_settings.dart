part of 'screens.dart';

enum _WidgetKind { compact, balance, kinds, wallets, wide, quick }

extension on _WidgetKind {
  String get title => switch (this) {
    _WidgetKind.compact => 'Compact home widget',
    _WidgetKind.balance => 'Balance home widget',
    _WidgetKind.kinds => 'Income & expense widget',
    _WidgetKind.wallets => 'Wallet overview widget',
    _WidgetKind.wide => 'Wide balance & categories widget',
    _WidgetKind.quick => 'Home-screen widget',
  };
  String get size => switch (this) {
    _WidgetKind.wallets => '4 × 4',
    _WidgetKind.wide => '4 × 2',
    _WidgetKind.quick => 'Larger layout',
    _ => '2 × 2',
  };
  String get detail => switch (this) {
    _WidgetKind.compact => 'Four category shortcuts',
    _WidgetKind.balance => 'Tracked balance and Add entry',
    _WidgetKind.kinds => 'Start an income or expense entry',
    _WidgetKind.wallets => 'Total and active wallet balances',
    _WidgetKind.wide => 'Balance, Add entry and four shortcuts',
    _WidgetKind.quick => 'Categories with a Ponpon header',
  };
  String get launcherName => switch (this) {
    _WidgetKind.compact => 'Quick entry (2 × 2)',
    _WidgetKind.balance => 'Balance (2 × 2)',
    _WidgetKind.kinds => 'Income & expense (2 × 2)',
    _WidgetKind.wallets => 'Wallet overview (4 × 4)',
    _WidgetKind.wide => 'Balance & categories (4 × 2)',
    _WidgetKind.quick => 'Quick entry',
  };
}

class WidgetsPage extends StatefulWidget {
  const WidgetsPage({super.key, required this.app});
  final AppController app;
  @override
  State<WidgetsPage> createState() => _WidgetsPageState();
}

class _WidgetsPageState extends State<WidgetsPage> {
  String? error;

  Future<void> pinWidget(_WidgetKind kind) async {
    try {
      final requested =
          await widget.app.bridge?.pinWidget(
            compact: kind == _WidgetKind.compact,
            balance: kind == _WidgetKind.balance,
            incomeExpense: kind == _WidgetKind.kinds,
            walletOverview: kind == _WidgetKind.wallets,
            wideBalance: kind == _WidgetKind.wide,
          ) ??
          false;
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(requested ? 'Add Ponpon' : 'Add from your home screen'),
          content: Text(
            requested
                ? 'Confirm the ${kind.launcherName} widget in your launcher. ${kind == _WidgetKind.wide
                      ? 'Category buttons open drafts and still require a wallet save.'
                      : kind == _WidgetKind.kinds
                      ? 'Each button opens a draft; choose a wallet when saving.'
                      : kind == _WidgetKind.compact || kind == _WidgetKind.quick
                      ? 'It shows categories only.'
                      : 'Tracked amounts follow Show balance on widget.'} Your launcher controls the final grid size.'
                : 'Long-press an empty area on your home screen, choose Widgets, then Ponpon · ${kind.launcherName}. Your launcher controls the final grid size. You can also long-press the app icon for Quick add.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
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
        'Widgets',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Your home screen',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Preview each layout, then add the one you want. The launcher sets its final size.',
              style: textStyle(context, size: 14, color: p.secondary),
            ),
            const SizedBox(height: 20),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  GroupRow(
                    'Show balance on widget',
                    subtitle: 'Tracked amounts on your home screen.',
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
                    'Quick categories',
                    subtitle: 'Choose up to four for widgets and Today.',
                    icon: CupertinoIcons.square_grid_2x2,
                    onTap: () =>
                        pushPocket<void>(context, CategoriesPage(app: app)),
                    last: true,
                  ),
                ],
              ),
            ),
            ErrorLine(error ?? app.storageError),
            const SizedBox(height: 24),
            Text(
              'Choose a widget',
              style: textStyle(context, size: 17, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final kind in _WidgetKind.values) ...[
              _WidgetGalleryCard(
                kind: kind,
                ledger: app.ledger,
                onAdd: () => pinWidget(kind),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Previews use your selected theme and balance visibility. Tapping a category on your home screen opens a draft; nothing is saved until you choose a wallet.',
              style: textStyle(context, size: 12, color: p.secondary),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}

class _WidgetGalleryCard extends StatelessWidget {
  const _WidgetGalleryCard({
    required this.kind,
    required this.ledger,
    required this.onAdd,
  });
  final _WidgetKind kind;
  final Ledger ledger;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kind.title,
            style: textStyle(context, size: 17, weight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            '${kind.size} · ${kind.detail}',
            style: textStyle(context, size: 13, color: p.secondary),
          ),
          const SizedBox(height: 16),
          _WidgetGalleryPreview(kind: kind, ledger: ledger),
          const SizedBox(height: 16),
          Press(
            label: 'Add ${kind.title}',
            onPressed: onAdd,
            color: p.tint,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.add, color: p.accent, size: 18),
                const SizedBox(width: 7),
                Text(
                  'Add widget',
                  style: textStyle(
                    context,
                    size: 14,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetGalleryPreview extends StatelessWidget {
  const _WidgetGalleryPreview({required this.kind, required this.ledger});
  final _WidgetKind kind;
  final Ledger ledger;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final limit = switch (kind) {
        _WidgetKind.wide => 420.0,
        _WidgetKind.wallets => 300.0,
        _ => 228.0,
      };
      final width = constraints.maxWidth < limit ? constraints.maxWidth : limit;
      final height = switch (kind) {
        _WidgetKind.wide => width / 1.85,
        _WidgetKind.wallets => width,
        _ => width,
      };
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: kind == _WidgetKind.wide
              ? WideWidgetPreview(ledger: ledger, height: height)
              : _WidgetFrame(kind: kind, ledger: ledger),
        ),
      );
    },
  );
}

class _WidgetFrame extends StatelessWidget {
  const _WidgetFrame({required this.kind, required this.ledger});
  final _WidgetKind kind;
  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final wallets = ledger.availableWallets;
    final visible = ledger.preferences.balanceWidgetVisible;
    final amount = wallets.isEmpty
        ? '—'
        : visible
        ? money(ledger.activeWalletBalance)
        : '••••';
    final content = switch (kind) {
      _WidgetKind.compact => _categoryGrid(context, ledger.quickCategories),
      _WidgetKind.quick => Column(
        children: [
          Row(
            children: [
              Text(
                'Ponpon',
                style: textStyle(context, size: 16, weight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'Tap a category',
                style: textStyle(context, size: 11, color: p.secondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _categoryGrid(context, ledger.quickCategories)),
        ],
      ),
      _WidgetKind.balance => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tracked balance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle(context, size: 11, color: p.secondary),
              ),
              const SizedBox(width: 4),
              _previewEye(context, visible, bare: true),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  amount,
                  style: textStyle(
                    context,
                    size: 26,
                    weight: FontWeight.w700,
                    tabular: true,
                    color: visible && ledger.activeWalletBalance < 0
                        ? p.danger
                        : p.ink,
                  ),
                ),
              ),
            ),
          ),
          Text(
            wallets.isEmpty
                ? 'No active wallets'
                : visible
                ? '${wallets.length} active ${wallets.length == 1 ? 'wallet' : 'wallets'}'
                : 'Amount hidden',
            style: textStyle(context, size: 10, color: p.secondary),
          ),
          const SizedBox(height: 5),
          _previewChip(context, '↙  Add entry'),
        ],
      ),
      _WidgetKind.kinds => Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick add',
              style: textStyle(context, size: 14, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 7),
          Expanded(child: _previewChip(context, '−  Expense')),
          const SizedBox(height: 7),
          Expanded(child: _previewChip(context, '+  Income')),
        ],
      ),
      _WidgetKind.wallets => _walletPreview(context, ledger, visible, amount),
      _ => const SizedBox.shrink(),
    };
    return Container(
      padding: EdgeInsets.all(kind == _WidgetKind.wallets ? 12 : 8),
      decoration: BoxDecoration(
        color: p.style == VisualStyle.original && p.dark
            ? p.surface
            : p.background,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(p.cardRadius),
      ),
      child: content,
    );
  }

  Widget _categoryGrid(BuildContext context, List<Category> categories) {
    final selected = categories.take(4).toList();
    if (selected.isEmpty) {
      return Center(
        child: Text(
          'Quick add',
          style: textStyle(context, size: 15, weight: FontWeight.w700),
        ),
      );
    }
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row * 2 + col < selected.length
                        ? _categoryTile(context, selected[row * 2 + col])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _categoryTile(BuildContext context, Category category) {
    final p = Palette.of(context);
    final color = categoryColor(context, category.icon);
    return Container(
      decoration: BoxDecoration(
        color: p.tint,
        borderRadius: BorderRadius.circular(p.controlRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(categoryIcon(category.icon), color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle(
              context,
              size: 12,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewChip(BuildContext context, String label) {
    final p = Palette.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.tint,
        borderRadius: BorderRadius.circular(p.controlRadius),
      ),
      child: Text(
        label,
        style: textStyle(
          context,
          size: 13,
          weight: FontWeight.w700,
          color: p.accent,
        ),
      ),
    );
  }

  Widget _previewEye(BuildContext context, bool visible, {bool bare = false}) {
    final p = Palette.of(context);
    return Semantics(
      label: visible ? 'Hide balance' : 'Show balance',
      child: Container(
        width: 48,
        height: 48,
        alignment: bare ? Alignment.centerLeft : Alignment.center,
        decoration: bare
            ? null
            : BoxDecoration(
                color: p.tint,
                borderRadius: BorderRadius.circular(p.controlRadius),
              ),
        child: Icon(
          visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          size: 20,
          color: p.secondary,
        ),
      ),
    );
  }

  Widget _walletPreview(
    BuildContext context,
    Ledger ledger,
    bool visible,
    String total,
  ) {
    final p = Palette.of(context);
    final wallets = [
      ...ledger.availableWallets.where((w) => ledger.calculate(w).balance != 0),
      ...ledger.availableWallets.where((w) => ledger.calculate(w).balance == 0),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Wallet overview',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle(context, size: 14, weight: FontWeight.w700),
              ),
            ),
            _previewEye(context, visible),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            total,
            style: textStyle(
              context,
              size: 22,
              weight: FontWeight.w700,
              tabular: true,
            ),
          ),
        ),
        Text(
          wallets.isEmpty
              ? 'No active wallets'
              : visible
              ? '${wallets.length} active wallets · manual records'
              : 'Amounts hidden in Settings',
          style: textStyle(context, size: 10, color: p.secondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: wallets.isEmpty
              ? Center(
                  child: Text(
                    'No active wallets',
                    style: textStyle(context, size: 13, color: p.secondary),
                  ),
                )
              : Column(
                  children: [
                    for (final wallet in wallets.take(3)) ...[
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: p.tint,
                            borderRadius: BorderRadius.circular(
                              p.controlRadius,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  wallet.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textStyle(context, size: 12),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                visible
                                    ? money(ledger.calculate(wallet).balance)
                                    : '••••',
                                style: textStyle(
                                  context,
                                  size: 12,
                                  color:
                                      visible &&
                                          ledger.calculate(wallet).balance < 0
                                      ? p.danger
                                      : p.secondary,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        if (wallets.length > 3)
          Text(
            '+${wallets.length - 3} more in Ponpon',
            style: textStyle(context, size: 10, color: p.secondary),
          ),
      ],
    );
  }
}
