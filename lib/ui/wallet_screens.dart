part of 'screens.dart';

class WalletEditorPage extends StatefulWidget {
  const WalletEditorPage({super.key, required this.app, this.wallet});
  final AppController app;
  final Wallet? wallet;
  @override
  State<WalletEditorPage> createState() => _WalletEditorState();
}

class _WalletEditorState extends State<WalletEditorPage> {
  late final String id = widget.wallet?.id ?? newId();
  late final TextEditingController name = TextEditingController(
    text: widget.wallet?.label ?? '',
  );
  late String icon = widget.wallet?.icon ?? 'wallet',
      color = widget.wallet?.color ?? 'plum';
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final value = Wallet(
      id: id,
      label: name.text.trim(),
      icon: icon,
      color: color,
      archived:
          widget.app.ledger.wallet(Wallet.reference(id))?.archived ?? false,
      removed: widget.app.ledger.wallet(Wallet.reference(id))?.removed ?? false,
    );
    final ok = await widget.app.setWallet(value);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => error = widget.app.storageError);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final p = Palette.of(context), app = widget.app;
      final current = app.ledger.wallet(Wallet.reference(id));
      return PocketPage(
        current == null ? 'New wallet' : 'Wallet settings',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Make it yours.',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Manual records only. No bank or e-wallet connection.',
              style: textStyle(context, size: 14, color: p.secondary),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: name,
              builder: (context, value, _) => Center(
                child: Column(
                  children: [
                    IconTile(
                      walletIcon(icon),
                      color: walletColor(
                        context,
                        Wallet(id: id, label: '', color: color),
                      ),
                      size: 72,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      value.text.trim().isEmpty
                          ? 'New wallet'
                          : value.text.trim(),
                      textAlign: TextAlign.center,
                      style: textStyle(
                        context,
                        size: 21,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            CupertinoTextField(
              key: const ValueKey('wallet-name'),
              controller: name,
              maxLength: 30,
              placeholder: 'Wallet name, e.g. Maya',
              placeholderStyle: textStyle(context, color: p.secondary),
              style: textStyle(context),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 24),
            Text('Icon', style: textStyle(context, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in walletIcons)
                  Press(
                    key: ValueKey('wallet-icon-$value'),
                    label: '$value icon${icon == value ? ', selected' : ''}',
                    color: icon == value ? p.tint : p.surface,
                    onPressed: app.busy
                        ? null
                        : () => setState(() => icon = value),
                    child: Icon(walletIcon(value), color: p.accent),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Color', style: textStyle(context, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in walletColors)
                  Press(
                    label: '$value color${color == value ? ', selected' : ''}',
                    color: color == value ? p.tint : p.surface,
                    onPressed: app.busy
                        ? null
                        : () => setState(() => color = value),
                    child: Icon(
                      CupertinoIcons.circle_fill,
                      color: walletColor(
                        context,
                        Wallet(id: id, label: '', color: value),
                      ),
                      size: 24,
                    ),
                  ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 24),
              Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (!current.archived)
                      GroupRow(
                        'Direct entry buttons',
                        subtitle:
                            'Choose and arrange all your wallets together.',
                        icon: CupertinoIcons.square_grid_2x2,
                        onTap: () => pushPocket<void>(
                          context,
                          DirectEntryButtonsPage(app: app),
                        ),
                      ),
                    GroupRow(
                      current.archived ? 'Restore wallet' : 'Remove wallet',
                      subtitle: 'History, transfers and balances are kept.',
                      icon: CupertinoIcons.archivebox,
                      last: true,
                      onTap: app.busy
                          ? null
                          : () async {
                              final ok = current.archived
                                  ? await app.restoreWallet(current)
                                  : await confirmWalletRemoval(
                                      context,
                                      app,
                                      current,
                                    );
                              if (mounted) {
                                setState(
                                  () => error = ok ? null : app.storageError,
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            ErrorLine(error),
            PrimaryButton('Save wallet', onPressed: app.busy ? null : save),
          ],
        ),
      );
    },
  );
}

class DirectEntryButtonsPage extends StatefulWidget {
  const DirectEntryButtonsPage({super.key, required this.app});
  final AppController app;
  @override
  State<DirectEntryButtonsPage> createState() => _DirectEntryButtonsState();
}

class _DirectEntryButtonsState extends State<DirectEntryButtonsPage> {
  String? error;
  Future<void> update(List<String> ids) async {
    final ok = await widget.app.setQuickWallets(ids);
    if (mounted) setState(() => error = ok ? null : widget.app.storageError);
  }

  void move(String id, int offset) {
    final ids = [...widget.app.ledger.preferences.quickWallets];
    final index = ids.indexOf(id), target = ids.indexOf(id) + offset;
    if (index < 0 || target < 0 || target >= ids.length) return;
    ids.removeAt(index);
    ids.insert(target, id);
    update(ids);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final app = widget.app, p = Palette.of(context);
      final selected = app.ledger.preferences.quickWallets;
      final wallets = [
        ...app.ledger.quickWallets,
        ...app.ledger.availableWallets.where((w) => !selected.contains(w.id)),
      ];
      final archived = app.ledger.wallets.where((w) => w.archived).length;
      return PocketPage(
        'Direct buttons',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Direct entry buttons',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Choose the wallets below your keypad, in this order. You still choose a wallet every time you save.',
              style: textStyle(context, size: 14, color: p.secondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Press(
                    key: const ValueKey('select-all-wallets'),
                    color: p.tint,
                    onPressed: app.busy || selected.length == wallets.length
                        ? null
                        : () => update([
                            ...selected,
                            ...wallets
                                .where((w) => !selected.contains(w.id))
                                .map((w) => w.id),
                          ]),
                    child: Text(
                      'Select all',
                      style: textStyle(
                        context,
                        size: 15,
                        weight: FontWeight.w600,
                        color: p.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Press(
                    key: const ValueKey('clear-direct-wallets'),
                    color: p.surface,
                    onPressed: app.busy || selected.isEmpty
                        ? null
                        : () => update([]),
                    child: Text(
                      'Clear',
                      style: textStyle(
                        context,
                        size: 15,
                        weight: FontWeight.w600,
                        color: p.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              selected.isEmpty
                  ? 'No direct buttons. Choose a wallet from the entry picker.'
                  : '${selected.length} selected · changes save automatically',
              style: textStyle(context, size: 13, color: p.secondary),
            ),
            const SizedBox(height: 16),
            ErrorLine(error),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < wallets.length; i++) ...[
                    Builder(
                      builder: (context) {
                        final wallet = wallets[i],
                            index = selected.indexOf(wallets[i].id);
                        final enabled = index >= 0;
                        return Padding(
                          key: ValueKey('direct-row-${wallet.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  checked: enabled,
                                  child: Press(
                                    key: ValueKey('direct-toggle-${wallet.id}'),
                                    label:
                                        '${wallet.label}, direct entry button${enabled ? ', position ${index + 1}' : ''}',
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 12,
                                    ),
                                    onPressed: app.busy
                                        ? null
                                        : () => update(
                                            enabled
                                                ? selected
                                                      .where(
                                                        (id) => id != wallet.id,
                                                      )
                                                      .toList()
                                                : [...selected, wallet.id],
                                          ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          enabled
                                              ? CupertinoIcons
                                                    .checkmark_circle_fill
                                              : CupertinoIcons.circle,
                                          color: enabled
                                              ? p.accent
                                              : p.secondary,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        IconTile(
                                          walletIcon(wallet.icon),
                                          color: walletColor(context, wallet),
                                          size: 32,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            wallet.label,
                                            style: textStyle(
                                              context,
                                              size: 15,
                                              weight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (enabled) ...[
                                Press(
                                  key: ValueKey('direct-up-${wallet.id}'),
                                  label: 'Move ${wallet.label} earlier',
                                  padding: const EdgeInsets.all(12),
                                  onPressed: app.busy || index == 0
                                      ? null
                                      : () => move(wallet.id, -1),
                                  child: Icon(
                                    CupertinoIcons.chevron_up,
                                    size: 18,
                                    color: p.accent,
                                  ),
                                ),
                                Press(
                                  key: ValueKey('direct-down-${wallet.id}'),
                                  label: 'Move ${wallet.label} later',
                                  padding: const EdgeInsets.all(12),
                                  onPressed:
                                      app.busy || index == selected.length - 1
                                      ? null
                                      : () => move(wallet.id, 1),
                                  child: Icon(
                                    CupertinoIcons.chevron_down,
                                    size: 18,
                                    color: p.accent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    if (i < wallets.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 24),
                        child: Rule(),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'All active wallets remain available in the entry picker.${archived > 0 ? ' $archived archived ${archived == 1 ? 'wallet is' : 'wallets are'} excluded.' : ''}',
              style: textStyle(context, size: 13, color: p.secondary),
            ),
          ],
        ),
      );
    },
  );
}

Future<bool> confirmWalletRemoval(
  BuildContext context,
  AppController app,
  Wallet wallet,
) async {
  final history = app.ledger.hasWalletHistory(wallet);
  final allowance =
      app.ledger.allowance?.enabled == true &&
      app.ledger.allowance?.wallet == wallet;
  final approved = await confirm(
    context,
    title: '${history ? 'Archive' : 'Remove'} ${wallet.label}?',
    message:
        '${history ? 'Recorded history, opening balance and totals will be kept. This wallet will be hidden from new entries.' : 'This unused wallet will be removed from active choices.'} Restore it anytime in Hidden wallets.${allowance ? ' Its allowance schedule will be paused. No money will be rerouted; restoring the wallet will not restart the schedule.' : ''}',
    action: allowance
        ? 'Pause allowance and archive'
        : history
        ? 'Archive wallet'
        : 'Remove wallet',
    destructive: true,
  );
  if (!approved || !context.mounted) return false;
  return app.removeWallet(wallet, pauseAllowance: allowance);
}

class HiddenWalletsPage extends StatelessWidget {
  const HiddenWalletsPage({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final wallets = app.ledger.wallets.where((w) => w.archived).toList();
      return PocketPage(
        'Hidden wallets',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Restore anytime.',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Restoring keeps the same wallet and history. Direct buttons and allowance schedules stay as you left them.',
              style: textStyle(
                context,
                size: 14,
                color: Palette.of(context).secondary,
              ),
            ),
            const SizedBox(height: 24),
            if (wallets.isEmpty)
              const QuietMessage(
                'No hidden wallets',
                'Wallets you archive or remove appear here.',
              ),
            if (wallets.isNotEmpty)
              Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < wallets.length; i++)
                      GroupRow(
                        wallets[i].label,
                        subtitle: wallets[i].removed
                            ? 'Removed · unused wallet'
                            : 'Archived · history and totals kept',
                        icon: walletIcon(wallets[i].icon),
                        last: i == wallets.length - 1,
                        trailing: Press(
                          key: ValueKey('restore-wallet-${wallets[i].id}'),
                          label: 'Restore ${wallets[i].label}',
                          onPressed: app.busy
                              ? null
                              : () => app.restoreWallet(wallets[i]),
                          child: Text(
                            'Restore',
                            style: textStyle(
                              context,
                              size: 14,
                              color: Palette.of(context).accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            ErrorLine(app.storageError),
          ],
        ),
      );
    },
  );
}
