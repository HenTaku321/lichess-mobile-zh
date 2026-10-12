import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';

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

/// The move written [iccs], which is also how Pikafish writes one.
XiangqiMove moveAt(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// Pumps the game screen with an engine whose transport is fake, and hands that transport back.
///
/// The game's own engine provider is replaced rather than the factory behind it, exactly as the
/// controller's tests do it: an [Engine] over a [FakeTransport] is the smallest thing that answers
/// the way Pikafish does, so the handshake, the option hygiene, the commands and the `bestmove`
/// parsing are all the real ones and only the bytes in and out are not. It is also what the game
/// needs to be testable at all — the engine it really starts is a 48 MB network written out of the
/// bundle first, which a test surface has nowhere to put.
Future<FakeTransport> pumpGameScreen(
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
      home: const XiangqiGameScreen(),
      overrides: {xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine)},
      surfaceSize: surfaceSize,
    ),
  );
  await tester.pumpAndSettle();
  return transport;
}

/// Answers the `isready` the engine is waiting on, which is what lets it start searching.
///
/// Pumped rather than awaited on a real clock: a widget test's body runs in fake time, so anything
/// that waits on a timer would wait for a clock nothing is advancing. Two pumps per line, because
/// they do different things — the first delivers the line and flushes the microtasks it sets off,
/// and the second draws what those microtasks changed. One pump is not enough: the frame that would
/// carry the change is only scheduled as the first one ends, so a single pump leaves the tree
/// showing the state before it.
Future<void> startSearch(WidgetTester tester, FakeTransport transport) async {
  await tester.pump();
  transport.emit('readyok');
  await tester.pump();
  await tester.pump();
}

/// Lets the engine reach its `bestmove`, as a real one does once it is asked to search.
Future<void> answer(WidgetTester tester, FakeTransport transport, String iccs) async {
  await startSearch(tester, transport);
  transport.emit('bestmove $iccs');
  await tester.pump();
  await tester.pump();
}

/// Touches the point [name] names, in the orientation these tests play from: red at the bottom.
///
/// Aimed at the drawn board rather than at the box it is drawn in, which are not the same thing: the
/// board takes the largest board that fits its room and centres it, so on a phone-shaped surface —
/// taller than the board's own 9:10 — there is a band of the box above and below the board, and a
/// touch aimed at the box's top-left corner would land beside it.
Future<void> tapSquare(WidgetTester tester, String name) async {
  final box = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(box.size);
  final board = Rect.fromCenter(center: box.center, width: geometry.width, height: geometry.height);
  await tester.tapAt(board.topLeft + geometry.centerOf(squareAt(name), .red));
  await tester.pump();
}

/// The bar button under [icon], which is how the buttons are found: their labels are tooltips and
/// semantics, not text on screen, and their `onTap` is what says whether they are live.
BottomBarButton barButton(WidgetTester tester, IconData icon) => tester.widget<BottomBarButton>(
  find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton)),
);

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiGameScreen', () {
    testWidgets('opens on a game the player can start at once', (tester) async {
      await pumpGameScreen(tester);

      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(find.text('Your turn'), findsOneWidget);

      // Red is the side that moves first, so the game is the player's and nothing is asked of the
      // engine until they have moved — which is what a takeback with nothing to take back means.
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.flag).onTap, isNotNull);
      expect(find.text('Computer thinking ...'), findsNothing);
    });

    testWidgets('the player moves and the computer answers', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tapSquare(tester, 'h2');
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).selected, squareAt('h2'));

      await tapSquare(tester, 'e2');
      expect(find.text('Computer thinking ...'), findsOneWidget);

      await answer(tester, transport, 'h9g7');

      expect(find.text('Your turn'), findsOneWidget);
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).lastMove, moveAt('h9g7'));
      // Both sides have moved, so there is something for the player to take back.
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNotNull);
    });

    testWidgets('picking a piece up and putting it down again is all it takes to move', (
      tester,
    ) async {
      await pumpGameScreen(tester);

      // A touch on the player's own piece picks it up and shows where it may go; a touch on a
      // square that is not one of those puts it back down.
      await tapSquare(tester, 'h2');
      final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
      expect(board.selected, squareAt('h2'));
      expect(board.moves, contains(moveAt('h2e2')));

      await tapSquare(tester, 'a9');
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).selected, isNull);
    });

    testWidgets('taking a move back hands the turn to the player again', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      await answer(tester, transport, 'h9g7');
      expect(find.text('Your turn'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
      await tester.pump();

      // The player's move and the answer to it both come off, so the game is theirs to play again.
      expect(find.text('Your turn'), findsOneWidget);
      final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
      expect(board.lastMove, isNull);
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNull);
    });

    testWidgets('resigning asks first, and then says how the game ended', (tester) async {
      await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.flag));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      // The result comes half a second after the game ends, so that the move which ended it is on
      // the board and read before the dialog comes down over it.
      await tester.pump();
      expect(find.byType(XiangqiGameResultDialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Game Over'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(XiangqiGameResultDialog),
          matching: find.text('Red resigned.'),
        ),
        findsOneWidget,
      );
      // A game that is over is a game with nothing left to do to it.
      expect(barButton(tester, CupertinoIcons.flag).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNull);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(XiangqiGameResultDialog), findsNothing);
      // What the game ended as stays on the line under the board.
      expect(find.text('Red resigned.'), findsOneWidget);
    });

    testWidgets('saying no to resigning leaves the game alone', (tester) async {
      await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.flag));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(find.text('Your turn'), findsOneWidget);
      expect(barButton(tester, CupertinoIcons.flag).onTap, isNotNull);
    });

    testWidgets('the new game sheet opens on the game in progress', (tester) async {
      await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();

      expect(find.text('Side'), findsOneWidget);
      expect(find.text('Red'), findsOneWidget);
      expect(find.text('Difficulty'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
    });

    testWidgets('taking black hands the opening move to the computer, and says so', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Red'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Black').last);
      await tester.pumpAndSettle();
      // 让先 is not a setting of its own — red moves first, so taking black is handing the opening
      // move over — and the sheet says so at the moment the choice is made.
      expect(find.text('Red moves first, so the computer opens the game.'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.text('Computer thinking ...'), findsOneWidget);
      await answer(tester, transport, 'h2e2');
      expect(find.text('Your turn'), findsOneWidget);

      // The board is drawn the other way up, so the engine's move is the one nearest the player.
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.black);
    });

    testWidgets('choosing a difficulty starts a game at that difficulty', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medium'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Easy').last);
      await tester.pumpAndSettle();
      expect(find.text('Easy'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      await startSearch(tester, transport);

      // What the difficulty is, is how long the computer may think: the three levels are three
      // search limits, because Pikafish has no strength setting to set. See [XiangqiDifficulty].
      expect(transport.takeCommands(), contains('go depth 3'));
    });
  });
}
