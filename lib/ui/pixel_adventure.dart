import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../app_controller.dart';
import '../domain/adventure.dart';
import '../domain/ledger.dart';
import 'adventure.dart';
import 'design.dart';

class PixelFrame extends StatelessWidget {
  const PixelFrame({
    super.key,
    required this.child,
    this.fillColor,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color? fillColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CustomPaint(
      foregroundPainter: _PixelTrimPainter(ink: p.ink, gold: p.pixelGold),
      child: ClipPath(
        clipper: const _PixelCornerClipper(),
        child: Container(color: fillColor, padding: padding, child: child),
      ),
    );
  }
}

class _PixelCornerClipper extends CustomClipper<Path> {
  const _PixelCornerClipper();

  @override
  Path getClip(Size size) {
    final step = math.min(5.0, math.min(size.width, size.height) / 5);
    return Path()
      ..moveTo(2 * step, 0)
      ..lineTo(size.width - 2 * step, 0)
      ..lineTo(size.width - 2 * step, step)
      ..lineTo(size.width - step, step)
      ..lineTo(size.width, 2 * step)
      ..lineTo(size.width, size.height - 2 * step)
      ..lineTo(size.width - step, size.height - step)
      ..lineTo(size.width - 2 * step, size.height - step)
      ..lineTo(size.width - 2 * step, size.height)
      ..lineTo(2 * step, size.height)
      ..lineTo(2 * step, size.height - step)
      ..lineTo(step, size.height - step)
      ..lineTo(0, size.height - 2 * step)
      ..lineTo(0, 2 * step)
      ..lineTo(step, step)
      ..lineTo(2 * step, step)
      ..close();
  }

  @override
  bool shouldReclip(_PixelCornerClipper oldClipper) => false;
}

class _PixelTrimPainter extends CustomPainter {
  const _PixelTrimPainter({required this.ink, required this.gold});
  final Color ink, gold;

  Path _path(Rect rect) {
    final step = math.min(5.0, math.min(rect.width, rect.height) / 5);
    return Path()
      ..moveTo(rect.left + 2 * step, rect.top)
      ..lineTo(rect.right - 2 * step, rect.top)
      ..lineTo(rect.right - 2 * step, rect.top + step)
      ..lineTo(rect.right - step, rect.top + step)
      ..lineTo(rect.right, rect.top + 2 * step)
      ..lineTo(rect.right, rect.bottom - 2 * step)
      ..lineTo(rect.right - step, rect.bottom - step)
      ..lineTo(rect.right - 2 * step, rect.bottom - step)
      ..lineTo(rect.right - 2 * step, rect.bottom)
      ..lineTo(rect.left + 2 * step, rect.bottom)
      ..lineTo(rect.left + 2 * step, rect.bottom - step)
      ..lineTo(rect.left + step, rect.bottom - step)
      ..lineTo(rect.left, rect.bottom - 2 * step)
      ..lineTo(rect.left, rect.top + 2 * step)
      ..lineTo(rect.left + step, rect.top + step)
      ..lineTo(rect.left + 2 * step, rect.top + step)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final bounds = Offset.zero & size;
    canvas.drawPath(
      _path(bounds.deflate(1)),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.miter,
    );
    canvas.drawPath(
      _path(bounds.deflate(3.5)),
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_PixelTrimPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.gold != gold;
}

class PixelAdventureHero extends StatelessWidget {
  const PixelAdventureHero({
    super.key,
    required this.app,
    required this.ledger,
    required this.onSettings,
    required this.onWallets,
    required this.onAdd,
  });

  final AppController app;
  final Ledger ledger;
  final VoidCallback onSettings, onWallets, onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final earned = AdventureBadges.earned(ledger).length;
    final count = ledger.availableWallets.length;
    final balance = ledger.activeWalletBalance;
    return LayoutBuilder(
      builder: (context, constraints) {
        final heroHeight = (constraints.maxWidth * 1.23).clamp(438.0, 500.0);
        return PixelFrame(
          key: const ValueKey('adventure-overworld'),
          child: SizedBox(
            width: double.infinity,
            height: heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/adventure/overworld.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                  semanticLabel:
                      'Pixel map of the PonPon village, river, and paths',
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        p.ink.withValues(alpha: .92),
                        p.ink.withValues(alpha: .67),
                        p.ink.withValues(alpha: .08),
                        p.ink.withValues(alpha: .04),
                      ],
                      stops: const [0, .40, .72, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PixelFrame(
                        fillColor: p.ink.withValues(alpha: .97),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/adventure/pixel_companion.png',
                              width: 38,
                              height: 38,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.none,
                              semanticLabel: 'PonPon companion',
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'PonPon',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle(
                                      context,
                                      size: 20,
                                      weight: FontWeight.w800,
                                      color: p.surface,
                                    ),
                                  ),
                                  Text(
                                    'TODAY · ${shortDate(dayKey(app.clock()))}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle(
                                      context,
                                      size: 9,
                                      weight: FontWeight.w700,
                                      color: p.pixelGold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Press(
                              key: const ValueKey('adventure-badge-shortcut'),
                              label:
                                  'Open badge collection, $earned of 3 earned',
                              onPressed: () =>
                                  showAdventureBadgeCollection(context, app),
                              color: p.accent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.rosette,
                                    size: 16,
                                    color: p.pixelGold,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$earned/3',
                                    style: textStyle(
                                      context,
                                      size: 10,
                                      weight: FontWeight.w800,
                                      color: p.surface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 3),
                            Press(
                              label: 'Settings',
                              onPressed: onSettings,
                              color: p.accent,
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                CupertinoIcons.gear_alt,
                                color: p.surface,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                      PixelFrame(
                        fillColor: p.ink.withValues(alpha: .97),
                        padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                label: count == 0
                                    ? 'No active wallets'
                                    : 'Total tracked balance ${money(balance)} across $count active ${count == 1 ? 'wallet' : 'wallets'}. Manual records.',
                                child: ExcludeSemantics(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'WALLET BALANCE',
                                        style: textStyle(
                                          context,
                                          size: 10,
                                          weight: FontWeight.w800,
                                          color: p.pixelGold,
                                        ),
                                      ),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          count == 0 ? '—' : money(balance),
                                          key: const ValueKey(
                                            'adventure-balance',
                                          ),
                                          style: textStyle(
                                            context,
                                            size: 27,
                                            weight: FontWeight.w800,
                                            tabular: true,
                                            color: balance < 0
                                                ? p.danger
                                                : p.surface,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        count == 0
                                            ? 'Add a wallet to begin'
                                            : '$count active ${count == 1 ? 'wallet' : 'wallets'} · manual records',
                                        style: textStyle(
                                          context,
                                          size: 10,
                                          color: p.surface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Press(
                              key: const ValueKey('adventure-wallet-action'),
                              label:
                                  'View and manage $count active ${count == 1 ? 'wallet' : 'wallets'}',
                              onPressed: onWallets,
                              color: p.accent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.creditcard_fill,
                                    color: p.pixelGold,
                                    size: 19,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Wallets',
                                    style: textStyle(
                                      context,
                                      size: 9,
                                      weight: FontWeight.w700,
                                      color: p.surface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                      PixelFrame(
                        fillColor: p.accent,
                        child: Press(
                          key: const ValueKey('adventure-add-entry'),
                          label: app.draft?.dirty == true
                              ? 'Resume unfinished entry'
                              : 'Add an entry',
                          onPressed: onAdd,
                          color: p.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.add,
                                color: p.surface,
                                size: 23,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  app.draft?.dirty == true
                                      ? 'Resume entry'
                                      : 'Add an entry',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textStyle(
                                    context,
                                    size: 19,
                                    weight: FontWeight.w800,
                                    color: p.surface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
