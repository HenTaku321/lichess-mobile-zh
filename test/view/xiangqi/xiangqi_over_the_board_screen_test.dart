import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/engine/fake_transport.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The square named [name], which the tests below write the way a player would.
XiangqiSquare squareAt(String name) {
  final square = XiangqiSquare.parse(name);
  if (square == null) throw ArgumentError('Not a square: $name');
  return square;
}

/// Pumps the over-the-board screen and starts a game on the sheet it opens on.
///
/// The engine is overridden even though this screen never asks it anything, because the controller
/// it shares with the computer screen starts one on construction — see [XiangqiGameController.build]
/// — and the engine it really starts is a 48 MB network written out of the bundle first, which a
/// test surface has nowhere to put. A [FakeTransport] is enough to let it be built and torn down.
///
/// The screen opens on its setup sheet, so the game does not exist until the sheet's own button has
/// been pressed: every test below starts from a game on the screen's default time control, which is
/// the one thing the sheet is asked for here.
Future<FakeTransport> pumpOtbScreen(
  WidgetTester tester, {
  Size surfaceSize = kTestSurfaceSize,
}) async {
  final transport = FakeTransport(
    spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
    startupLines: kPikafishHandshake,
  );
  final engine = Engine(transport);
  addTearDown(engine.dispose);

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const XiangqiOverTheBoardScreen(),
      overrides: {xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine)},
      surfaceSize: surfaceSize,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();

  return transport;
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(XiangqiOverTheBoardScreen)));

/// The clock drawn at the bottom of the board, or the one above it.
Clock clockAt(WidgetTester tester, String key) => tester.widget<Clock>(find.byKey(ValueKey(key)));

/// Touches the point [name] names, in the orientation the screen starts in: red at the bottom.
///
/// Aimed at the drawn board rather than at the box it is drawn in, which are not the same thing: the
/// board takes the largest board that fits its room and centres it, so on a phone-shaped surface —
/// taller than the board's own 10:11 — there is a band of the box above and below the board.
Future<void> tapSquare(WidgetTester tester, String name) async {
  final box = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(box.size, showCoordinates: true);
  final board = Rect.fromCenter(center: box.center, width: geometry.width, height: geometry.height);
  await tester.tapAt(board.topLeft + geometry.centerOf(squareAt(name), .red));
  await tester.pump();
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiOverTheBoardScreen', () {
    testWidgets("both sides move, and the moves are written in the game's own notation", (
      tester,
    ) async {
      final transport = await pumpOtbScreen(tester);

      // Red is drawn at the bottom, and red moves first.
      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      expect(find.text('炮二平五'), findsOneWidget);

      // And then black, from the top of the same board: the turn comes back to a person rather than
      // to an engine, which is the whole of what the over-the-board arrangement is.
      await tapSquare(tester, 'h9');
      await tapSquare(tester, 'g7');
      expect(find.text('马8进7'), findsOneWidget);

      final container = containerOf(tester);
      expect(container.read(xiangqiGameControllerProvider).moves.length, 2);
      expect(container.read(xiangqiGameControllerProvider).isEngineThinking, isFalse);
      // Nothing was ever searched for: there is no side here for a search to belong to.
      expect(transport.takeCommands().where((command) => command.startsWith('go ')), isEmpty);
    });

    testWidgets('the clock is drawn for both sides, and a move hands it over', (tester) async {
      await pumpOtbScreen(tester);

      expect(find.byKey(const ValueKey('bottomClock')), findsOneWidget);
      expect(find.byKey(const ValueKey('topClock')), findsOneWidget);
      // Neither side's time is running until a move is made, which is the hand a clock over a board
      // starts on.
      expect(clockAt(tester, 'bottomClock').active, isFalse);
      expect(clockAt(tester, 'topClock').active, isFalse);

      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');

      // Red's move is what starts black's time, and the row that is drawn running is the row above
      // the board, because black is the side drawn there. Red is charged nothing for it: an
      // increment is paid for a move made with time already running, and nothing was running.
      expect(clockAt(tester, 'topClock').active, isTrue);
      expect(clockAt(tester, 'bottomClock').active, isFalse);
      expect(clockAt(tester, 'bottomClock').timeLeft, const Duration(seconds: 300));

      // Black's time is the one going, and it goes. The clock reads the system clock rather than the
      // frame clock, so the quarter of a second it loses is a real one — see the flag test below.
      sleep(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 150));

      expect(clockAt(tester, 'topClock').timeLeft, lessThan(const Duration(seconds: 300)));
    });

    testWidgets('a clock that runs out ends the game, and says which side lost', (tester) async {
      await pumpOtbScreen(tester);
      final container = containerOf(tester);

      container.read(xiangqiClockProvider.notifier).setupClock(const TimeIncrement(1, 0));
      container.read(xiangqiClockProvider.notifier).resume(XiangqiSide.red);

      // The clock reads the system clock rather than the frame clock, so the time it is waiting to
      // lose is a real second: no amount of pumping would pass it, and the wait has to be slept
      // through exactly as the chess screen's own flag test does.
      sleep(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final state = container.read(xiangqiGameControllerProvider);
      expect(state.end, XiangqiGameEnd.timeout);
      // The side that lost is the side whose clock it was, recorded on the game rather than worked
      // out afterwards: by the time the flag is acted on the turn may already have moved on.
      expect(state.flaggedSide, XiangqiSide.red);
      expect(state.winner, XiangqiSide.black);

      expect(find.text('Game Over'), findsOneWidget);
      expect(find.text('Red ran out of time.'), findsOneWidget);
    });

    testWidgets('the board can be turned round, and the two rows turn with it', (tester) async {
      await pumpOtbScreen(tester);

      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.red);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flip board'));
      await tester.pumpAndSettle();

      // Turning the board round is a way of looking at the game and not a fact about it, so the
      // clocks follow the rows they belong to rather than being taken away and put back.
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.black);
      expect(find.byKey(const ValueKey('bottomClock')), findsOneWidget);
      expect(find.byKey(const ValueKey('topClock')), findsOneWidget);
    });

    testWidgets('an untimed game draws no clock and cannot be flagged', (tester) async {
      await pumpOtbScreen(tester);

      final container = containerOf(tester);
      container.read(xiangqiClockProvider.notifier).setupClock(const TimeIncrement.infinite());
      await tester.pumpAndSettle();

      expect(find.byType(Clock), findsNothing);

      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');

      // A clock with no time in it has no time to run out: the game is the game and nothing else
      // ends it. There is no pause button either, since there is nothing to pause.
      expect(container.read(xiangqiGameControllerProvider).isFinished, isFalse);
      expect(find.byIcon(CupertinoIcons.pause), findsNothing);
      expect(find.byIcon(CupertinoIcons.play), findsNothing);
    });
  });
}
