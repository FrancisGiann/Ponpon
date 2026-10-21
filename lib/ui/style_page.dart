part of 'screens.dart';

String visualStyleName(VisualStyle style) => switch (style) {
  VisualStyle.original => 'Original',
  VisualStyle.powderBlue => 'Powder Blue',
  VisualStyle.notebook => 'Notebook',
  VisualStyle.midnight => 'Midnight',
};

String visualStyleDescription(VisualStyle style) => switch (style) {
  VisualStyle.original => 'Warm neutrals, soft cards and familiar purple.',
  VisualStyle.powderBlue =>
    'Airy blue surfaces, quiet cloud details and generous curves.',
  VisualStyle.notebook => 'Warm paper, fine rules and classic headings.',
  VisualStyle.midnight =>
    'Deep navy, crisp edges and luminous blue details. Always dark.',
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
              child: Surface(
                detailBand:
                    style == VisualStyle.powderBlue ||
                    style == VisualStyle.notebook,
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
                      style: textStyle(context, size: 14, color: p.secondary),
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
                        borderRadius: BorderRadius.circular(p.controlRadius),
                      ),
                      child: Text(
                        'Food · Today',
                        style: textStyle(context, size: 14, color: p.accent),
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
