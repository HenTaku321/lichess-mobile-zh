import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart';
import 'package:lichess_mobile/src/widgets/practice_feedback_card.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

const feedback = PracticeFeedbackData(
  verdict: MoveVerdict.mistake,
  suggestion: 'Cannon to the middle',
  evalAfter: '+0.2',
);

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('a new game never reuses the previous game feedback while scoring', (tester) async {
    final frame = ValueNotifier<(PracticeFeedbackData?, bool)>((feedback, false));
    addTearDown(frame.dispose);
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        failOnOverflow: true,
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder(
              valueListenable: frame,
              builder: (context, value, child) => PracticeFeedbackCard(
                feedback: value.$1,
                isEvaluatingMove: value.$2,
                isPlayerTurn: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Mistake'), findsOneWidget);
    frame.value = (null, false);
    await tester.pump();
    expect(find.text('Mistake'), findsNothing);
    frame.value = (null, true);
    await tester.pump(const Duration(milliseconds: 301));
    expect(find.text('Mistake'), findsNothing);
  });

  testWidgets('the suggestion supports Tab and Enter activation', (tester) async {
    var activated = 0;
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        failOnOverflow: true,
        home: Scaffold(
          body: PracticeFeedbackCard(
            feedback: feedback,
            isEvaluatingMove: false,
            isPlayerTurn: true,
            onToggleSuggestion: () => activated++,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 1);
  });

  testWidgets('long suggestions at double text scale are not clipped or overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        failOnOverflow: true,
        home: const Scaffold(
          body: Center(
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SizedBox(
                width: 220,
                child: PracticeFeedbackCard(
                  feedback: PracticeFeedbackData(
                    verdict: MoveVerdict.mistake,
                    suggestion:
                        'A very long translated suggestion with several words that must wrap',
                    evalAfter: '-12.34',
                  ),
                  isEvaluatingMove: false,
                  isPlayerTurn: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(PracticeFeedbackCard));
    final suggestion = tester.getRect(find.textContaining('A very long', findRichText: true));
    expect(card.contains(suggestion.bottomRight), isTrue);
  });
}
