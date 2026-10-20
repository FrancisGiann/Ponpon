import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';

import '../domain/ledger.dart';

class Palette {
  const Palette(this.dark);
  final bool dark;
  static Palette of(BuildContext context) =>
      Palette(CupertinoTheme.of(context).brightness == Brightness.dark);
  Color get background =>
      dark ? const Color(0xFF151416) : const Color(0xFFF6F4F1);
  Color get surface => dark ? const Color(0xFF232125) : const Color(0xFFFFFFFF);
  Color get ink => dark ? const Color(0xFFF7F3F1) : const Color(0xFF27212A);
  Color get secondary =>
      dark ? const Color(0xFFBBB3BD) : const Color(0xFF6A606F);
  Color get line => dark ? const Color(0xFF3F3943) : const Color(0xFFE5DFE7);
  Color get accent => dark ? const Color(0xFFE9CCE6) : const Color(0xFF5B315D);
  Color get onAccent =>
      dark ? const Color(0xFF322235) : const Color(0xFFFFFFFF);
  Color get tint => dark ? const Color(0xFF382E3C) : const Color(0xFFF0E8F1);
  Color get green => dark ? const Color(0xFFADE2C8) : const Color(0xFF246D53);
  Color get greenTint =>
      dark ? const Color(0xFF263C33) : const Color(0xFFE8F3EC);
  Color get blue => dark ? const Color(0xFFBBD7FF) : const Color(0xFF285B8C);
  Color get blueTint =>
      dark ? const Color(0xFF29374C) : const Color(0xFFEAF1FA);
  Color get danger => dark ? const Color(0xFFFFBAB3) : const Color(0xFFAA3429);
  Color get amber => dark ? const Color(0xFFEFCF9C) : const Color(0xFF84551C);
}

class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.reduced, required super.child});
  final bool reduced;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.reduced ??
      false;
  @override
  bool updateShouldNotify(MotionScope oldWidget) =>
      reduced != oldWidget.reduced;
}

/// Keep every segment's own hit and semantics bounds accessible.
class SegmentLabel extends StatelessWidget {
  const SegmentLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Text(
          label,
          style: textStyle(context, size: 13, weight: FontWeight.w600),
        ),
      ),
    ),
  );
}

TextStyle textStyle(
  BuildContext context, {
  double size = 17,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  bool tabular = false,
}) => TextStyle(
  fontFamily: 'Inter',
  fontSize: size,
  fontWeight: weight,
  color: color ?? Palette.of(context).ink,
  height: height ?? 1.3,
  letterSpacing: size >= 28 ? -1.0 : -.25,
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

IconData categoryIcon(String? icon) => switch (icon) {
  'food' => CupertinoIcons.cart,
  'travel' => CupertinoIcons.car,
  'bills' => CupertinoIcons.bolt,
  'shopping' => CupertinoIcons.bag,
  'health' => CupertinoIcons.heart,
  'fun' => CupertinoIcons.ticket,
  'home' => CupertinoIcons.house,
  'school' => CupertinoIcons.book,
  'income' => CupertinoIcons.arrow_down_left,
  _ => CupertinoIcons.square_grid_2x2,
};

IconData walletIcon(String icon) => switch (icon) {
  'cash' => CupertinoIcons.money_dollar_circle,
  'phone' => CupertinoIcons.device_phone_portrait,
  'card' => CupertinoIcons.creditcard,
  'bank' => CupertinoIcons.building_2_fill,
  _ => CupertinoIcons.square_stack,
};
Color walletColor(BuildContext context, Wallet wallet) {
  final p = Palette.of(context);
  return switch (wallet.color) {
    'blue' => p.blue,
    'green' => p.green,
    'amber' => p.amber,
    'rose' => p.danger,
    'slate' => p.secondary,
    _ => p.accent,
  };
}

Color categoryColor(BuildContext context, String? icon) {
  final p = Palette.of(context);
  return switch (icon) {
    'food' || 'home' => p.accent,
    'travel' || 'school' => p.blue,
    'bills' || 'shopping' => p.amber,
    'health' || 'income' => p.green,
    'fun' => p.danger,
    _ => p.secondary,
  };
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color, this.size = 38});
  final IconData icon;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final ink = color ?? Palette.of(context).accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(size * .29),
      ),
      child: Icon(icon, color: ink, size: size * .52),
    );
  }
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.height,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final double? height;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: height,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 9),
            ExcludeSemantics(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: p.secondary.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textStyle(
                            context,
                            size: 22,
                            weight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: textStyle(
                              context,
                              size: 13,
                              color: p.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  action ??
                      Press(
                        label: 'Close $title',
                        padding: const EdgeInsets.all(12),
                        onPressed: () => Navigator.pop(context),
                        child: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: p.secondary,
                          size: 26,
                        ),
                      ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

Future<T?> showPocketSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  if (!MotionScope.of(context)) {
    return showCupertinoModalPopup<T>(context: context, builder: builder);
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss sheet',
    barrierColor: const Color(0x55000000),
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, animation, secondary) =>
        Align(alignment: Alignment.bottomCenter, child: builder(ctx)),
  );
}

Future<Wallet?> chooseWallet(
  BuildContext context,
  List<Wallet> wallets, {
  required String title,
  VoidCallback? manageButtons,
}) => showPocketSheet<Wallet>(
  context: context,
  builder: (ctx) => SheetFrame(
    title: title,
    subtitle: title == 'Paid with' || title == 'Received in'
        ? 'Choose a wallet to record this entry.'
        : 'Choose one of your wallets.',
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        if (manageButtons != null) ...[
          Press(
            key: const ValueKey('manage-direct-buttons'),
            color: Palette.of(ctx).surface,
            onPressed: () {
              Navigator.pop(ctx);
              manageButtons();
            },
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.square_grid_2x2,
                  color: Palette.of(ctx).accent,
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Edit direct entry buttons',
                    style: textStyle(ctx, size: 15, weight: FontWeight.w600),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  color: Palette.of(ctx).secondary,
                  size: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < wallets.length; i++) ...[
                Press(
                  key: ValueKey('wallet-choice-${wallets[i].id}'),
                  label:
                      '$title ${wallets[i].label}${wallets[i].archived ? ', archived, retain for edit' : ''}',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  onPressed: () => Navigator.pop(ctx, wallets[i]),
                  child: Row(
                    children: [
                      IconTile(
                        walletIcon(wallets[i].icon),
                        color: walletColor(ctx, wallets[i]),
                        size: 42,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          wallets[i].label,
                          style: textStyle(ctx, weight: FontWeight.w600),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.arrow_up_right,
                        size: 18,
                        color: Palette.of(ctx).secondary,
                      ),
                    ],
                  ),
                ),
                if (i < wallets.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 72),
                    child: Rule(),
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  ),
);

class Press extends StatefulWidget {
  const Press({
    super.key,
    required this.child,
    this.onPressed,
    this.color,
    this.label,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.radius = 16,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final Color? color;
  final String? label;
  final EdgeInsets padding;
  final double radius;
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final reduced = MotionScope.of(context);
    final interactive = Listener(
      onPointerDown: (_) {
        if (mounted && widget.onPressed != null) {
          setState(() => pressed = true);
        }
      },
      onPointerUp: (_) {
        if (mounted) setState(() => pressed = false);
      },
      onPointerCancel: (_) {
        if (mounted) setState(() => pressed = false);
      },
      child: AnimatedScale(
        scale: pressed && !reduced ? .975 : 1,
        duration: Duration(milliseconds: reduced ? 0 : (pressed ? 90 : 260)),
        curve: pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: CupertinoButton(
          padding: widget.padding,
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.radius),
          minimumSize: const Size(48, 48),
          disabledColor: Palette.of(context).line,
          onPressed: widget.onPressed,
          child: DefaultTextStyle(
            style: textStyle(context, weight: FontWeight.w600),
            child: widget.child,
          ),
        ),
      ),
    );
    return Semantics(
      label: widget.label,
      button: true,
      enabled: widget.onPressed != null,
      onTap: widget.onPressed,
      child: widget.label == null
          ? interactive
          : ExcludeSemantics(child: interactive),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Press(
      onPressed: onPressed,
      color: p.accent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: p.onAccent, size: 21),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: textStyle(
                context,
                weight: FontWeight.w600,
                color: p.onAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Palette.of(context).surface,
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 20, 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textStyle(context, size: 34, weight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: textStyle(
                    context,
                    size: 14,
                    color: Palette.of(context).secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class GroupRow extends StatelessWidget {
  const GroupRow(
    this.title, {
    super.key,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.last = false,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger, last;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          if (icon != null) ...[
            IconTile(icon!, color: danger ? p.danger : p.accent, size: 32),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textStyle(context, color: danger ? p.danger : p.ink),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: textStyle(context, size: 13, color: p.secondary),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, color: p.secondary, size: 16),
          ],
        ],
      ),
    );
    return Column(
      children: [
        if (onTap != null)
          Press(
            onPressed: onTap,
            padding: EdgeInsets.zero,
            radius: 0,
            child: content,
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: content,
          ),
        if (!last)
          Padding(
            padding: EdgeInsets.only(left: icon == null ? 18 : 64),
            child: Container(height: .5, color: p.line),
          ),
      ],
    );
  }
}

class QuietMessage extends StatelessWidget {
  const QuietMessage(
    this.title,
    this.message, {
    super.key,
    this.icon = CupertinoIcons.tray,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 36, color: p.accent),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: textStyle(context, size: 19, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textStyle(context, size: 15, color: p.secondary),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class ErrorLine extends StatelessWidget {
  const ErrorLine(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              message!,
              style: textStyle(
                context,
                size: 14,
                color: Palette.of(context).danger,
              ),
            ),
          ),
        );
}

class PocketRoute<T> extends CupertinoPageRoute<T> {
  PocketRoute({
    required super.builder,
    this.reduced = false,
    super.fullscreenDialog,
    super.settings,
  });
  final bool reduced;
  @override
  Simulation? createSimulation({required bool forward}) => reduced
      ? null
      : SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 520, damping: 46),
          controller?.value ?? (forward ? 0 : 1),
          forward ? 1 : 0,
          0,
          tolerance: const Tolerance(distance: .001, velocity: .001),
          snapToEnd: true,
        );
  @override
  Duration get transitionDuration => Duration(milliseconds: reduced ? 0 : 320);
  @override
  Duration get reverseTransitionDuration =>
      Duration(milliseconds: reduced ? 0 : 280);
}

class PocketEntryRoute<T> extends CupertinoSheetRoute<T> {
  PocketEntryRoute({
    required Widget page,
    required this.reduced,
    super.settings,
  }) : super(
         topGap: .055,
         scrollableBuilder: (_, _) => ClipRRect(
           borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
           child: page,
         ),
       );
  final bool reduced;
  @override
  Color get barrierColor => const Color(0xFF080709);
  @override
  Duration get transitionDuration => Duration(milliseconds: reduced ? 0 : 380);
  @override
  Duration get reverseTransitionDuration =>
      Duration(milliseconds: reduced ? 0 : 300);
  @override
  Simulation? createSimulation({required bool forward}) => reduced
      ? null
      : SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 520, damping: 46),
          controller?.value ?? (forward ? 0 : 1),
          forward ? 1 : 0,
          0,
          tolerance: const Tolerance(distance: .001, velocity: .001),
          snapToEnd: true,
        );
}

Future<T?> pushPocket<T>(
  BuildContext context,
  Widget page, {
  bool modal = false,
}) => Navigator.of(context).push<T>(
  modal
      ? PocketEntryRoute<T>(page: page, reduced: MotionScope.of(context))
      : PocketRoute<T>(builder: (_) => page, reduced: MotionScope.of(context)),
);

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Continue',
  bool destructive = false,
}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> textPrompt(
  BuildContext context, {
  required String title,
  String value = '',
  String? hint,
  bool amount = false,
  bool signed = false,
  int maxLength = 500,
  String? message,
  ValueChanged<String>? onChanged,
}) async {
  final controller = TextEditingController(text: value);
  final route = CupertinoDialogRoute<String>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(
        title,
        style: textStyle(context, size: 17, weight: FontWeight.w600),
      ),
      content: Column(
        children: [
          if (message != null) ...[const SizedBox(height: 8), Text(message)],
          const SizedBox(height: 14),
          CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: hint,
            placeholderStyle: textStyle(
              context,
              size: 17,
              color: Palette.of(context).secondary,
            ),
            style: textStyle(context),
            onChanged: onChanged,
            maxLength: maxLength,
            keyboardType: amount
                ? TextInputType.numberWithOptions(decimal: true, signed: signed)
                : TextInputType.text,
            textCapitalization: amount
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            onSubmitted: (_) => Navigator.pop(ctx, controller.text),
            decoration: BoxDecoration(
              color: Palette.of(context).surface,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  // Return the edit immediately; release the field only after its route leaves.
  route.completed.whenComplete(controller.dispose);

  return result;
}

class Rule extends StatelessWidget {
  const Rule({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: .5, color: Palette.of(context).line);
}

class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.entry,
    required this.ledger,
    this.onTap,
  });
  final Entry entry;
  final Ledger ledger;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final category = ledger.category(entry.categoryId);
    final transfer = entry.kind == EntryKind.transfer;
    final title = entry.adjustment != null
        ? 'Balance adjustment'
        : transfer
        ? '${ledger.wallet(entry.wallet)!.label} → ${ledger.wallet(entry.toWallet)!.label}'
        : category?.name ?? 'Category';
    final amount =
        '${entry.kind == EntryKind.income
            ? '+'
            : entry.kind == EntryKind.expense
            ? '−'
            : ''}${money(entry.centavos)}';
    return Press(
      onPressed: onTap,
      label:
          '$title, $amount, ${shortDate(entry.date)}, ${ledger.wallet(entry.wallet)!.label}',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: transfer
                  ? p.blueTint
                  : entry.kind == EntryKind.income
                  ? p.greenTint
                  : categoryColor(
                      context,
                      category?.icon,
                    ).withValues(alpha: .10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              entry.adjustment != null
                  ? CupertinoIcons.money_dollar_circle
                  : transfer
                  ? CupertinoIcons.arrow_right_arrow_left
                  : categoryIcon(category?.icon),
              size: 21,
              color: transfer
                  ? p.blue
                  : entry.kind == EntryKind.income
                  ? p.green
                  : categoryColor(context, category?.icon),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(context, size: 15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.note.isEmpty
                      ? '${ledger.wallet(entry.wallet)!.label} · ${shortDate(entry.date)}'
                      : '${ledger.wallet(entry.wallet)!.label} · ${entry.note}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(context, size: 12, color: p.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: textStyle(
              context,
              size: 15,
              weight: FontWeight.w600,
              tabular: true,
              color: entry.kind == EntryKind.income ? p.green : p.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class PocketSwitch extends StatelessWidget {
  const PocketSwitch({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: value,
    enabled: onChanged != null,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: ExcludeSemantics(
      child: SizedBox(
        width: 60,
        height: 48,
        child: CupertinoSwitch(
          value: value,
          activeTrackColor: Palette.of(context).accent,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}
