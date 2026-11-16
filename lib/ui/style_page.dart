part of 'screens.dart';

String visualStyleName(VisualStyle style) => switch (style) {
  VisualStyle.adventure => 'PonPon Adventure',
  VisualStyle.original => 'Original',
  VisualStyle.powderBlue => 'Powder Blue',
  VisualStyle.notebook => 'Notebook',
  VisualStyle.midnight => 'Midnight',
  VisualStyle.moss => 'Moss',
  VisualStyle.clay => 'Clay',
  VisualStyle.graphite => 'Graphite',
};

String visualStyleDescription(VisualStyle style) => switch (style) {
  VisualStyle.adventure => 'Parchment, forest greens and a lantern-lit night for your everyday ledger.',
  VisualStyle.original => 'Warm neutrals, soft cards and familiar purple.',
  VisualStyle.powderBlue =>
    'Airy blue surfaces, quiet cloud details and generous curves.',
  VisualStyle.notebook => 'Warm paper, fine rules and classic headings.',
  VisualStyle.midnight =>
    'Deep navy, crisp edges and luminous blue details. Always dark.',
  VisualStyle.moss =>
    'Quiet sage surfaces, forest ink and rounded, low-glare controls.',
  VisualStyle.clay =>
    'Warm sand and soft terracotta with matte, balanced surfaces.',
  VisualStyle.graphite =>
    'Charcoal surfaces with smoky gold details. Always dark.',
};

class VisualStylePage extends StatelessWidget {
  const VisualStylePage({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => PocketPage(
      'Visual style',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'A little more you',
            style: textStyle(context, size: 27, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a look for every screen. Your entries stay the same.',
            style: textStyle(
              context,
              size: 15,
              color: Palette.of(context).secondary,
            ),
          ),
          const SizedBox(height: 20),
          for (final style in VisualStyle.values) ...[
            _StylePreview(app: app, style: style),
            const SizedBox(height: 16),
          ],
        ],
      ),
    ),
  );
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.app, required this.style});
  final AppController app;
  final VisualStyle style;
  @override
  Widget build(BuildContext context) {
    final selected = app.ledger.preferences.visualStyle == style;
    final dark =
        style == VisualStyle.midnight ||
        style == VisualStyle.graphite ||
        (app.ledger.preferences.theme == 'dark' ||
            (app.ledger.preferences.theme == 'system' &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark));
    final p = Palette(dark, style);
    return VisualStyleScope(
      style: style,
      child: CupertinoTheme(
        data: CupertinoTheme.of(context).copyWith(
          brightness: dark ? Brightness.dark : Brightness.light,
          primaryColor: p.accent,
          primaryContrastingColor: p.onAccent,
        ),
        child: Builder(
          builder: (context) => Semantics(
            selected: selected,
            child: Press(
              key: ValueKey('style-${style.name}'),
              label:
                  '${visualStyleName(style)}. ${visualStyleDescription(style)}',
              padding: EdgeInsets.zero,
              onPressed: app.busy
                  ? null
                  : () async {
                      final saved = await app.preferences(
                        app.ledger.preferences.copy(visualStyle: style),
                      );
                      if (!saved && context.mounted) {
                        await showCupertinoDialog<void>(
                          context: context,
                          builder: (dialogContext) => CupertinoAlertDialog(
                            title: const Text('Style could not be saved'),
                            content: Text(app.storageError ?? 'Try again.'),
                            actions: [
                              CupertinoDialogAction(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
              child: style == VisualStyle.adventure
                  ? _AdventureStyleCard(selected: selected)
                  : Surface(
                      detailBand:
                          style == VisualStyle.powderBlue ||
                          style == VisualStyle.notebook ||
                          style == VisualStyle.moss,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  visualStyleName(style),
                                  style: textStyle(
                                    context,
                                    size: 22,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                selected
                                    ? CupertinoIcons.check_mark_circled_solid
                                    : CupertinoIcons.circle,
                                color: p.accent,
                                size: 24,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            visualStyleDescription(style),
                            style: textStyle(
                              context,
                              size: 14,
                              color: p.secondary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'PREVIEW · DAILY SPENDING',
                            style: textStyle(
                              context,
                              size: 11,
                              weight: FontWeight.w600,
                              color: p.secondary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '₱250.00',
                            style: textStyle(
                              context,
                              size: 28,
                              weight: FontWeight.w700,
                              tabular: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: p.tint,
                              borderRadius: BorderRadius.circular(
                                p.controlRadius,
                              ),
                            ),
                            child: Text(
                              'Food · Today',
                              style: textStyle(
                                context,
                                size: 14,
                                color: p.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdventureStyleCard extends StatelessWidget {
  const _AdventureStyleCard({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const selectedBadgeInk = Color(0xFF18352D);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(
          color: selected ? p.pixelGold : p.line,
          width: selected ? 4 : 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: p.ink.withValues(alpha: .35),
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PonPon Adventure',
                  style: textStyle(context, size: 18, weight: FontWeight.w800),
                ),
              ),
              Container(
                color: selected ? p.pixelGold : p.ink,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected
                          ? CupertinoIcons.check_mark
                          : CupertinoIcons.sparkles,
                      size: 13,
                      color: selected ? selectedBadgeInk : p.surface,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      selected ? 'CURRENT' : 'PREVIEW',
                      style: textStyle(
                        context,
                        size: 9,
                        weight: FontWeight.w900,
                        color: selected ? selectedBadgeInk : p.surface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            visualStyleDescription(VisualStyle.adventure),
            style: textStyle(context, size: 12, color: p.secondary),
          ),
          const SizedBox(height: 9),
          // The nested HUD is illustrative and excluded from semantics; keep
          // its miniature controls at their designed size while the actual
          // card title and description scale for accessibility.
          MediaQuery.withNoTextScaling(
            child: Builder(
              builder: (previewContext) => Column(
                children: [
                  PixelFrame(
                    fillColor: p.ink,
                    padding: const EdgeInsets.all(3),
                    child: SizedBox(
                      height: 126,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/adventure/overworld.png',
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.none,
                            excludeFromSemantics: true,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  p.ink.withValues(alpha: .94),
                                  p.ink.withValues(alpha: .70),
                                  p.ink.withValues(alpha: .20),
                                  p.ink.withValues(alpha: .91),
                                ],
                                stops: const [0, .28, .62, 1],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(7),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Image.asset(
                                      'assets/adventure/pixel_companion.png',
                                      width: 27,
                                      height: 27,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.none,
                                      excludeFromSemantics: true,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        'TODAY · PONPON VILLAGE',
                                        style: textStyle(
                                          previewContext,
                                          size: 9,
                                          weight: FontWeight.w900,
                                          color: p.pixelGold,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      CupertinoIcons.gear_alt_fill,
                                      color: p.surface,
                                      size: 15,
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'WALLET BALANCE',
                                            style: textStyle(
                                              previewContext,
                                              size: 8,
                                              weight: FontWeight.w800,
                                              color: p.pixelGold,
                                            ),
                                          ),
                                          Text(
                                            '₱6,327.50',
                                            style: textStyle(
                                              previewContext,
                                              size: 20,
                                              weight: FontWeight.w900,
                                              color: p.surface,
                                              tabular: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      color: p.accent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 7,
                                      ),
                                      child: Text(
                                        '+ ADD ENTRY',
                                        style: textStyle(
                                          previewContext,
                                          size: 9,
                                          weight: FontWeight.w900,
                                          color: p.surface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  ExcludeSemantics(
                    child: IgnorePointer(
                      child: PixelFrame(
                        fillColor: p.ink,
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            for (final (index, label) in [
                              (0, 'Today'),
                              (1, 'History'),
                              (2, 'Plan'),
                              (3, 'Loans'),
                            ])
                              Expanded(
                                child: Container(
                                  color: selected && index == 0
                                      ? p.accent
                                      : p.ink,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        [
                                          CupertinoIcons.house,
                                          CupertinoIcons.list_bullet,
                                          CupertinoIcons.chart_bar,
                                          CupertinoIcons.person_2,
                                        ][index],
                                        size: 14,
                                        color: p.surface,
                                      ),
                                      Text(
                                        label,
                                        style: textStyle(
                                          previewContext,
                                          size: 8,
                                          weight: index == 0
                                              ? FontWeight.w800
                                              : FontWeight.w500,
                                          color: p.surface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
