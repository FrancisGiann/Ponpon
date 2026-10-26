import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';
import 'package:pocket_entry/ui/design.dart';
import 'package:pocket_entry/ui/screens.dart';

import 'ui_test.dart' show configure, fixture, loadFonts, synthetic;

void main() {
  setUpAll(loadFonts);

  testWidgets('Settings opens a dedicated Widgets gallery and returns', (
    tester,
  ) async {
    configure(tester, const Size(390, 844));
    final app = fixture(synthetic());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(
        controller: app,
        testHome: SettingsPage(app: app),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Widgets'), findsOneWidget);
    expect(find.text('Choose a widget'), findsNothing);
    await tester.ensureVisible(find.text('Widgets'));
    await tester.tap(find.text('Widgets'));
    await tester.pumpAndSettle();
    expect(find.byType(WidgetsPage), findsOneWidget);
    expect(find.text('Choose a widget'), findsOneWidget);
    expect(find.text('Compact home widget'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is PocketSwitch && w.label == 'Show balance on widget',
      ),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(WidgetsPage), findsNothing);
    expect(find.text('Widgets'), findsOneWidget);
  });

  for (final style in VisualStyle.values) {
    for (final theme in ['light', 'dark']) {
      testWidgets('Widgets gallery fits $style $theme with enlarged text', (
        tester,
      ) async {
        configure(tester, const Size(390, 844), scale: 1.4);
        final base = synthetic(theme: theme, populated: false);
        final app = fixture(
          base.copy(preferences: base.preferences.copy(visualStyle: style)),
        );
        addTearDown(app.dispose);
        await tester.pumpWidget(
          PocketApp(
            controller: app,
            testHome: WidgetsPage(app: app),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final title in [
          'Compact home widget',
          'Balance home widget',
          'Income & expense widget',
          'Wallet overview widget',
          'Wide balance & categories widget',
          'Home-screen widget',
        ]) {
          await tester.scrollUntilVisible(
            find.text(title),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
