import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';

import '../domain/ledger.dart';

class VisualStyleScope extends InheritedWidget {
  const VisualStyleScope({
    super.key,
    required this.style,
    required super.child,
  });
  final VisualStyle style;
  static VisualStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VisualStyleScope>()?.style ??
      VisualStyle.original;
  @override
  bool updateShouldNotify(VisualStyleScope oldWidget) =>
      style != oldWidget.style;
}

class Palette {
  const Palette(this.dark, [this.style = VisualStyle.original]);
  final bool dark;
  final VisualStyle style;
  static Palette of(BuildContext context) => Palette(
    CupertinoTheme.of(context).brightness == Brightness.dark,
    VisualStyleScope.of(context),
  );
  Color tone(int light, int night) => Color(dark ? night : light);
  Color get background => switch (style) {
    VisualStyle.powderBlue => tone(0xFFEFF6FC, 0xFF142431),
    VisualStyle.notebook => tone(0xFFF6F1E5, 0xFF25231F),
    VisualStyle.midnight => const Color(0xFF0C1420),
    _ => tone(0xFFF6F4F1, 0xFF151416),
  };
  Color get surface => switch (style) {
    VisualStyle.powderBlue => tone(0xFFF8FCFF, 0xFF1F3546),
    VisualStyle.notebook => tone(0xFFFFFCF4, 0xFF302C26),
    VisualStyle.midnight => const Color(0xFF152235),
    _ => tone(0xFFFFFFFF, 0xFF232125),
  };
  Color get ink => switch (style) {
    VisualStyle.powderBlue => tone(0xFF173447, 0xFFEDF7FF),
    VisualStyle.notebook => tone(0xFF302A23, 0xFFF5ECDD),
    VisualStyle.midnight => const Color(0xFFF0F5FF),
    _ => tone(0xFF27212A, 0xFFF7F3F1),
  };
  Color get secondary => switch (style) {
    VisualStyle.powderBlue => tone(0xFF4B6274, 0xFFB8CCD9),
    VisualStyle.notebook => tone(0xFF685C4D, 0xFFC9BCA7),
    VisualStyle.midnight => const Color(0xFFB8C8DC),
    _ => tone(0xFF6A606F, 0xFFBBB3BD),
  };
  Color get line => switch (style) {
    VisualStyle.powderBlue => tone(0xFFB7CBDA, 0xFF526B7E),
    VisualStyle.notebook => tone(0xFFCFC3AC, 0xFF716958),
    VisualStyle.midnight => const Color(0xFF455A76),
    _ => tone(0xFFE5DFE7, 0xFF3F3943),
  };
  Color get accent => switch (style) {
    VisualStyle.powderBlue => tone(0xFF244E6D, 0xFFB7D9F1),
    VisualStyle.notebook => tone(0xFF55432B, 0xFFE3C895),
    VisualStyle.midnight => const Color(0xFFC1DCFF),
    _ => tone(0xFF5B315D, 0xFFE9CCE6),
  };
  Color get onAccent => switch (style) {
    VisualStyle.powderBlue => tone(0xFFFFFFFF, 0xFF122B3D),
    VisualStyle.notebook => tone(0xFFFFFFFF, 0xFF302519),
    VisualStyle.midnight => const Color(0xFF10233D),
    _ => tone(0xFFFFFFFF, 0xFF322235),
  };
  Color get tint => switch (style) {
    VisualStyle.powderBlue => tone(0xFFD8EAF6, 0xFF304F66),
    VisualStyle.notebook => tone(0xFFEDE1CA, 0xFF4B4030),
    VisualStyle.midnight => const Color(0xFF243D5B),
    _ => tone(0xFFF0E8F1, 0xFF382E3C),
  };
  double get cardRadius => switch (style) {
    VisualStyle.powderBlue => 28,
    VisualStyle.notebook || VisualStyle.midnight => 12,
    _ => 20,
  };
  double get controlRadius => switch (style) {
    VisualStyle.powderBlue => 24,
    VisualStyle.notebook || VisualStyle.midnight => 10,
    _ => 16,
  };
  double get sheetRadius => switch (style) {
    VisualStyle.powderBlue => 34,
    VisualStyle.notebook => 18,
    VisualStyle.midnight => 16,
    _ => 30,
  };
  double get navRadius => switch (style) {
    VisualStyle.powderBlue => 30,
    VisualStyle.notebook || VisualStyle.midnight => 14,
    _ => 26,
  };
  double controlCorner(double original) =>
      style == VisualStyle.original ? original : controlRadius;
  double get badgeRadius => style == VisualStyle.original
      ? 13
      : style == VisualStyle.powderBlue
      ? 18
      : 8;
  Border? get border =>
      style == VisualStyle.original ? null : Border.all(color: line);
  Color get green => tone(0xFF246D53, 0xFFADE2C8);
  Color get greenTint => tone(0xFFE8F3EC, 0xFF263C33);
  Color get blue => tone(0xFF285B8C, 0xFFBBD7FF);
  Color get blueTint => tone(0xFFEAF1FA, 0xFF29374C);
  Color get danger => tone(0xFFAA3429, 0xFFFFBAB3);
  Color get amber => tone(0xFF84551C, 0xFFEFCF9C);
}

/// Static, low-contrast decoration stays behind content and never receives input.
class SurfaceDetail extends CustomPainter {
  const SurfaceDetail(this.palette);
  final Palette palette;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = palette.accent.withValues(alpha: .055);
    if (palette.style == VisualStyle.powderBlue) {
      canvas.drawCircle(Offset(size.width - 30, 18), 22, paint);
      canvas.drawCircle(Offset(size.width - 57, 20), 15, paint);
      canvas.drawCircle(Offset(size.width - 12, 32), 18, paint);
    } else if (palette.style == VisualStyle.notebook) {
      paint.strokeWidth = .5;
      for (double y = 26; y < size.height; y += 26) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      canvas.drawLine(const Offset(12, 0), Offset(12, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(SurfaceDetail oldDelegate) =>
      oldDelegate.palette.style != palette.style ||
      oldDelegate.palette.dark != palette.dark;
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
      padding: EdgeInsets.zero,
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
  fontWeight:
      VisualStyleScope.of(context) == VisualStyle.notebook &&
          size >= 19 &&
          weight.value >= FontWeight.w600.value &&
          !tabular
      ? FontWeight.w500
      : weight,
  color: color ?? Palette.of(context).ink,
  height: height ?? 1.3,
  letterSpacing: VisualStyleScope.of(context) == VisualStyle.notebook
      ? 0
      : (size >= 28 ? -1.0 : -.25),
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

/// Shared form treatment; callbacks and keyboard behavior stay with the caller.
class PocketTextField extends StatelessWidget {
  const PocketTextField({
    super.key,
    required this.controller,
    this.placeholder,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.money = false,
    this.compact = false,
  });
  final TextEditingController controller;
  final String? placeholder;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged, onSubmitted;
  final bool autofocus, money, compact;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = money && !compact ? 24.0 : 17.0;
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      maxLength: maxLength,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      style: textStyle(context, size: size, tabular: money),
      placeholderStyle: textStyle(context, size: size, color: p.secondary),
      cursorColor: p.accent,
      prefix: money && !compact
          ? Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                '₱',
                style: textStyle(context, size: size, color: p.secondary),
              ),
            )
          : null,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(p.controlRadius),
        border: p.border,
      ),
    );
  }
}

TextStyle formLabelStyle(BuildContext context) => textStyle(
  context,
  size: 14,
  weight: FontWeight.w600,
  color: Palette.of(context).secondary,
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
        borderRadius: BorderRadius.circular(
          Palette.of(context).style == VisualStyle.original
              ? size * .29
              : size *
                    (Palette.of(context).style == VisualStyle.powderBlue
                        ? .4
                        : .18),
        ),
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(p.sheetRadius),
        ),
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
    this.radius,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final Color? color;
  final String? label;
  final EdgeInsets padding;
  final double? radius;
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
          borderRadius: BorderRadius.circular(
            widget.radius ?? Palette.of(context).controlRadius,
          ),
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
            Icon(
              icon,
              color: onPressed == null ? p.secondary : p.onAccent,
              size: 21,
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: textStyle(
                context,
                weight: FontWeight.w600,
                color: onPressed == null ? p.secondary : p.onAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary actions share a quieter tint and the primary button's hit target.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton(
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
      color: p.tint,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: onPressed == null ? p.secondary : p.accent,
              size: 20,
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: textStyle(
                context,
                color: onPressed == null ? p.secondary : p.accent,
                weight: FontWeight.w600,
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
    this.roundTop = true,
    this.roundBottom = true,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool roundTop, roundBottom;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(roundTop ? p.cardRadius : 0),
          bottom: Radius.circular(roundBottom ? p.cardRadius : 0),
        ),
        border: p.border == null
            ? null
            : Border(
                left: BorderSide(color: p.line),
                right: BorderSide(color: p.line),
                top: roundTop ? BorderSide(color: p.line) : BorderSide.none,
                bottom: roundBottom
                    ? BorderSide(color: p.line)
                    : BorderSide.none,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: SurfaceDetail(p),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textStyle(context, size: 32, weight: FontWeight.w700),
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
    this.selected,
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
  final bool? selected;
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
          if (selected != null)
            Icon(
              selected!
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: p.accent,
              size: 24,
            ),
          if (onTap != null && selected == null) ...[
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, color: p.secondary, size: 16),
          ],
        ],
      ),
    );
    return Semantics(
      selected: selected,
      child: Column(
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
      ),
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
         scrollableBuilder: (context, _) => ClipRRect(
           borderRadius: BorderRadius.vertical(
             top: Radius.circular(Palette.of(context).sheetRadius),
           ),
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
          PocketTextField(
            controller: controller,
            autofocus: true,
            compact: true,
            money: amount,
            placeholder: hint,
            onChanged: onChanged,
            maxLength: maxLength,
            keyboardType: amount
                ? TextInputType.numberWithOptions(decimal: true, signed: signed)
                : TextInputType.text,
            textCapitalization: amount
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            onSubmitted: (_) => Navigator.pop(ctx, controller.text),
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
              borderRadius: BorderRadius.circular(p.badgeRadius),
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
