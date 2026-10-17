import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/more/more_tab_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
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

/// The move written [iccs], which is also how Pikafish writes one.
XiangqiMove moveAt(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// An engine whose transport is fake, and the transport itself so that a test can answer it.
///
/// The engine the app really starts is a 48 MB network written out of the bundle first, which a test
/// surface has nowhere to put: a fake transport is the smallest thing that answers the way Pikafish
/// does, and it is what the controller's tests and the game screen's use too.
({Engine engine, FakeTransport transport}) fakeXiangqiEngine() {
  final transport = FakeTransport(
    spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
    startupLines: kPikafishHandshake,
  );
  final engine = Engine(transport);
  addTearDown(engine.dispose);
  return (engine: engine, transport: transport);
}

/// The preferences that say whether the engine runs at all, written the way the app stores them.
Map<String, String> evaluationPreferences({required bool isEnabled}) => {
  PrefCategory.engineEvaluation.storageKey: jsonEncode(
    EngineEvaluationPrefState.defaults.copyWith(isEnabled: isEnabled).toJson(),
  ),
};

/// Pumps the analysis screen with an engine whose transport is fake, and hands that transport back.
///
/// The analysis's own engine provider is replaced rather than the factory behind it, exactly as the
/// controller's tests and the game screen's do.
///
/// The evaluation is on by default, which is also what the app's own default preference says: an
/// analysis board with no engine on it is a move list, and the tests that are about the board alone
/// turn it off so that the engine is out of the way.
///
/// [initialFen] is the position to open the board on, and only the test about opening on one passes
/// it: the screen sets it before starting the engine, which is what that test's command log is about.
Future<FakeTransport> pumpAnalysisScreen(
  WidgetTester tester, {
  Size surfaceSize = kTestSurfaceSize,
  bool engineEvaluation = true,
  String? initialFen,
}) async {
  final (:engine, :transport) = fakeXiangqiEngine();

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: XiangqiAnalysisScreen(initialFen: initialFen),
      overrides: {xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine)},
      defaultPreferences: evaluationPreferences(isEnabled: engineEvaluation),
      surfaceSize: surfaceSize,
    ),
  );
  await tester.pumpAndSettle();
  return transport;
}

/// Answers the `isready` the engine is waiting on, which is what lets it start searching.
///
/// Two pumps per line, because they do different things: the first delivers the line and flushes the
/// microtasks it sets off, and the second draws what those microtasks changed.
Future<void> startSearch(WidgetTester tester, FakeTransport transport) async {
  await tester.pump();
  transport.emit('readyok');
  await tester.pump();
  await tester.pump();
}

/// Lets the engine say what it has found, and lets the screen draw it.
Future<void> answer(WidgetTester tester, FakeTransport transport, String info) async {
  transport.emit(info);
  await tester.pump();
  await tester.pump();
}

/// Touches the point [name] names, in the orientation these tests look at the board from: red at
/// the bottom.
///
/// Aimed at the drawn board rather than at the box it is drawn in, which are not the same thing: the
/// board takes the largest board that fits its room and centres it, so there is a band of the box
/// beside it, and a touch aimed at the box's corner would land beside the board.
Future<void> tapSquare(WidgetTester tester, String name) async {
  final box = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(box.size, showCoordinates: true);
  final board = Rect.fromCenter(center: box.center, width: geometry.width, height: geometry.height);
  await tester.tapAt(board.topLeft + geometry.centerOf(squareAt(name), .red));
  await tester.pump();
}

/// The bar button under [icon], which is how the buttons are found: their labels are tooltips and
/// semantics, not text on screen, and their `onTap` is what says whether they are live.
BottomBarButton barButton(WidgetTester tester, IconData icon) => tester.widget<BottomBarButton>(
  find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton)),
);

/// The board as the screen has drawn it.
XiangqiBoard board(WidgetTester tester) => tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));

void main() {
  TestLichessBinding.ensureInitialized();

  // An analysis is deliberately remembered across a pop and a re-push, and the tests in this file
  // are separate visits to the screen in one process: without this, the line a test leaves behind is
  // the line the next one opens on. The chess analysis board's own tests clear its session for the
  // same reason.
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  group('XiangqiAnalysisScreen', () {
    testWidgets('opens on the starting position with nothing played', (tester) async {
      await pumpAnalysisScreen(tester);

      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(
        find.text('Xiangqi · Analysis board'),
        findsOneWidget,
        reason: 'the game it analyses, then what the screen is',
      );

      // Nothing has been played, so there is no line to show and nowhere to step through it.
      expect(find.byType(InlineMoveItem), findsNothing);
      expect(board(tester).position, XiangqiPosition.initial());
      expect(barButton(tester, CupertinoIcons.chevron_back).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
      expect(find.byIcon(Icons.restart_alt), findsOneWidget);
    });

    testWidgets('the engine is started on it, and says how deep it has got', (tester) async {
      final transport = await pumpAnalysisScreen(tester);

      // A fresh engine, so its first search is a new game, and it is asked to get ready before it
      // is given a position to search.
      expect(transport.takeCommands(), ['ucinewgame', 'isready']);
      await startSearch(tester, transport);

      expect(transport.takeCommands(), [
        'setoption name MultiPV value 3',
        'position fen ${XiangqiPosition.initial().toFen()}',
        'go infinite',
      ]);

      expect(find.text('Depth 12'), findsNothing, reason: 'nothing to report yet');

      await answer(
        tester,
        transport,
        'info depth 12 multipv 1 score cp 42 nodes 1000 time 100 pv h2e2 h9g7',
      );

      expect(find.text('Depth 12'), findsOneWidget);
      expect(
        find.widgetWithText(XiangqiEvalGauge, '+0.4'),
        findsOneWidget,
        reason: "red's score, to one decimal, on the bar beside the board",
      );
      expect(find.text('1. 炮二平五 马8进7'), findsOneWidget);
      expect(board(tester).arrows.single.move, moveAt('h2e2'));
    });

    testWidgets('the engine says where the game stands on the bar beside the board', (
      tester,
    ) async {
      final transport = await pumpAnalysisScreen(tester);

      // A search that has said nothing yet is drawn level rather than left out: the engine is about
      // to answer, and a bar that came and went would flicker.
      final fresh = tester.widget<XiangqiEvalGauge>(find.byType(XiangqiEvalGauge));
      expect(fresh.redWinProbability, 0.5);
      expect(fresh.evaluation, isNull);
      expect(fresh.orientation, XiangqiSide.red, reason: 'red is at the bottom of the board');

      await startSearch(tester, transport);
      await answer(
        tester,
        transport,
        'info depth 9 multipv 1 score cp 300 nodes 100 time 10 pv h2e2',
      );

      final gauge = tester.widget<XiangqiEvalGauge>(find.byType(XiangqiEvalGauge));
      expect(gauge.redWinProbability, greaterThan(0.5));
      expect(find.widgetWithText(XiangqiEvalGauge, '+3.0'), findsOneWidget);
    });

    testWidgets('a mate is written as a mate count, both ways round', (tester) async {
      final transport = await pumpAnalysisScreen(tester);
      await startSearch(tester, transport);

      await answer(
        tester,
        transport,
        'info depth 20 multipv 1 score mate 3 nodes 100 time 10 pv h2e2',
      );
      expect(find.widgetWithText(XiangqiEvalGauge, 'M3'), findsOneWidget);
      expect(find.text('+3.0'), findsNothing, reason: 'a mate count is not a score in pawns');
    });

    testWidgets('there is no bar and no engine when the evaluation is off', (tester) async {
      final transport = await pumpAnalysisScreen(tester, engineEvaluation: false);

      expect(find.byType(XiangqiEvalGauge), findsNothing);
      expect(transport.takeCommands(), isEmpty, reason: 'the engine is not started at all');

      // The board is still the board: an analysis board with the engine off is a move list.
      expect(find.byType(XiangqiBoard), findsOneWidget);
      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      expect(find.text('炮二平五'), findsOneWidget);
      expect(transport.takeCommands(), isEmpty);
    });

    testWidgets("the move list is the line of play, in the game's own notation", (tester) async {
      await pumpAnalysisScreen(tester, engineEvaluation: false);

      await tapSquare(tester, 'h2');
      expect(board(tester).selected, squareAt('h2'), reason: 'the piece is picked up');
      await tapSquare(tester, 'e2');

      expect(find.text('炮二平五'), findsOneWidget);
      expect(board(tester).lastMove, moveAt('h2e2'));
      expect(board(tester).selected, isNull);

      await tapSquare(tester, 'h9');
      await tapSquare(tester, 'g7');
      expect(find.text('马8进7'), findsOneWidget);
    });

    testWidgets('the bar steps back and forward through the line', (tester) async {
      await pumpAnalysisScreen(tester, engineEvaluation: false);
      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      await tapSquare(tester, 'h9');
      await tapSquare(tester, 'g7');

      final afterBothMoves = board(tester).position;
      expect(barButton(tester, CupertinoIcons.chevron_back).onTap, isNotNull);
      expect(
        barButton(tester, CupertinoIcons.chevron_forward).onTap,
        isNull,
        reason: 'the board is at the end of the line',
      );

      await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
      await tester.pump();

      expect(find.byIcon(CupertinoIcons.chevron_forward), findsOneWidget);
      expect(board(tester).lastMove, moveAt('h2e2'), reason: 'the move that led to the position');
      expect(board(tester).position, isNot(afterBothMoves));

      await tester.tap(find.byIcon(CupertinoIcons.chevron_forward));
      await tester.pump();

      expect(board(tester).position, afterBothMoves);
      expect(barButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
    });

    testWidgets('a move in the list puts the board back on it', (tester) async {
      await pumpAnalysisScreen(tester, engineEvaluation: false);
      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      await tapSquare(tester, 'h9');
      await tapSquare(tester, 'g7');
      expect(find.byType(InlineMoveItem), findsNWidgets(2));
      final afterBothMoves = board(tester).position;

      // The list counts the way a scoresheet does — the first move of the line is move 1 — and its
      // counting is in positions rather than in moves, which is what the shared list widget's own
      // index means: tapping a move goes to the position that move made.
      await tester.tap(find.text('炮二平五'));
      await tester.pump();

      expect(board(tester).lastMove, moveAt('h2e2'), reason: 'the move that made the position');
      expect(board(tester).position, isNot(afterBothMoves));
      expect(
        barButton(tester, CupertinoIcons.chevron_forward).onTap,
        isNotNull,
        reason: 'the board is not at the end of the line any more',
      );
    });

    testWidgets('playing a move while looking back at the line drops what followed it', (
      tester,
    ) async {
      await pumpAnalysisScreen(tester, engineEvaluation: false);
      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      await tapSquare(tester, 'h9');
      await tapSquare(tester, 'g7');

      await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
      await tester.pump();

      // Anything else from here is the new continuation of the line, and the old one is gone —
      // the same thing playing a move means on any analysis board.
      await tapSquare(tester, 'g6');
      await tapSquare(tester, 'g5');

      expect(find.text('卒7进1'), findsOneWidget);
      expect(
        find.text('马8进7'),
        findsNothing,
        reason: 'the move that followed the one stepped back to is no longer in the line',
      );
      expect(barButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
    });

    testWidgets('an engine line is shown as a score and the moves it expects', (tester) async {
      final transport = await pumpAnalysisScreen(tester);
      await startSearch(tester, transport);

      await answer(
        tester,
        transport,
        'info depth 14 multipv 1 score cp 120 nodes 1000 time 100 pv h2e2 h9g7 b0c2',
      );

      expect(
        find.widgetWithText(InkWell, '+1.2'),
        findsOneWidget,
        reason: 'the score is on the badge of the line',
      );
      expect(find.text('1. 炮二平五 马8进7 2. 马八进七'), findsOneWidget);

      // Tapping a line plays the move the engine would play, which is the fastest way to see what
      // the engine is talking about.
      await tester.tap(find.text('1. 炮二平五 马8进7 2. 马八进七'));
      await tester.pump();

      expect(board(tester).lastMove, moveAt('h2e2'));
      expect(find.text('炮二平五'), findsOneWidget);
    });

    testWidgets('the engine is asked for as many lines as the player has asked to see', (
      tester,
    ) async {
      final transport = await pumpAnalysisScreen(tester);
      await startSearch(tester, transport);

      await answer(tester, transport, 'info depth 8 multipv 1 score cp 10 nodes 10 time 1 pv h2e2');
      await answer(
        tester,
        transport,
        'info depth 8 multipv 2 score cp -40 nodes 10 time 1 pv b0c2',
      );

      expect(find.widgetWithText(InkWell, '+0.1'), findsOneWidget);
      expect(find.widgetWithText(InkWell, '-0.4'), findsOneWidget);
      expect(
        find.text('1. 马八进七'),
        findsOneWidget,
        reason:
            'each line is numbered from the position it was searched from, not from the one above',
      );
      expect(
        find.byType(BottomBarButton),
        findsNWidgets(4),
        reason: 'the lines are not buttons; the bar is its own row',
      );
    });

    testWidgets('the engine button turns the evaluation off and on again', (tester) async {
      final transport = await pumpAnalysisScreen(tester);
      await startSearch(tester, transport);

      expect(find.byType(XiangqiEvalGauge), findsOneWidget);

      await tester.tap(find.byIcon(Icons.memory));
      await tester.pumpAndSettle();

      expect(find.byType(XiangqiEvalGauge), findsNothing);
      expect(transport.takeCommands(), contains('stop'));

      await tester.tap(find.byIcon(Icons.memory));
      await tester.pumpAndSettle();

      expect(find.byType(XiangqiEvalGauge), findsOneWidget);
      expect(transport.takeCommands(), isNotEmpty, reason: 'the engine is started again');
    });

    testWidgets('flipping turns the board and the bar around together', (tester) async {
      await pumpAnalysisScreen(tester);

      expect(board(tester).orientation, XiangqiSide.red);

      await tester.tap(find.byIcon(CupertinoIcons.arrow_2_squarepath));
      await tester.pump();

      expect(board(tester).orientation, XiangqiSide.black);
      expect(
        tester.widget<XiangqiEvalGauge>(find.byType(XiangqiEvalGauge)).orientation,
        XiangqiSide.black,
      );
    });

    testWidgets('reset puts the board back and throws the line away', (tester) async {
      await pumpAnalysisScreen(tester, engineEvaluation: false);
      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      expect(find.byType(InlineMoveItem), findsOneWidget);
      expect(find.text('炮二平五'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.restart_alt));
      await tester.pump();

      expect(find.byType(InlineMoveItem), findsNothing);
      expect(board(tester).position, XiangqiPosition.initial());
      expect(barButton(tester, CupertinoIcons.chevron_back).onTap, isNull);
    });

    testWidgets('a screen opened on a position analyses that position', (tester) async {
      // The standard arrangement, black to move — a well formed position that is not the opening, and
      // not the one the screen would otherwise open on.
      final start = XiangqiPosition.fromFen(
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1',
      );
      final transport = await pumpAnalysisScreen(tester, initialFen: start.toFen());

      // The board is the position handed over and not the opening the screen first opened on: the
      // position is set before the engine is started, so there is no search of the opening for the
      // engine to be stopped and restarted on — the log below has one position in it, not two.
      expect(board(tester).position.toFen(), start.toFen());

      // A fresh engine, so its first search is a new game, and it is asked to get ready before it is
      // given the position to search.
      expect(transport.takeCommands(), ['ucinewgame', 'isready']);
      await startSearch(tester, transport);

      expect(transport.takeCommands(), [
        'setoption name MultiPV value 3',
        'position fen ${start.toFen()}',
        'go infinite',
      ]);
    });
  });

  group('the Analysis row on the More tab', () {
    /// Opens the More tab, with the engine settings a build has, and nothing running.
    ///
    /// The evaluation is off so that the board this opens is a board and no more: what is under test
    /// here is the row and the picker it opens, not the engine behind them.
    Future<void> pumpMoreTab(
      WidgetTester tester, {
      EngineAvailability availability = EngineAvailability.phone,
    }) async {
      final (:engine, transport: _) = fakeXiangqiEngine();
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const MoreTabScreen(),
          overrides: {
            engineAvailabilityProvider: engineAvailabilityProvider.overrideWithValue(availability),
            xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine),
          },
          defaultPreferences: evaluationPreferences(isEnabled: false),
        ),
      );
    }

    testWidgets('offers xiangqi beside chess, and the xiangqi one opens this screen', (
      tester,
    ) async {
      await pumpMoreTab(tester);

      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();

      // One row, two games: which of them is analysed is a question the row asks rather than a row
      // each, and it is asked with the same picker the play menu asks its own questions with.
      expect(find.text('Chess'), findsOneWidget);
      expect(find.text('Xiangqi'), findsOneWidget);

      await tester.tap(find.text('Xiangqi'));
      await tester.pumpAndSettle();

      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(
        find.text('Xiangqi · Analysis board'),
        findsOneWidget,
        reason: 'the screen the row opened, named the way the screen names itself',
      );
    });

    testWidgets('leaves xiangqi out of a build that has no Pikafish', (tester) async {
      await pumpMoreTab(tester, availability: EngineAvailability.none);

      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();

      // The gate sits on the choice rather than on a row of its own, so this build still analyses
      // chess — the one thing a build with no Pikafish can do.
      expect(find.text('Chess'), findsOneWidget);
      expect(find.text('Xiangqi'), findsNothing);
    });
  });
}
