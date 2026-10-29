import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/widgets/practice_feedback_card.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import 'xiangqi_game_screen_test.dart' as game;

const practiceScreen = XiangqiGameScreen(
  initialSide: .red,
  initialDifficulty: .level4,
  initialTimeIncrement: TimeIncrement.infinite(),
  initialPracticeMode: true,
);

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(() {
    const channel = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      channel,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    addTearDown(() => messenger.setMockMessageHandler(channel, null));
  });

  final human = find.byWidgetPredicate((widget) => widget is XiangqiPlayerRow && !widget.isBot);

  testWidgets('a finished computer game does not offer a drag that cannot be played', (
    tester,
  ) async {
    await game.pumpGameScreen(tester, screen: practiceScreen);
    game.containerOf(tester).read(xiangqiGameControllerProvider.notifier).resign();
    await tester.pump();
    final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    expect(board.canStartDrag!(board.position.pieceAt(game.squareAt('a3'))!), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a reviewed computer position is not presented as draggable', (tester) async {
    final transport = await game.pumpGameScreen(
      tester,
      screen: const XiangqiGameScreen(
        initialSide: .red,
        initialDifficulty: .level4,
        initialTimeIncrement: TimeIncrement.infinite(),
      ),
    );
    await game.tapSquare(tester, 'h2');
    await game.tapSquare(tester, 'e2');
    await game.answer(tester, transport, 'h9g7');
    game.containerOf(tester).read(xiangqiGameControllerProvider.notifier).goTo(0);
    await tester.pump();
    final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    expect(board.canStartDrag!(board.position.pieceAt(game.squareAt('a3'))!), isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('flipping does not rename the anonymous human to the opposite side', (tester) async {
    await game.pumpGameScreen(tester, screen: practiceScreen);
    final name = tester.widget<XiangqiPlayerRow>(human).name;
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SwitchSettingTile, 'Flip board'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.black);
    expect(tester.widget<XiangqiPlayerRow>(human).name, name);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('practice feedback is before the actual human row, including after flipping', (
    tester,
  ) async {
    await game.pumpGameScreen(tester, screen: practiceScreen);
    expect(
      tester.getCenter(find.byType(PracticeFeedbackCard)).dy,
      lessThan(tester.getCenter(human).dy),
    );
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SwitchSettingTile, 'Flip board'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.black);
    expect(
      tester.getCenter(find.byType(PracticeFeedbackCard)).dy,
      lessThan(tester.getCenter(human).dy),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the player is told their move is being evaluated', (tester) async {
    await game.pumpGameScreen(tester, screen: practiceScreen);
    await game.tapSquare(tester, 'h2');
    await game.tapSquare(tester, 'e2');
    final label = tester.element(find.byType(XiangqiGameScreen)).l10n.evaluatingYourMove;
    expect(find.text(label), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('taking black starts the red opening clock, not the human clock', (tester) async {
    await game.pumpGameScreen(
      tester,
      screen: const XiangqiGameScreen(
        initialSide: .black,
        initialDifficulty: .level4,
        initialTimeIncrement: TimeIncrement(300, 0),
      ),
    );
    final clock = game.containerOf(tester).read(xiangqiClockProvider);
    expect(clock.activeClock, XiangqiSide.red);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
