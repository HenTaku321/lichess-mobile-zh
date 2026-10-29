import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

import '../../test_container.dart';
import '../engine/fake_transport.dart';

/// The move written [iccs], which is also how Pikafish writes one.
XiangqiMove move(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// The moves written [iccs].
IList<XiangqiMove> moves(List<String> iccs) => [for (final iccs in iccs) move(iccs)].lock;

/// The initial position with black to move, for the sign tests: a score the engine reports here is
/// black's, and has to be read as red's the other way round.
const _blackToMoveFen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1';

/// An analysis: the container it lives in, the engine behind it, and what it has asked the view to
/// say.
class AnalysisHarness(
  final ProviderContainer container,
  final FakeTransport transport,
  final ProviderSubscription<XiangqiAnalysisState> watched,
) {
  final List<UiEvent> events = [];

  XiangqiAnalysisController get notifier =>
      container.read(xiangqiAnalysisControllerProvider.notifier);

  XiangqiAnalysisState get state => container.read(xiangqiAnalysisControllerProvider);
}

/// An analysis on a real [Engine] whose transport is fake, with the engine already up.
///
/// The same harness the hint's own tests use, and for the same reason: what is under test is the
/// analysis, and an [Engine] over a [FakeTransport] is the smallest thing that answers the way
/// Pikafish does — the handshake, the option hygiene, the commands, the `info` parsing are all the
/// real ones, and only the bytes in and out are not.
Future<AnalysisHarness> makeHarness() async {
  final transport = FakeTransport(
    spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
    startupLines: kPikafishHandshake,
  );
  final engine = Engine(transport);
  addTearDown(engine.dispose);

  final container = await makeContainer(
    overrides: {xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine)},
  );

  // The analysis is autoDispose and a bare `read` is not a watcher, so without something holding it
  // it would be thrown away between two lines of a test.
  final watched = container.listen(xiangqiAnalysisControllerProvider, (_, _) {});
  addTearDown(watched.close);

  final harness = AnalysisHarness(container, transport, watched);
  final events = container.read(uiEventBusProvider).stream.listen(harness.events.add);
  addTearDown(events.cancel);

  // The engine's handshake is read before the first search is handed over.
  await pumpEventQueue();
  return harness;
}

/// The analysis with its engine started and its first search in flight on the initial position.
Future<AnalysisHarness> makeAnalysingHarness() async {
  final harness = await makeHarness();
  harness.notifier.startEngine();
  await pumpEventQueue();
  harness.transport.emit('readyok');
  await pumpEventQueue();
  return harness;
}

/// What the engine is told to do to start a search: the options this search needs that the last one
/// did not have, then the position, then the search itself.
List<String> startOfSearch(XiangqiPosition position) => [
  'setoption name MultiPV value 3',
  'position fen ${position.toFen()}',
  'go infinite',
];

void main() {
  // The saved session is a module-level variable, so it outlives a container and would leak
  // between tests if it were left where the last one put it.
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  group('the state it starts from', () {
    test('a fresh analysis is the starting position with nothing on it', () async {
      final harness = await makeHarness();
      final state = harness.state;

      expect(state.positions, [XiangqiPosition.initial()]);
      expect(state.moves, isEmpty);
      expect(state.cursor, 0);
      expect(state.position, XiangqiPosition.initial());
      expect(state.lastMove, isNull);
      expect(state.selected, isNull);
      expect(state.selectedMoves, isEmpty);
      expect(state.lines, isEmpty);
      expect(state.bestLine, isNull);
      expect(state.evaluation, isNull);
      expect(state.depth, 0);
      expect(state.isEngineRunning, isFalse);
      expect(state.isFinished, isFalse);
      expect(state.canGoBack, isFalse);
      expect(state.canGoForward, isFalse);
      expect(harness.transport.takeCommands(), isEmpty);
    });
  });

  group('building a line', () {
    test('playing a move appends it and puts the board after it', () async {
      final harness = await makeHarness();

      harness.notifier.play(move('h2e2'));

      final state = harness.state;
      expect(state.moves, moves(['h2e2']));
      expect(state.positions, hasLength(2));
      expect(state.cursor, 1);
      expect(state.lastMove, move('h2e2'));
      expect(state.position, rules.play(XiangqiPosition.initial(), move('h2e2')));
      expect(state.canGoBack, isTrue);
      expect(state.canGoForward, isFalse);
      expect(state.selected, isNull);
    });

    test('a move this position cannot play is refused', () async {
      final harness = await makeHarness();

      expect(
        () => harness.notifier.play(move('a0a9')),
        throwsA(isA<rules.XiangqiIllegalMoveException>()),
      );
      expect(harness.state.moves, isEmpty, reason: 'a refused move leaves the line alone');
    });

    test('two taps pick a piece up and put it down', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;

      notifier.tapSquare(XiangqiSquare.parse('h2')!);
      expect(harness.state.selected, XiangqiSquare.parse('h2'));
      expect(
        harness.state.selectedMoves.map((m) => m.iccs),
        contains('h2e2'),
        reason: 'the board offers every move the cannon has',
      );

      notifier.tapSquare(XiangqiSquare.parse('e2')!);
      expect(harness.state.selected, isNull);
      expect(harness.state.moves, moves(['h2e2']));
    });

    test('a tap that is not a move puts the piece back down', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;

      // A piece of one's own with nowhere to go: the black general, on red's turn.
      notifier.tapSquare(XiangqiSquare.parse('e9')!);
      expect(harness.state.selected, isNull);
      expect(harness.state.moves, isEmpty);

      // An empty square, with nothing picked up.
      notifier.tapSquare(XiangqiSquare.parse('e5')!);
      expect(harness.state.selected, isNull);

      // The same piece twice: the second tap is not one of the moves it has, so it lets go.
      notifier.tapSquare(XiangqiSquare.parse('h2')!);
      expect(harness.state.selected, XiangqiSquare.parse('h2'));
      // A square the picked-up piece cannot go to: no move is played and the piece goes back down,
      // which is what a touch there does on the game screen too.
      notifier.tapSquare(XiangqiSquare.parse('e5')!);
      expect(harness.state.selected, isNull);
      expect(harness.state.moves, isEmpty);
    });

    test('taking a move back steps the line back, and does nothing at the start', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;

      notifier.play(move('h2e2'));
      notifier.play(move('h9g7'));
      expect(harness.state.moves, hasLength(2));

      notifier.retract();
      expect(harness.state.moves, moves(['h2e2']));
      expect(harness.state.positions, hasLength(2));
      expect(harness.state.cursor, 1);
      expect(harness.state.position, rules.play(XiangqiPosition.initial(), move('h2e2')));

      notifier.retract();
      expect(harness.state.moves, isEmpty);
      expect(harness.state.position, XiangqiPosition.initial());

      // Nothing before the first move: a game that has not begun is already at the start of its
      // line.
      notifier.retract();
      expect(harness.state.moves, isEmpty);
      expect(harness.state.cursor, 0);
    });
  });

  group('stepping through the line', () {
    test('the cursor walks the line and stops at both ends', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;
      notifier.play(move('h2e2'));
      notifier.play(move('h9g7'));
      notifier.play(move('b0c2'));

      expect(harness.state.cursor, 3);

      notifier.goBack();
      expect(harness.state.cursor, 2);
      expect(harness.state.position, harness.state.positions[2]);
      expect(
        harness.state.lastMove,
        move('h9g7'),
        reason: 'the move that led to the position on the board',
      );

      notifier.goForward();
      expect(harness.state.cursor, 3);

      // Past the end: the board stays where it is rather than the line growing.
      notifier.goForward();
      expect(harness.state.cursor, 3);
      expect(harness.state.canGoForward, isFalse);

      // Before the start.
      notifier.goTo(0);
      expect(harness.state.cursor, 0);
      expect(harness.state.lastMove, isNull);
      notifier.goBack();
      expect(harness.state.cursor, 0);
      expect(harness.state.canGoBack, isFalse);
    });

    test('a cursor past either end is pulled back to the line', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;
      notifier.play(move('h2e2'));
      notifier.play(move('h9g7'));

      notifier.goTo(99);
      expect(harness.state.cursor, 2);
      notifier.goTo(-3);
      expect(harness.state.cursor, 0);
    });

    test('a move played after stepping back is the new line, and the old one is dropped', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;
      notifier.play(move('h2e2'));
      notifier.play(move('h9g7'));
      notifier.play(move('b0c2'));

      notifier.goTo(1);
      notifier.play(move('g6g5'));

      expect(harness.state.moves, moves(['h2e2', 'g6g5']));
      expect(harness.state.cursor, 2);
      expect(harness.state.positions, hasLength(3));
      expect(harness.state.canGoForward, isFalse);
    });
  });

  group('setting a position up', () {
    test('a FEN becomes the start of a new line', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;
      notifier.play(move('h2e2'));
      notifier.play(move('h9g7'));

      notifier.setFen(_blackToMoveFen);

      final state = harness.state;
      expect(state.moves, isEmpty);
      expect(state.cursor, 0);
      expect(state.position, XiangqiPosition.fromFen(_blackToMoveFen));
      expect(state.position.turn, XiangqiSide.black);
      expect(state.lastMove, isNull);
      expect(state.positions, hasLength(1));
    });

    test('a string that is not a position is refused', () async {
      final harness = await makeHarness();

      expect(() => harness.notifier.setFen('not a fen'), throwsFormatException);
      expect(harness.state.position, XiangqiPosition.initial());
    });

    test('reset puts the starting position back and throws the line away', () async {
      final harness = await makeHarness();
      final notifier = harness.notifier;
      notifier.setFen(_blackToMoveFen);
      notifier.play(move('h9g7'));

      notifier.reset();

      expect(harness.state.moves, isEmpty);
      expect(harness.state.position, XiangqiPosition.initial());
      expect(harness.state.positions, hasLength(1));
    });
  });

  group('the engine', () {
    test('starting it hands the position over as a FEN and asks for three lines', () async {
      final harness = await makeHarness();

      harness.notifier.startEngine();
      expect(harness.state.isEngineRunning, isTrue);
      await pumpEventQueue();

      // The engine's first search is always a new game, and it is asked to get ready before it is
      // given anything to search.
      expect(harness.transport.takeCommands(), ['ucinewgame', 'isready']);

      harness.transport.emit('readyok');
      await pumpEventQueue();
      expect(harness.transport.takeCommands(), startOfSearch(XiangqiPosition.initial()));
    });

    test(
      'it is asked for the widest set of lines the setting allows, and runs unbounded',
      () async {
        final harness = await makeAnalysingHarness();

        expect(
          harness.transport.takeCommands(),
          contains('setoption name MultiPV value 3'),
          reason:
              'three is the most the app lets a player show, so the search is never started over',
        );
        expect(kXiangqiAnalysisLines, 3);
      },
    );

    test('an info line becomes a line of the analysis', () async {
      final harness = await makeAnalysingHarness();

      harness.transport.emit(
        'info depth 12 seldepth 20 multipv 1 score cp 34 nodes 1000 nps 5 time 100 pv h2e2 h9g7',
      );
      await pumpEventQueue();

      expect(harness.state.lines, hasLength(1));
      final line = harness.state.lines.first;
      expect(line.depth, 12);
      expect(line.evaluation, const XiangqiEvaluation(cp: 34));
      expect(line.moves, moves(['h2e2', 'h9g7']));
      expect(harness.state.depth, 12);
      expect(harness.state.evaluation, const XiangqiEvaluation(cp: 34));
      expect(harness.state.bestLine, line);
    });

    test('the lines are ordered best first, however the engine reports them', () async {
      final harness = await makeAnalysingHarness();

      // The engine reports its lines one at a time and not in order: the first `info` of a new
      // depth is not necessarily multipv 1's.
      harness.transport.emit('info depth 10 multipv 3 score cp -80 nodes 30 time 3 pv a0a1');
      harness.transport.emit('info depth 10 multipv 1 score cp 25 nodes 30 time 3 pv h2e2');
      harness.transport.emit('info depth 10 multipv 2 score cp 10 nodes 30 time 3 pv b0c2');
      await pumpEventQueue();

      expect(harness.state.lines.map((line) => line.evaluation.cp), [
        25,
        10,
        -80,
      ], reason: 'the best line is the first line, whichever order it arrived in');
      expect(harness.state.bestLine?.evaluation, const XiangqiEvaluation(cp: 25));
    });

    test('a deeper reading of one line replaces the shallower one', () async {
      final harness = await makeAnalysingHarness();

      harness.transport.emit('info depth 5 multipv 1 score cp 12 nodes 50 time 5 pv h2e2');
      await pumpEventQueue();
      expect(harness.state.depth, 5);

      harness.transport.emit('info depth 18 multipv 1 score cp 40 nodes 5000 time 50 pv h2e2 h9g7');
      await pumpEventQueue();

      expect(harness.state.lines, hasLength(1), reason: 'not a second line beside the first');
      expect(harness.state.depth, 18);
      expect(harness.state.lines.first.moves, moves(['h2e2', 'h9g7']));
    });

    test("the score is red's, whatever side is to move", () async {
      final harness = await makeAnalysingHarness();
      harness.notifier.setFen(_blackToMoveFen);
      await pumpEventQueue();
      harness.transport.emit('bestmove h9g7');
      await pumpEventQueue();

      // The engine says the side to move — black — is 150 up. That is red being 150 down.
      harness.transport.emit('info depth 9 multipv 1 score cp 150 nodes 500 time 10 pv h9g7');
      await pumpEventQueue();

      expect(harness.state.evaluation?.cp, -150);
      expect(harness.state.evaluation!.redWinProbability, lessThan(0.5));
    });

    test('a mate score is a mate score, on the right side of the bar', () async {
      final harness = await makeAnalysingHarness();

      harness.transport.emit('info depth 20 multipv 1 score mate 3 nodes 500 time 10 pv h2e2');
      await pumpEventQueue();

      expect(harness.state.evaluation, const XiangqiEvaluation(mate: 3));
      expect(harness.state.evaluation!.redWinProbability, greaterThan(0.5));
    });

    test('a bound is not a score, where it is the search talking about itself', () async {
      final harness = await makeAnalysingHarness();

      // Multipv 1's `lowerbound` line is the search saying it has established the line is at least
      // this good — a fact about the search rather than a verdict on the position.
      harness.transport.emit(
        'info depth 4 multipv 1 score cp 20 lowerbound nodes 10 time 1 pv h2e2',
      );
      await pumpEventQueue();
      expect(harness.state.lines, isEmpty);

      // The lines under it are real scores for the lines they belong to, bounds or not.
      harness.transport.emit(
        'info depth 4 multipv 2 score cp 15 upperbound nodes 10 time 1 pv b0c2',
      );
      await pumpEventQueue();
      expect(harness.state.lines, hasLength(1));
      expect(harness.state.lines.first.evaluation, const XiangqiEvaluation(cp: 15));
    });

    test('a principal variation the board cannot play is kept to what can be played', () async {
      final harness = await makeAnalysingHarness();

      // Nothing about the position changes when it arrives: the sequence is what the engine
      // expects, and the analysis has no business refusing it or playing it.
      harness.transport.emit('info depth 8 multipv 1 score cp 5 nodes 10 time 1 pv h2e2 notamove');
      await pumpEventQueue();

      expect(harness.state.lines, hasLength(1));
      expect(harness.state.lines.first.moves, moves(['h2e2']));
      expect(harness.state.moves, isEmpty);
    });

    test('starting it twice is starting it once', () async {
      final harness = await makeAnalysingHarness();
      harness.transport.takeCommands();

      harness.notifier.startEngine();
      await pumpEventQueue();

      expect(harness.state.isEngineRunning, isTrue);
      expect(harness.transport.takeCommands(), isEmpty);
    });

    test('a move restarts the search on the position it makes', () async {
      final harness = await makeAnalysingHarness();
      harness.transport.takeCommands();

      harness.notifier.play(move('h2e2'));
      await pumpEventQueue();

      // The search in flight is stopped before the new one is handed over, and the engine is not
      // told a new game: it is the same analysis, further along.
      expect(harness.transport.takeCommands(), ['stop', 'isready']);

      harness.transport.emit('bestmove h2e2');
      await pumpEventQueue();

      final afterH2e2 = rules.play(XiangqiPosition.initial(), move('h2e2'));
      expect(harness.transport.takeCommands(), [
        'position fen ${afterH2e2.toFen()}',
        'go infinite',
      ]);
    });

    test('the lines of the position before the move do not outlive it', () async {
      final harness = await makeAnalysingHarness();
      harness.transport.emit('info depth 10 multipv 1 score cp 30 nodes 10 time 1 pv h2e2');
      await pumpEventQueue();
      expect(harness.state.lines, hasLength(1));

      harness.notifier.play(move('h2e2'));

      expect(
        harness.state.lines,
        isEmpty,
        reason: 'what the engine said was about a position that is no longer on the board',
      );
      expect(harness.state.evaluation, isNull);
      expect(harness.state.depth, 0);
    });

    test('stopping it keeps what it has already found', () async {
      final harness = await makeAnalysingHarness();
      harness.transport.emit('info depth 14 multipv 1 score cp 44 nodes 10 time 1 pv h2e2');
      await pumpEventQueue();
      harness.transport.takeCommands();

      harness.notifier.stopEngine();

      expect(harness.state.isEngineRunning, isFalse);
      expect(harness.transport.takeCommands(), ['stop']);
      expect(
        harness.state.lines,
        hasLength(1),
        reason: 'the lines are still about the position on the board',
      );
      expect(harness.state.evaluation, const XiangqiEvaluation(cp: 44));
    });

    test('an answer to a stopped search is dropped', () async {
      final harness = await makeAnalysingHarness();
      harness.transport.emit('info depth 14 multipv 1 score cp 44 nodes 10 time 1 pv h2e2');
      await pumpEventQueue();

      harness.notifier.stopEngine();
      // The engine still has a search in flight: it answers the `stop` with its `bestmove` a moment
      // later, and reports what it had found in the meantime.
      harness.transport.emit('info depth 22 multipv 1 score cp 900 nodes 10 time 1 pv h2e2 h9g7');
      await pumpEventQueue();

      expect(harness.state.depth, 14);
      expect(harness.state.evaluation, const XiangqiEvaluation(cp: 44));
    });

    test('stopping it when it is not running asks the engine for nothing', () async {
      final harness = await makeHarness();

      harness.notifier.stopEngine();

      expect(harness.state.isEngineRunning, isFalse);
      expect(harness.transport.takeCommands(), isEmpty);
    });

    test('a line built with the engine off leaves it off', () async {
      final harness = await makeHarness();

      harness.notifier.play(move('h2e2'));
      harness.notifier.goBack();

      expect(harness.state.isEngineRunning, isFalse);
      expect(harness.transport.takeCommands(), isEmpty);
    });

    test('an engine that cannot be started is reported, not thrown into the UI', () async {
      final container = ProviderContainer(
        overrides: [
          // An engine that cannot be started: the future the search awaits never has an engine in
          // it, only this failure. It is thrown as an [Error] on purpose — riverpod's retry policy
          // never retries one, so the search sees the failure at once instead of waiting out a
          // backoff, which is also how the app meets a missing engine.
          xiangqiEngineProvider.overrideWith((Ref ref) {
            throw StateError('no engine');
          }),
        ],
      );
      addTearDown(container.dispose);
      final events = <UiEvent>[];
      final subscription = container.read(uiEventBusProvider).stream.listen(events.add);
      addTearDown(subscription.cancel);
      final watched = container.listen(xiangqiAnalysisControllerProvider, (_, _) {});
      addTearDown(watched.close);

      container.read(xiangqiAnalysisControllerProvider.notifier).startEngine();
      await pumpEventQueue();

      final state = container.read(xiangqiAnalysisControllerProvider);
      expect(state.isEngineRunning, isFalse, reason: 'the search is not left looking like one');
      expect(state.lines, isEmpty);
      expect(events, [isA<ShowErrorEvent>()], reason: 'the player has to be told');
    });

    test('disposal stops the search on the shared engine', () async {
      // Standalone rather than through makeHarness: this test disposes the container itself, and a
      // second dispose from a tear-down would be the thing under test's noise rather than its point.
      final transport = FakeTransport(
        spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
        startupLines: kPikafishHandshake,
      );
      final engine = Engine(transport);
      addTearDown(engine.dispose);
      final container = ProviderContainer(
        overrides: [xiangqiEngineProvider.overrideWith((Ref ref) => engine)],
      );
      container.listen(xiangqiAnalysisControllerProvider, (_, _) {});

      container.read(xiangqiAnalysisControllerProvider.notifier).startEngine();
      await pumpEventQueue();
      expect(transport.takeCommands(), ['ucinewgame', 'isready']);
      transport.emit('readyok');
      await pumpEventQueue();
      expect(transport.takeCommands(), startOfSearch(XiangqiPosition.initial()));

      container.dispose();

      expect(transport.takeCommands(), [
        'stop',
      ], reason: 'a search must not outlive the screen that asked for it');
    });
  });

  group('the session kept in memory', () {
    test('the line is there when the screen is come back to', () async {
      final harness = await makeHarness();
      harness.notifier.play(move('h2e2'));
      harness.notifier.play(move('h9g7'));
      harness.notifier.goBack();
      final leftOn = harness.state;

      // Popping the screen: the last listener goes away, which is what the save is hung on.
      harness.watched.close();
      await pumpEventQueue();

      final again = await makeHarness();

      expect(again.state.moves, leftOn.moves);
      expect(again.state.positions, leftOn.positions);
      expect(
        again.state.cursor,
        leftOn.moves.length,
        reason: 'a player coming back to a board is looking at the end of the line',
      );
      expect(again.state.position, leftOn.positions.last);
      expect(again.state.selected, isNull);
      expect(again.state.lines, isEmpty, reason: 'the engine has said nothing about it yet');
    });

    test('nothing reaches the disk, and the session can be dropped', () async {
      final harness = await makeHarness();
      harness.notifier.play(move('h2e2'));
      harness.watched.close();
      await pumpEventQueue();

      clearSavedXiangqiAnalysis();

      final again = await makeHarness();
      expect(again.state.moves, isEmpty);
      expect(again.state.position, XiangqiPosition.initial());
    });

    test('a line cleared before leaving is not resurrected by coming back', () async {
      final harness = await makeHarness();
      harness.notifier.play(move('h2e2'));
      harness.notifier.reset();

      harness.watched.close();
      await pumpEventQueue();

      final again = await makeHarness();
      expect(again.state.moves, isEmpty);
      expect(again.state.position, XiangqiPosition.initial());
    });
  });
}
