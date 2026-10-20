import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../domain/ledger.dart';
import 'design.dart';
import 'screens.dart' show DirectEntryButtonsPage, WalletsPage;

class EntryPage extends StatefulWidget {
  const EntryPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  AppController get app => widget.controller;
  Draft get draft => app.draft!;
  List<Wallet> get selectableWallets {
    final old = app.ledger.entry(draft.editingId ?? '');
    return [
      ...app.ledger.availableWallets,
      if (old != null)
        for (final w in app.ledger.wallets.where(
          (w) => w.archived && (w == old.wallet || w == old.toWallet),
        ))
          w,
    ];
  }

  bool submitting = false;
  final selectedCategoryKey = GlobalKey();
  void showSelectedCategory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = selectedCategoryKey.currentContext;
      if (mounted && context != null) {
        // Reveal the selected chip only within its horizontal category strip.
        // Scrolling ancestor pages would move the landscape header off screen.
        Scrollable.of(context).position.ensureVisible(
          context.findRenderObject()!,
          duration: Duration.zero,
          alignment: .5,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    app.entryVisible = true;
    showSelectedCategory();
  }

  @override
  void dispose() {
    app.entryVisible = false;
    super.dispose();
  }

  void change(VoidCallback update) {
    if (app.busy || submitting || app.draft == null) return;
    setState(() {
      update();
      app.storageError = null;
    });
    app.updateDraft();
    showSelectedCategory();
  }

  void digit(String key) {
    change(() {
      if (key == '⌫') {
        if (draft.amount.isNotEmpty) {
          draft.amount = draft.amount.substring(0, draft.amount.length - 1);
        }
      } else if (key == '.') {
        if (!draft.amount.contains('.')) {
          draft.amount = '${draft.amount.isEmpty ? '0' : draft.amount}.';
        }
      } else {
        final parts = draft.amount.split('.');
        if (parts.length == 2 && parts[1].length >= 2 ||
            parts.length == 1 && parts[0].length >= 9) {
          return;
        }
        draft.amount = draft.amount == '0' ? key : '${draft.amount}$key';
      }
    });
    if (app.ledger.preferences.haptics) HapticFeedback.selectionClick();
  }

  Future<void> save(Wallet wallet) async {
    if (submitting || app.busy) return;
    setState(() => submitting = true);
    final result = await app.saveDraft(wallet);
    if (!mounted) return;
    if (result) {
      Navigator.of(context).pop();
    } else {
      setState(() => submitting = false);
    }
  }

  Future<void> chooseDate() async {
    var date = localDay(draft.date);
    final now = app.clock();
    await showPocketSheet<void>(
      context: context,
      builder: (ctx) => SheetFrame(
        title: 'Entry date',
        height: 350,
        action: Press(
          onPressed: () {
            change(() => draft.date = dayKey(date));
            Navigator.pop(ctx);
          },
          child: Text(
            'Done',
            style: textStyle(
              ctx,
              color: Palette.of(ctx).accent,
              weight: FontWeight.w600,
            ),
          ),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: date.isAfter(now) ? now : date,
          minimumDate: DateTime(1900),
          maximumDate: DateTime(now.year, now.month, now.day, 23, 59),
          onDateTimeChanged: (value) => date = value,
        ),
      ),
    );
  }

  Future<void> chooseCategory() async {
    final categories = app.ledger.categoriesFor(draft.kind);
    final chosen = await showPocketSheet<String>(
      context: context,
      builder: (ctx) => SheetFrame(
        title: 'Choose a category',
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < categories.length; i++)
                    Builder(
                      builder: (ctx) {
                        final c = categories[i];
                        return GroupRow(
                          c.name,
                          icon: categoryIcon(c.icon),
                          last: i == categories.length - 1,
                          trailing: c.id == draft.categoryId
                              ? Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: Palette.of(ctx).accent,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, c.id),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) change(() => draft.categoryId = chosen);
  }

  Future<void> note() async {
    final original = draft.note;
    final result = await textPrompt(
      context,
      title: 'A note, if you need it',
      value: original,
      hint: 'What was this for?',
      maxLength: 500,
      onChanged: (value) => change(() => draft.note = value),
    );
    if (mounted && app.draft != null) {
      change(() => draft.note = result?.trim() ?? original);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      if (app.draft == null) {
        return CupertinoPageScaffold(
          child: Center(
            child: CupertinoActivityIndicator(
              color: Palette.of(context).accent,
            ),
          ),
        );
      }
      final p = Palette.of(context);
      final isTransfer = draft.kind == EntryKind.transfer;
      final categories = app.ledger.categoriesFor(draft.kind);
      final quickCategories = categories
          .take(draft.kind == EntryKind.income ? 5 : 4)
          .toList();
      final chosen = categories
          .where((c) => c.id == draft.categoryId)
          .firstOrNull;
      if (chosen != null && !quickCategories.any((c) => c.id == chosen.id)) {
        if (quickCategories.length == 4) quickCategories.removeLast();
        quickCategories.add(chosen);
      }
      final isToday = draft.date == dayKey(app.clock());
      return CupertinoPageScaffold(
        backgroundColor: p.background,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    MediaQuery.sizeOf(context).width >
                        MediaQuery.sizeOf(context).height
                    ? 920
                    : 520,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final small =
                      constraints.maxHeight < 680 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.25;
                  final compactKeypad =
                      small ||
                      (!isTransfer && app.ledger.quickWallets.length == 4);
                  final landscape =
                      constraints.maxHeight < 480 &&
                      constraints.maxWidth >= 620;
                  final content = Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 16, 0),
                        child: Row(
                          children: [
                            Press(
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.pop(context),
                              label: 'Close entry, keep unfinished amount',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Icon(
                                CupertinoIcons.xmark_circle_fill,
                                color: p.secondary,
                                size: 27,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                draft.editingId == null
                                    ? 'New entry'
                                    : 'Edit entry',
                                textAlign: TextAlign.center,
                                style: textStyle(
                                  context,
                                  size: 17,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Press(
                              label: draft.note.isEmpty
                                  ? 'Add a note'
                                  : 'Edit note',
                              onPressed: app.busy ? null : note,
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                CupertinoIcons.pencil,
                                size: 21,
                                color: p.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: CupertinoSlidingSegmentedControl<EntryKind>(
                            groupValue: draft.kind,
                            backgroundColor: p.line.withValues(alpha: .55),
                            thumbColor: p.surface,
                            padding: const EdgeInsets.all(4),
                            onValueChanged: (value) {
                              if (!submitting && !app.busy && value != null) {
                                change(() {
                                  app.changeDraftKind(value);
                                });
                              }
                            },
                            disabledChildren:
                                app.ledger
                                        .entry(draft.editingId ?? '')
                                        ?.billId !=
                                    null
                                ? {EntryKind.income, EntryKind.transfer}
                                : const {},
                            children: {
                              for (final kind in EntryKind.values)
                                kind: SegmentLabel(switch (kind) {
                                  EntryKind.expense => 'Expense',
                                  EntryKind.income => 'Income',
                                  EntryKind.transfer => 'Transfer',
                                }, key: ValueKey('entry-kind-${kind.name}')),
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, amountBounds) => SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: amountBounds.maxHeight,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 8),
                                  Semantics(
                                    label:
                                        'Amount in Philippine pesos, ${draft.amount.isEmpty ? 'zero' : draft.amount}',
                                    liveRegion: true,
                                    child: ExcludeSemantics(
                                      child: SizedBox(
                                        height: small
                                            ? (amountBounds.maxHeight - 58)
                                                  .clamp(24.0, 58.0)
                                            : 96,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            FittedBox(
                                              child: Text(
                                                '₱',
                                                style: textStyle(
                                                  context,
                                                  size: 29,
                                                  weight: FontWeight.w500,
                                                  color: p.secondary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  draft.amount.isEmpty
                                                      ? '0'
                                                      : draft.amount,
                                                  style: textStyle(
                                                    context,
                                                    size: small ? 54 : 72,
                                                    weight: FontWeight.w500,
                                                    tabular: true,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Press(
                                        key: const ValueKey('entry-date'),
                                        onPressed: app.busy ? null : chooseDate,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        label:
                                            'Edit date, ${shortDate(draft.date)}',
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              CupertinoIcons.calendar,
                                              size: 16,
                                              color: p.secondary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${isToday ? 'Today, ' : ''}${shortDate(draft.date)}',
                                              style: textStyle(
                                                context,
                                                size: 13,
                                                color: p.secondary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              CupertinoIcons.chevron_down,
                                              size: 11,
                                              color: p.secondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (!small)
                                    Press(
                                      onPressed: app.busy ? null : note,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            CupertinoIcons.pencil,
                                            color: p.secondary,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              draft.note.isEmpty
                                                  ? 'Add a note'
                                                  : draft.note,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: textStyle(
                                                context,
                                                size: 13,
                                                color: p.secondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ErrorLine(app.storageError ?? app.draftError),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 4,
                        ),
                        child: isTransfer
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Press(
                                      key: const ValueKey('transfer-from'),
                                      color: p.surface,
                                      label:
                                          'Transfer from ${app.ledger.wallet(draft.from)?.label ?? "Choose wallet"}',
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      onPressed: app.busy
                                          ? null
                                          : () async {
                                              final w = await chooseWallet(
                                                context,
                                                selectableWallets,
                                                title: 'Transfer from',
                                              );
                                              if (w != null && mounted) {
                                                change(() => draft.from = w);
                                              }
                                            },
                                      child: Text(
                                        app.ledger.wallet(draft.from)?.label ??
                                            'From',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyle(context, size: 14),
                                      ),
                                    ),
                                  ),
                                  Press(
                                    label: 'Reverse transfer direction',
                                    padding: const EdgeInsets.all(8),
                                    onPressed: app.busy
                                        ? null
                                        : () => change(() {
                                            final from = draft.from;
                                            draft.from = draft.to;
                                            draft.to = from;
                                          }),
                                    child: Icon(
                                      CupertinoIcons.arrow_right_arrow_left,
                                      color: p.accent,
                                      size: 20,
                                    ),
                                  ),
                                  Expanded(
                                    child: Press(
                                      key: const ValueKey('transfer-to'),
                                      color: p.surface,
                                      label:
                                          'Transfer to ${app.ledger.wallet(draft.to)?.label ?? "Choose wallet"}',
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      onPressed: app.busy
                                          ? null
                                          : () async {
                                              final w = await chooseWallet(
                                                context,
                                                selectableWallets,
                                                title: 'Transfer to',
                                              );
                                              if (w != null && mounted) {
                                                change(() => draft.to = w);
                                              }
                                            },
                                      child: Text(
                                        app.ledger.wallet(draft.to)?.label ??
                                            'To',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyle(context, size: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: quickCategories
                                            .map(
                                              (c) => Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: Press(
                                                  key: c.id == draft.categoryId
                                                      ? selectedCategoryKey
                                                      : null,
                                                  onPressed: app.busy
                                                      ? null
                                                      : () => change(
                                                          () =>
                                                              draft.categoryId =
                                                                  c.id,
                                                        ),
                                                  color:
                                                      c.id == draft.categoryId
                                                      ? categoryColor(
                                                          context,
                                                          c.icon,
                                                        ).withValues(alpha: .14)
                                                      : p.surface,
                                                  label:
                                                      '${c.name} category${c.id == draft.categoryId ? ', selected' : ''}',
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 12,
                                                      ),
                                                  radius: 14,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        categoryIcon(c.icon),
                                                        size: 18,
                                                        color: categoryColor(
                                                          context,
                                                          c.icon,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        c.name,
                                                        style: textStyle(
                                                          context,
                                                          size: 13,
                                                          weight:
                                                              FontWeight.w600,
                                                          color: categoryColor(
                                                            context,
                                                            c.icon,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ),
                                  Press(
                                    label: 'All categories',
                                    onPressed: app.busy ? null : chooseCategory,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 12,
                                    ),
                                    child: Icon(
                                      CupertinoIcons.ellipsis,
                                      color: p.accent,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          compactKeypad ? 2 : 4,
                          24,
                          compactKeypad ? 6 : 8,
                        ),
                        child: Column(
                          children: [
                            for (final row in const [
                              ['1', '2', '3'],
                              ['4', '5', '6'],
                              ['7', '8', '9'],
                              ['.', '0', '⌫'],
                            ])
                              Row(
                                children: row
                                    .map(
                                      (key) => Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.all(
                                            compactKeypad ? 3 : 4,
                                          ),
                                          child: Press(
                                            key: ValueKey('key-$key'),
                                            onPressed: submitting || app.busy
                                                ? null
                                                : () => digit(key),
                                            padding: EdgeInsets.symmetric(
                                              vertical: compactKeypad ? 0 : 12,
                                            ),
                                            radius: 18,
                                            color: p.surface,
                                            label: key == '⌫'
                                                ? 'Delete last digit'
                                                : key == '.'
                                                ? 'Decimal point'
                                                : 'Digit $key',
                                            child: key == '⌫'
                                                ? Icon(
                                                    CupertinoIcons.delete_left,
                                                    size: 24,
                                                    color: p.ink,
                                                  )
                                                : Text(
                                                    key,
                                                    style: textStyle(
                                                      context,
                                                      size: compactKeypad
                                                          ? 24
                                                          : 30,
                                                      weight: FontWeight.w400,
                                                      tabular: true,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                        child: isTransfer && selectableWallets.length < 2
                            ? PrimaryButton(
                                'Add or restore wallets',
                                onPressed: app.busy
                                    ? null
                                    : () => pushPocket<void>(
                                        context,
                                        WalletsPage(app: app),
                                      ),
                              )
                            : isTransfer
                            ? PrimaryButton(
                                'Record ${app.ledger.wallet(draft.from)?.label ?? "From"} → ${app.ledger.wallet(draft.to)?.label ?? "To"}',
                                icon: CupertinoIcons.arrow_right_arrow_left,
                                onPressed: submitting || app.busy
                                    ? null
                                    : () => save(draft.from),
                              )
                            : _DirectWalletActions(
                                key: ValueKey(
                                  app.ledger.preferences.quickWallets.join(','),
                                ),
                                app: app,
                                kind: draft.kind,
                                compact: small,
                                landscape: landscape,
                                wallets: selectableWallets,
                                disabled: submitting || app.busy,
                                onSave: save,
                              ),
                      ),
                    ],
                  );
                  if (constraints.maxHeight < 480 &&
                      constraints.maxWidth >= 620) {
                    // Two working columns keep typing and final wallet actions
                    // in the first landscape viewport, with full touch targets.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            children: content.children.take(4).toList(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Container(width: .5, color: p.line),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: content.children.skip(4).toList(),
                          ),
                        ),
                      ],
                    );
                  }
                  final enlarged =
                      MediaQuery.textScalerOf(context).scale(1) > 1.25;
                  final needsScroll =
                      constraints.maxHeight < 480 ||
                      constraints.maxHeight < 640 &&
                          (enlarged ||
                              app.ledger.quickWallets.length > 2 ||
                              app.ledger.quickWallets.any(
                                (w) => w.label.length > 18,
                              ));
                  return needsScroll
                      ? SingleChildScrollView(
                          child: SizedBox(
                            height: enlarged ? 700 : 680,
                            child: content,
                          ),
                        )
                      : content;
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SaveWallet extends StatelessWidget {
  const _SaveWallet({
    required this.wallet,
    required this.kind,
    required this.showIcon,
    required this.compact,
    this.navigationHint,
    this.onPressed,
  });
  final Wallet wallet;
  final EntryKind kind;
  final bool showIcon, compact;
  final String? navigationHint;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final foreground = p.dark ? p.background : const Color(0xFFFFFFFF);
    return Press(
      key: ValueKey('save-${wallet.name}'),
      label: '${entryAction(kind)} ${wallet.label}',
      color: walletColor(context, wallet),
      onPressed: onPressed,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 12),
      radius: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            navigationHint ?? entryAction(kind),
            style: textStyle(
              context,
              size: 12,
              weight: FontWeight.w500,
              color: foreground,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showIcon) ...[
                Icon(walletIcon(wallet.icon), color: foreground, size: 19),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  wallet.label,
                  textAlign: TextAlign.center,
                  style: textStyle(
                    context,
                    size: 17,
                    weight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DirectWalletActions extends StatefulWidget {
  const _DirectWalletActions({
    super.key,
    required this.app,
    required this.kind,
    required this.compact,
    required this.landscape,
    required this.wallets,
    required this.disabled,
    required this.onSave,
  });
  final AppController app;
  final EntryKind kind;
  final bool compact, landscape;
  final List<Wallet> wallets;
  final bool disabled;
  final Future<void> Function(Wallet) onSave;
  @override
  State<_DirectWalletActions> createState() => _DirectWalletActionsState();
}

class _DirectWalletActionsState extends State<_DirectWalletActions> {
  final rail = ScrollController();
  int first = 0;
  bool atStart = true, atEnd = false;
  double extent = 1;
  int step = 1;
  @override
  void dispose() {
    rail.dispose();
    super.dispose();
  }

  Future<void> picker() async {
    final selected = await chooseWallet(
      context,
      widget.wallets,
      title: entryAction(widget.kind),
      manageButtons: () {
        if (mounted) {
          pushPocket<void>(context, DirectEntryButtonsPage(app: widget.app));
        }
      },
    );
    if (selected != null && mounted) await widget.onSave(selected);
  }

  double labelHeight(Wallet wallet, double width, bool icon) {
    final painter = TextPainter(
      text: TextSpan(
        text: wallet.label,
        style: textStyle(context, size: 17, weight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    painter.layout(
      maxWidth: (width - 24 - (icon ? 26 : 0)).clamp(1, double.infinity),
    );
    final height = painter.height;
    painter.dispose();
    return height;
  }

  bool namesFit(
    List<Wallet> wallets,
    double width,
    bool icon, {
    int lines = 1,
  }) {
    final line = MediaQuery.textScalerOf(context).scale(17) * 1.3;
    return wallets.every(
      (wallet) => labelHeight(wallet, width, icon) <= line * lines + .1,
    );
  }

  void move(bool forward) {
    if (!rail.hasClients || widget.disabled) return;
    final target = (rail.offset + (forward ? 1 : -1) * extent * step).clamp(
      0.0,
      rail.position.maxScrollExtent,
    );
    if (MotionScope.of(context)) {
      rail.jumpTo(target);
    } else {
      rail.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = widget.app.ledger.quickWallets, p = Palette.of(context);
    if (widget.wallets.isEmpty) {
      return PrimaryButton(
        'Add or restore a wallet',
        icon: CupertinoIcons.add,
        onPressed: widget.disabled
            ? null
            : () => pushPocket<void>(context, WalletsPage(app: widget.app)),
      );
    }
    if (wallets.isEmpty) {
      return PrimaryButton(
        key: const ValueKey('choose-save-wallet'),
        'Choose wallet to save',
        icon: CupertinoIcons.square_grid_2x2,
        onPressed: widget.disabled ? null : picker,
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        const gap = 10.0;
        final width = bounds.maxWidth - (widget.landscape ? 56 : 0);
        final large = MediaQuery.textScalerOf(context).scale(1) > 1.25;
        final columns = wallets.length <= 3 ? wallets.length : 2;
        final slotWidth = (width - gap * (columns - 1)) / columns;
        final inlineIcon = columns < 3 && !large;
        final inline =
            wallets.length <= 3 &&
            namesFit(
              wallets,
              slotWidth,
              inlineIcon,
              lines: wallets.length < 3 ? 2 : 1,
            );
        final grid =
            wallets.length == 4 &&
            !widget.compact &&
            namesFit(wallets, slotWidth, inlineIcon, lines: 2);
        final scrolling = !inline && !grid;
        final preferred = (large ? 220.0 : 176.0).clamp(0.0, width);
        final railWidth = namesFit(wallets, preferred, !large, lines: 2)
            ? preferred
            : width;
        final cardWidth = scrolling ? railWidth : slotWidth;
        final icon = scrolling ? !large : inlineIcon;
        final nameHeight = wallets
            .map((w) => labelHeight(w, cardWidth, icon))
            .reduce((a, b) => a > b ? a : b);
        final buttonHeight =
            (MediaQuery.textScalerOf(context).scale(12) * 1.3 +
                    4 +
                    nameHeight +
                    (widget.compact ? 12 : 24))
                .clamp(68.0, double.infinity)
                .ceilToDouble();
        extent = cardWidth + gap;
        step = (width / extent).floor().clamp(1, wallets.length);
        Widget action(Wallet wallet) => SizedBox(
          width: cardWidth,
          height: buttonHeight,
          child: _SaveWallet(
            wallet: wallet,
            kind: widget.kind,
            showIcon: icon,
            compact: widget.compact,
            navigationHint: widget.landscape && scrolling
                ? '${entryAction(widget.kind)} · Swipe ${wallets.indexOf(wallet) + 1} of ${wallets.length}'
                : null,
            onPressed: widget.disabled ? null : () => widget.onSave(wallet),
          ),
        );
        Widget row(Iterable<Wallet> items) => Row(
          children: [
            for (final indexed in items.indexed) ...[
              if (indexed.$1 > 0) const SizedBox(width: gap),
              action(indexed.$2),
            ],
          ],
        );
        final buttons = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (scrolling)
              SizedBox(
                height: buttonHeight,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (event) {
                    if (event.metrics.axis == Axis.horizontal) {
                      final value = (event.metrics.pixels / extent)
                          .floor()
                          .clamp(0, wallets.length - 1);
                      final start = event.metrics.extentBefore <= .5;
                      final end = event.metrics.extentAfter <= .5;
                      if (value != first || start != atStart || end != atEnd) {
                        setState(() {
                          first = value;
                          atStart = start;
                          atEnd = end;
                        });
                      }
                    }
                    return false;
                  },
                  child: ListView.separated(
                    key: const ValueKey('direct-wallet-pages'),
                    controller: rail,
                    scrollDirection: Axis.horizontal,
                    itemCount: wallets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: gap),
                    itemBuilder: (_, index) => action(wallets[index]),
                  ),
                ),
              )
            else if (grid)
              Column(
                children: [
                  row(wallets.take(2)),
                  const SizedBox(height: gap),
                  row(wallets.skip(2)),
                ],
              )
            else
              row(wallets),
          ],
        );
        if (widget.landscape) {
          return Row(
            children: [
              SizedBox(width: width, child: buttons),
              const SizedBox(width: 8),
              Press(
                key: const ValueKey('more-wallets'),
                label: 'All wallets and direct entry buttons',
                onPressed: widget.disabled ? null : picker,
                padding: const EdgeInsets.all(12),
                child: Icon(
                  CupertinoIcons.square_grid_2x2,
                  color: p.accent,
                  size: 22,
                ),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buttons,
            Row(
              children: [
                Press(
                  key: const ValueKey('more-wallets'),
                  label: 'All wallets and direct entry buttons',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 8,
                  ),
                  onPressed: widget.disabled ? null : picker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.square_grid_2x2,
                        color: p.accent,
                        size: 16,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'All wallets',
                        style: textStyle(
                          context,
                          size: 13,
                          weight: FontWeight.w600,
                          color: p.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (scrolling) ...[
                  Text(
                    '${first + 1}/${wallets.length}',
                    style: textStyle(
                      context,
                      size: 11,
                      color: p.secondary,
                      tabular: true,
                    ),
                  ),
                  Press(
                    key: const ValueKey('previous-direct-wallets'),
                    label: 'Previous direct entry wallets',
                    onPressed: widget.disabled || atStart
                        ? null
                        : () => move(false),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      size: 18,
                      color: widget.disabled || atStart
                          ? p.secondary.withValues(alpha: .45)
                          : p.accent,
                    ),
                  ),
                  Press(
                    key: const ValueKey('next-direct-wallets'),
                    label: 'Next direct entry wallets',
                    onPressed: widget.disabled || atEnd
                        ? null
                        : () => move(true),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                      color: widget.disabled || atEnd
                          ? p.secondary.withValues(alpha: .45)
                          : p.accent,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
