import 'package:cupertino_ui/cupertino_ui.dart';
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
import 'package:lichess_mobile/src/widgets/xiangqi_difficulty_tile.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/engine/fake_transport.dart';
import 'xiangqi_game_screen_test.dart' as game;

const practiceScreen = XiangqiGameScreen(
  initialSide: .red,
  initialDifficulty: .level4,
  initialTimeIncrement: TimeIncrement.infinite(),
  initialPracticeMode: true,
);

Future<void> tap(WidgetTester tester, String square) async {
  final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
  final rect = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(rect.size, showCoordinates: true);
  final drawn = Rect.fromCenter(
    center: rect.center,
    width: geometry.width,
    height: geometry.height,
  );
  await tester.tapAt(drawn.topLeft + geometry.centerOf(game.squareAt(square), board.orientation));
  await tester.pump();
}

Future<void> searchStarted(
  WidgetTester tester,
  FakeTransport transport, {
  bool scoring = false,
}) async {
  final commands = <String>[];
  var started = false;
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
    final fresh = transport.takeCommands();
    commands.addAll(fresh);
    // Reply only after isready was sent; the engine drops an early readyok.
    for (final command in fresh) {
      if (command == 'isready') transport.emit('readyok');
    }
    if (fresh.any((command) => scoring ? command == 'go depth 9' : command.startsWith('go '))) {
      started = true;
      break;
    }
  }
  expect(started, isTrue, reason: 'search never started; scoring=$scoring; commands=$commands');
}

Future<void> reply(WidgetTester tester, FakeTransport transport, String move) async {
  await searchStarted(tester, transport);
  transport.emit('bestmove $move');
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
  await tester.pump();
}

Future<void> score(WidgetTester tester, FakeTransport transport, int cp, String move) async {
  await searchStarted(tester, transport, scoring: true);
  transport.emit('info depth 9 score cp $cp pv $move');
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
  transport.emit('bestmove $move');
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
  await tester.pump();
}

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

  testWidgets('difficulty dragging never discards a live game before confirmation', (tester) async {
    final transport = await game.pumpGameScreen(tester, screen: practiceScreen);
    await tap(tester, 'h2');
    await tap(tester, 'e2');
    await score(tester, transport, 20, 'b2e2');
    await score(tester, transport, -30, 'h9g7');
    await reply(tester, transport, 'h9g7');
    final container = game.containerOf(tester);
    final controller = container.read(xiangqiGameControllerProvider.notifier);
    final before = container.read(xiangqiGameControllerProvider);
    final generation = controller.generation;
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    final slider = find.descendant(
      of: find.byType(XiangqiDifficultyTile),
      matching: find.byType(Slider),
    );
    final rect = tester.getRect(slider);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(rect.centerRight - const Offset(16, 0));
    await tester.pump();
    final preview = container.read(xiangqiGameControllerProvider);
    final previewGeneration = controller.generation;
    await gesture.up();
    await tester.pumpAndSettle();
    expect(preview.moves, before.moves);
    expect(previewGeneration, generation);
    final dialog = find.byType(YesNoDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('New game')), findsOneWidget);
    expect(container.read(xiangqiGameControllerProvider).moves, before.moves);
    await tester.tap(find.descendant(of: dialog, matching: find.text('Yes')));
    await tester.pump();
    final next = container.read(xiangqiGameControllerProvider);
    expect(next.moves, isEmpty);
    expect(next.practiceMode, isTrue);
    expect(next.timeIncrement, before.timeIncrement);
    expect(controller.generation, generation + 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final size in const [Size(480, 480), Size(1280, 720), Size(1920, 1080)]) {
    for (final side in XiangqiSide.values) {
      testWidgets('$side practice complete round stays coherent at $size', (tester) async {
        final transport = await game.pumpGameScreen(
          tester,
          surfaceSize: size,
          failOnOverflow: true,
          screen: XiangqiGameScreen(
            initialSide: side,
            initialDifficulty: .level4,
            initialTimeIncrement: const TimeIncrement.infinite(),
            initialPracticeMode: true,
          ),
        );
        if (side == .black) await reply(tester, transport, 'h2e2');
        await tap(tester, side == .red ? 'h2' : 'h9');
        await tap(tester, side == .red ? 'e2' : 'g7');
        final moved = game.containerOf(tester).read(xiangqiGameControllerProvider);
        expect(moved.moves.length, side == .red ? 1 : 2);
        expect(moved.isEvaluatingMove, isTrue);
        await score(tester, transport, 20, side == .red ? 'b2e2' : 'b9c7');
        final engineMove = side == .red ? 'h9g7' : 'h0g2';
        await score(tester, transport, -30, engineMove);
        expect(
          game.containerOf(tester).read(xiangqiGameControllerProvider).practiceComment,
          isNotNull,
        );
        final verdict = tester
            .widget<PracticeFeedbackCard>(find.byType(PracticeFeedbackCard))
            .feedback!
            .verdict;
        await reply(tester, transport, engineMove);
        expect(
          game.containerOf(tester).read(xiangqiGameControllerProvider).moves.length,
          side == .red ? 2 : 3,
        );
        expect(
          tester.widget<PracticeFeedbackCard>(find.byType(PracticeFeedbackCard)).feedback!.verdict,
          verdict,
        );
        final origin = side == .red ? 'a3' : 'a6';
        await tap(tester, origin);
        await tap(tester, side == .red ? 'a5' : 'a4');
        expect(
          tester.widget<PracticeFeedbackCard>(find.byType(PracticeFeedbackCard)).feedback!.verdict,
          verdict,
        );
        await tap(tester, origin);
        await tap(tester, side == .red ? 'a4' : 'a5');
        var card = tester.widget<PracticeFeedbackCard>(find.byType(PracticeFeedbackCard));
        expect(card.feedback, isNull);
        expect(card.isEvaluatingMove, isTrue);
        expect(card.previousFeedback!.verdict, verdict);
        await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
        await tester.pump();
        card = tester.widget<PracticeFeedbackCard>(find.byType(PracticeFeedbackCard));
        expect(card.isEvaluatingMove, isFalse);
        expect(card.feedback!.verdict, verdict);
        game
            .containerOf(tester)
            .read(xiangqiGameControllerProvider.notifier)
            .startNewGame(
              side: side,
              difficulty: .level4,
              timeIncrement: const TimeIncrement.infinite(),
              practiceMode: true,
            );
        await tester.pump();
        card = tester.widget<PracticeFeedbackCard>(find.byType(PracticeFeedbackCard));
        expect(card.feedback, isNull);
        expect(card.previousFeedback, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
    }
  }

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
