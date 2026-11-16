import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../app_controller.dart';
import '../domain/adventure.dart';
import '../domain/ledger.dart';
import 'design.dart';

Future<void> showAdventureBadgeCollection(
  BuildContext context,
  AppController app,
) => showPocketSheet<void>(
  context: context,
  builder: (ctx) {
    final earned = AdventureBadges.earned(app.ledger);
    return SheetFrame(
      title: 'Badge collection',
      subtitle: '${earned.length} of ${AdventureBadge.values.length} earned',
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          for (final badge in AdventureBadge.values) ...[
            _AdventureBadgeRow(badge: badge, earned: earned.contains(badge)),
            if (badge != AdventureBadge.values.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  },
);

class AdventureSectionHeader extends StatelessWidget {
  const AdventureSectionHeader({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.subtitle,
    required this.asset,
    this.trailing,
  });
  final String title, eyebrow, subtitle, asset;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: p.ink,
          border: Border.all(color: p.amber, width: 3),
          boxShadow: [
            BoxShadow(
              color: p.ink.withValues(alpha: .28),
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        child: Row(
          children: [
            Image.asset(
              asset,
              width: 42,
              height: 42,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      context,
                      size: 9,
                      weight: FontWeight.w800,
                      color: p.amber,
                    ).copyWith(letterSpacing: .4),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      context,
                      size: 22,
                      weight: FontWeight.w800,
                      color: p.surface,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(context, size: 11, color: p.surface),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 2), trailing!],
          ],
        ),
      ),
    );
  }
}

class _AdventureBadgeRow extends StatelessWidget {
  const _AdventureBadgeRow({required this.badge, required this.earned});
  final AdventureBadge badge;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label:
          '${badge.title}. ${earned ? 'Earned' : 'Locked'}. ${badge.description}',
      child: Surface(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Opacity(
              opacity: earned ? 1 : .38,
              child: Image.asset(
                badge.asset,
                width: 58,
                height: 58,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badge.title,
                    style: textStyle(
                      context,
                      size: 15,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    badge.description,
                    style: textStyle(context, size: 12, color: p.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              earned ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.lock,
              color: earned ? p.green : p.secondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class AdventureBillsProgress extends StatelessWidget {
  const AdventureBillsProgress({super.key, required this.ledger});
  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bills = ledger.bills
        .where((bill) => bill.paymentCount != null)
        .toList();
    if (bills.isEmpty) return const SizedBox.shrink();
    final shown = bills.take(3).toList();
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bill progress',
                  style: textStyle(context, size: 16, weight: FontWeight.w600),
                ),
              ),
              Image.asset(
                'assets/adventure/pixel_bills.png',
                width: 54,
                height: 54,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                semanticLabel: 'Bill progress badge illustration',
              ),
            ],
          ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _BillProgressRow(bill: shown[i], ledger: ledger),
          ],
          if (bills.length > shown.length) ...[
            const SizedBox(height: 10),
            Text(
              '+${bills.length - shown.length} more fixed-term bills',
              style: textStyle(context, size: 12, color: p.secondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillProgressRow extends StatelessWidget {
  const _BillProgressRow({required this.bill, required this.ledger});
  final Bill bill;
  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final count = bill.paymentCount!;
    final paid = bill.paidInstallments(ledger);
    final progress = count == 0 ? 0.0 : paid / count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                bill.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textStyle(context, size: 14, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$paid of $count',
              style: textStyle(context, size: 12, color: p.secondary),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            key: ValueKey('bill-progress-track-${bill.id}'),
            width: double.infinity,
            height: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: p.tint),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                    heightFactor: 1,
                    child: ColoredBox(
                      key: ValueKey('bill-progress-fill-${bill.id}'),
                      color: p.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AdventureRewardOverlay extends StatefulWidget {
  const AdventureRewardOverlay({super.key, required this.app});
  final AppController app;

  @override
  State<AdventureRewardOverlay> createState() => _AdventureRewardOverlayState();
}

class _AdventureRewardOverlayState extends State<AdventureRewardOverlay>
    with SingleTickerProviderStateMixin {
  Timer? timer;
  int? activeId;
  int? dismissedId;
  late final AnimationController timeline;
  _AdventureSparklesPainter? sparkles;

  @override
  void initState() {
    super.initState();
    timeline = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    widget.app.addListener(changed);
    changed();
  }

  bool get _reducedMotion =>
      widget.app.ledger.preferences.reduceMotion ||
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;

  void changed() {
    final event = widget.app.adventureReward;
    if (event == null) {
      timer?.cancel();
      activeId = null;
      timeline.stop();
      timeline.value = 0;
      sparkles = null;
      return;
    }
    if (event.id == activeId) return;
    activeId = event.id;
    dismissedId = null;
    timer?.cancel();
    timeline.stop();
    timeline.value = 0;
    final milestone =
        event.badge != null || event.kind != AdventureRewardKind.saved;
    timeline.duration = Duration(milliseconds: milestone ? 1450 : 520);
    sparkles = milestone
        ? _AdventureSparklesPainter(animation: timeline, seed: event.id)
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.app.adventureReward?.id != event.id) return;
      if (_reducedMotion) {
        timeline.value = 1;
      } else {
        timeline.forward(from: 0);
      }
    });
    timer = Timer(const Duration(milliseconds: 3600), () {
      if (mounted) widget.app.clearAdventureReward(event.id);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.app.removeListener(changed);
    timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.app.adventureReward;
    if (event == null ||
        dismissedId == event.id ||
        !Palette.of(context).adventure) {
      return const SizedBox.shrink();
    }
    final p = Palette.of(context);
    final milestone =
        event.badge != null || event.kind != AdventureRewardKind.saved;
    final trophy =
        event.kind == AdventureRewardKind.billCompleted ||
        event.kind == AdventureRewardKind.loanCompleted;
    final artAsset = trophy
        ? 'assets/celebrations/bill_completed.png'
        : event.badge?.asset;
    final entryFade = Interval(
      0,
      milestone ? .16 : .12,
      curve: Curves.easeOutCubic,
    );
    final textReveal = Interval(
      milestone ? .24 : .10,
      milestone ? .48 : .34,
      curve: Curves.easeOutCubic,
    );
    return Positioned(
      left: 20,
      right: 20,
      top: MediaQuery.paddingOf(context).top + 56,
      child: Dismissible(
        key: ValueKey('adventure-reward-${event.id}'),
        direction: DismissDirection.horizontal,
        movementDuration: MotionScope.of(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        resizeDuration: MotionScope.of(context)
            ? null
            : const Duration(milliseconds: 180),
        onDismissed: (_) {
          setState(() => dismissedId = event.id);
          widget.app.clearAdventureReward(event.id);
        },
        child: Semantics(
          liveRegion: true,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: timeline,
              builder: (context, _) {
                final progress = timeline.value;
                final artScale = milestone
                    ? _milestoneScale.transform(
                        (progress / .72).clamp(0.0, 1.0),
                      )
                    : _saveScale.transform((progress / .64).clamp(0.0, 1.0));
                final textProgress = textReveal.transform(progress);
                final subtitle = event.badge == null
                    ? switch (event.kind) {
                        AdventureRewardKind.saved =>
                          'Your everyday entry is in the ledger.',
                        AdventureRewardKind.billCompleted =>
                          'Every installment is accounted for.',
                        AdventureRewardKind.loanCompleted =>
                          'The final repayment is recorded.',
                      }
                    : 'New badge · ${event.badge!.title}';
                return Opacity(
                  opacity: entryFade.transform(progress),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(p.cardRadius + 4),
                      border: Border.all(
                        color: p.accent.withValues(alpha: .68),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF000000).withValues(alpha: .20),
                          blurRadius: 24,
                          offset: const Offset(0, 9),
                        ),
                        BoxShadow(
                          color: p.amber.withValues(alpha: .15),
                          blurRadius: 28,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    child: Row(
                      children: [
                        Transform.scale(
                          key: const ValueKey('adventure-reward-art'),
                          scale: artScale,
                          child: SizedBox(
                            width: 86,
                            height: 86,
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                if (milestone && sparkles != null)
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      key: const ValueKey('adventure-sparkles'),
                                      size: const Size(86, 86),
                                      painter: sparkles,
                                    ),
                                  ),
                                if (artAsset != null)
                                  Image.asset(
                                    artAsset,
                                    width: trophy ? 80 : 70,
                                    height: trophy ? 80 : 70,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.none,
                                    excludeFromSemantics: true,
                                  )
                                else
                                  Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    size: 62,
                                    color: p.green,
                                  ),
                                if (trophy && event.badge != null)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: p.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: p.accent,
                                          width: 1.5,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(3),
                                      child: Image.asset(
                                        event.badge!.asset,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.none,
                                        excludeFromSemantics: true,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Transform.translate(
                            offset: Offset(0, (1 - textProgress) * 8),
                            child: Opacity(
                              opacity: textProgress,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    event.title,
                                    style: textStyle(
                                      context,
                                      size: 15,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: textStyle(
                                      context,
                                      size: 13,
                                      color: p.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Press(
                          label: 'Dismiss adventure celebration',
                          padding: const EdgeInsets.all(12),
                          onPressed: () =>
                              widget.app.clearAdventureReward(event.id),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 17,
                            color: p.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static final TweenSequence<double> _milestoneScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: .38,
        end: 1.28,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.28,
        end: .94,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: .94,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 25,
    ),
  ]);

  static final TweenSequence<double> _saveScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: .75,
        end: 1.10,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 64,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.10,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 36,
    ),
  ]);
}

class _Sparkle {
  const _Sparkle(
    this.angle,
    this.distance,
    this.delay,
    this.bend,
    this.size,
    this.rotation,
  );
  final double angle, distance, delay, bend, size, rotation;
}

class _AdventureSparklesPainter extends CustomPainter {
  _AdventureSparklesPainter({required this.animation, required int seed})
    : sparkles = _createSparkles(seed),
      super(repaint: animation);

  final Animation<double> animation;
  final List<_Sparkle> sparkles;

  static List<_Sparkle> _createSparkles(int seed) {
    final random = math.Random(seed);
    return List.generate(
      12,
      (_) => _Sparkle(
        random.nextDouble() * math.pi * 2,
        30 + random.nextDouble() * 22,
        random.nextDouble() * .24,
        (random.nextDouble() - .5) * 28,
        2.3 + random.nextDouble() * 2.3,
        random.nextDouble() * math.pi,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final t = animation.value;
    for (final sparkle in sparkles) {
      final local = ((t - sparkle.delay) / (1 - sparkle.delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final direction = Offset(
        math.cos(sparkle.angle),
        math.sin(sparkle.angle),
      );
      final end = center + direction * sparkle.distance;
      final perpendicular = Offset(-direction.dy, direction.dx);
      final control =
          Offset.lerp(center, end, .5)! + perpendicular * sparkle.bend;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      final metric = path.computeMetrics().first;
      final eased = Curves.easeOutCubic.transform(local);
      final tangent = metric.getTangentForOffset(metric.length * eased);
      if (tangent == null) continue;
      final alpha = (math.sin(math.pi * local) * .94).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = const Color(0xFFFFD56A).withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(tangent.position.dx, tangent.position.dy);
      canvas.rotate(sparkle.rotation + local * 1.8);
      canvas.drawPath(_star(Offset.zero, sparkle.size), paint);
      canvas.restore();
    }
  }

  Path _star(Offset center, double radius) {
    final path = Path();
    for (var point = 0; point < 8; point++) {
      final angle = -math.pi / 2 + point * math.pi / 4;
      final r = point.isEven ? radius : radius * .32;
      final position =
          center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (point == 0) {
        path.moveTo(position.dx, position.dy);
      } else {
        path.lineTo(position.dx, position.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_AdventureSparklesPainter oldDelegate) =>
      oldDelegate.sparkles != sparkles;
}
