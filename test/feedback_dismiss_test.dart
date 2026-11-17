import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_entry/app_controller.dart';
import 'package:pocket_entry/data/storage.dart';
import 'package:pocket_entry/domain/adventure.dart';
import 'package:pocket_entry/domain/ledger.dart';
import 'package:pocket_entry/main.dart';

import 'ui_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);

  testWidgets('undo feedback can be swiped or dismissed accessibly by ID', (
    tester,
  ) async {
    final ledger = Ledger.empty().copy(
      preferences: const Preferences(
        visualStyle: VisualStyle.adventure,
        reduceMotion: true,
      ),
    );
    final app = AppController(store: MemoryLedgerStore(ledger))
      ..ledger = ledger;
    addTearDown(app.dispose);
    await tester.pumpWidget(
      PocketApp(controller: app, testHome: const SizedBox.shrink()),
    );
    await tester.pumpAndSettle();

    app.feedback = 'Entry saved';
    app.feedbackUndo = true;
    app.publish();
    await tester.pump();
    final firstId = app.feedbackId;
    expect(find.bySemanticsLabel('Undo last change'), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss feedback'), findsOneWidget);

    app.feedback = 'Newer message';
    app.feedbackUndo = true;
    app.publish();
    app.clearFeedback(firstId);
    await tester.pump();
    expect(app.feedback, 'Newer message');
    expect(find.text('Newer message'), findsOneWidget);

    final toast = find.byKey(ValueKey('feedback-${app.feedbackId}'));
    await tester.drag(toast, const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(app.feedback, isNull);
    expect(find.text('Newer message'), findsNothing);

    app.showAdventureReward(AdventureRewardKind.saved);
    await tester.pumpAndSettle();
    final reward = app.adventureReward!;
    final rewardCard = find.byKey(ValueKey('adventure-reward-${reward.id}'));
    expect(rewardCard, findsOneWidget);
    await tester.drag(rewardCard, const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(app.adventureReward, isNull);
    expect(tester.takeException(), isNull);
  });
}
