import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

import '../engine/fake_transport.dart';

/// The move written [iccs], which is also how Pikafish writes one.
XiangqiMove move(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// The initial position with black to move, for the sign tests below: a score the engine reports
/// here is black's, and has to be read as red's the other way round.
const _blackToMoveFen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1';

/// A running analysis: the container it lives in, the engine behind it, and what it has asked the
/// view to say.
class AnalysisHarness(final ProviderContainer container, final FakeTransport transport) {
  final List<UiEvent> events = [];

  XiangqiEngineAnalysis get notifier => container.read(xiangqiEngineAnalysisProvider.notifier);

  XiangqiEngineAnalysisState get state => container.read(xiangqiEngineAnalysisProvider);
}

/// An analysis on a real [Engine] whose transport is fake, with the engine already up.
///
/// Overriding the analysis's own engine provider, not the factory behind it, is deliberate: what is
/// under test is the analysis, and an [Engine] over a [FakeTransport] is the smallest thing that
/// answers the way Pikafish does — the handshake, the option hygiene, the commands, the `info`
/// parsing and the `bestmove` are all the real ones, and only the bytes in and out are not.
Future<AnalysisHarness> makeHarness() async {
  final transport = FakeTransport(
    spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
    startupLines: kPikafishHandshake,
  );
  final engine = Engine(transport);
  addTearDown(engine.dispose);

  final container = ProviderContainer(
    overrides: [xiangqiEngineProvider.overrideWith((Ref ref) => engine)],
  );
  addTearDown(container.dispose);

  final harness = AnalysisHarness(container, transport);
  final events = container.read(uiEventBusProvider).stream.listen(harness.events.add);
  addTearDown(events.cancel);

  // The analysis is autoDispose and a bare `read` is not a watcher, so without something holding it
  // it would be thrown away between two lines of a test.
  final watched = container.listen(xiangqiEngineAnalysisProvider, (_, _) {});
  addTearDown(watched.close);

  // The engine is started by the analysis's own build, so this is also what lets its handshake be
  // read before the first search.
  await pumpEventQueue();
  return harness;
}

void main() {
  group('XiangqiEvaluation.redWinProbability', () {
    double probability({int? cp, int? mate}) =>
        XiangqiEvaluation(cp: cp, mate: mate).redWinProbability;

    test('a level position is a coin toss, and the sign names the side', () {
      expect(probability(cp: 0), 0.5);
      expect(probability(cp: 100), greaterThan(0.5));
      expect(probability(cp: -100), lessThan(0.5));

      // The app's logistic is symmetric about zero, so the two sides of one score always add to
      // one — an exact identity, not an approximation.
      expect(probability(cp: 100) + probability(cp: -100), closeTo(1.0, 1e-9));
      expect(probability(cp: 1000) + probability(cp: -1000), closeTo(1.0, 1e-9));
    });

    test('the conversion matches lila at a known score', () {
      // The value is 1 / (1 + e^(-0.00368208 * cp)) — the app's winningChances shifted onto a bar —
      // spelled out here so that a change to the multiplier is a failure and not a silent drift.
      expect(probability(cp: 100), closeTo(0.5910, 0.0005));
      expect(probability(cp: -100), closeTo(0.4090, 0.0005));
    });

    test('a bigger advantage is further from level', () {
      expect(probability(cp: 300), greaterThan(probability(cp: 100)));
      expect(probability(cp: -300), lessThan(probability(cp: -100)));
      expect(probability(cp: 1000), greaterThan(probability(cp: 300)));
    });

    test('both mate signs, and a faster mate is more certain', () {
      expect(probability(mate: 1), greaterThan(0.99));
      expect(probability(mate: -1), lessThan(0.01));
      expect(probability(mate: 1) + probability(mate: -1), closeTo(1.0, 1e-9));

      // A mate in n is scored as a big centipawn win that shrinks as n grows, so mate in 1 reads as
      // more certain than mate in 10 — on whichever side of the bar.
      expect(probability(mate: 1), greaterThan(probability(mate: 10)));
      expect(probability(mate: -1), lessThan(probability(mate: -10)));
      expect(probability(mate: 10), greaterThan(0.5));
      expect(probability(mate: -10), lessThan(0.5));
    });

    test('extreme scores clamp to the bar, and no score at all is level', () {
      expect(probability(cp: 100000), lessThanOrEqualTo(1.0));
      expect(probability(cp: -100000), greaterThanOrEqualTo(0.0));
      expect(probability(mate: 1), lessThanOrEqualTo(1.0));
      expect(probability(mate: -1), greaterThanOrEqualTo(0.0));
      // Both null is the engine having said nothing yet: even, rather than a crash.
      expect(probability(), 0.5);
    });
  });

  group('xiangqiEvaluationFromEngine', () {
    test('leaves a red-to-move score alone', () {
      final evaluation = xiangqiEvaluationFromEngine(cp: 120, mate: null, sideToMove: .red);

      expect(evaluation.cp, 120);
      expect(evaluation.mate, isNull);
      expect(evaluation.redWinProbability, greaterThan(0.5));
    });

    test("flips a black-to-move score into red's point of view", () {
      final evaluation = xiangqiEvaluationFromEngine(cp: 120, mate: null, sideToMove: .black);

      expect(evaluation.cp, -120, reason: 'the engine said black is better, and red is not black');
      expect(evaluation.redWinProbability, lessThan(0.5));
    });

    test('flips both mate signs on a black-to-move position', () {
      // The engine's score is the side to move's, so a positive mate with black to move is black
      // mating, and red is the one on the wrong end of it.
      expect(
        xiangqiEvaluationFromEngine(cp: null, mate: 3, sideToMove: .black).redWinProbability,
        lessThan(0.5),
      );
      expect(
        xiangqiEvaluationFromEngine(cp: null, mate: -3, sideToMove: .black).redWinProbability,
        greaterThan(0.5),
      );
      // And unchanged with red to move, both ways.
      expect(
        xiangqiEvaluationFromEngine(cp: null, mate: 3, sideToMove: .red).redWinProbability,
        greaterThan(0.5),
      );
      expect(
        xiangqiEvaluationFromEngine(cp: null, mate: -3, sideToMove: .red).redWinProbability,
        lessThan(0.5),
      );
    });

    test('the two sides to move are exact mirrors of each other', () {
      for (final cp in [17, -250, 900]) {
        final red = xiangqiEvaluationFromEngine(cp: cp, mate: null, sideToMove: .red);
        final black = xiangqiEvaluationFromEngine(cp: cp, mate: null, sideToMove: .black);

        expect(red.cp, cp);
        expect(black.cp, -cp);
        expect(red.redWinProbability + black.redWinProbability, closeTo(1.0, 1e-9));
      }
    });
  });

  group('value equality', () {
    test('hints and evaluations are equal by value', () {
      final hint = XiangqiHint(move: move('h2e2'), evaluation: const XiangqiEvaluation(cp: 34));
      final same = XiangqiHint(move: move('h2e2'), evaluation: const XiangqiEvaluation(cp: 34));
      final other = XiangqiHint(move: move('h2e0'));

      expect(hint, same);
      expect(hint.hashCode, same.hashCode);
      expect(hint, isNot(other));
      // No evaluation is not the same as a level one.
      expect(hint, isNot(XiangqiHint(move: move('h2e2'))));

      expect(const XiangqiEvaluation(cp: 34), const XiangqiEvaluation(cp: 34));
      expect(const XiangqiEvaluation(cp: 34), isNot(const XiangqiEvaluation(cp: 35)));
      expect(const XiangqiEvaluation(cp: 34), isNot(const XiangqiEvaluation(mate: 34)));
    });

    test('the analysis state is equal by value, and copyWith replaces one field', () {
      const empty = XiangqiEngineAnalysisState();

      expect(empty.hint, isNull);
      expect(empty.evaluation, isNull);
      expect(empty.isBusy, isFalse);
      expect(empty, const XiangqiEngineAnalysisState());

      final busy = empty.copyWith(isBusy: true);
      expect(busy.isBusy, isTrue);
      expect(busy, const XiangqiEngineAnalysisState(isBusy: true));
      expect(busy.copyWith(isBusy: false), empty);
    });
  });

  group('XiangqiEngineAnalysis', () {
    test("a hint is the engine's move, at the opponent's own strength", () async {
      final harness = await makeHarness();
      final position = XiangqiPosition.initial();

      final hint = harness.notifier.requestHint(position);
      expect(harness.state.isBusy, isTrue);
      await pumpEventQueue();
      expect(harness.transport.takeCommands(), ['ucinewgame', 'isready']);

      harness.transport.emit('readyok');
      await pumpEventQueue();
      // The position as a FEN, and a depth of nine as the limit: the analysis limit, which is a
      // bounded search because the engine is one the opponent is sharing. It is not a rung of the
      // difficulty ladder — a hint is not a level of opponent — so it does not move with one.
      expect(harness.transport.takeCommands(), ['position fen ${position.toFen()}', 'go depth 9']);

      harness.transport.emit('info depth 9 score cp 34 nodes 9450 time 90 pv h2e2');
      await pumpEventQueue();
      expect(harness.state.evaluation, const XiangqiEvaluation(cp: 34));

      harness.transport.emit('bestmove h2e2');
      await hint;

      expect(harness.state.isBusy, isFalse);
      expect(
        harness.state.hint,
        XiangqiHint(move: move('h2e2'), evaluation: const XiangqiEvaluation(cp: 34)),
      );
    });

    test("the evaluation is red's point of view, whatever side is to move", () async {
      final harness = await makeHarness();
      final position = XiangqiPosition.fromFen(_blackToMoveFen);

      final hint = harness.notifier.requestHint(position);
      await pumpEventQueue();
      harness.transport.emit('readyok');
      await pumpEventQueue();

      // The engine says the side to move — black — is 150 up. That is red being 150 down.
      harness.transport.emit('info depth 9 score cp 150 nodes 500 time 10 pv h9g7');
      await pumpEventQueue();
      expect(harness.state.evaluation?.cp, -150);
      expect(harness.state.evaluation!.redWinProbability, lessThan(0.5));

      harness.transport.emit('bestmove h9g7');
      await hint;
      expect(harness.state.hint?.move, move('h9g7'));
      expect(harness.state.hint?.evaluation?.cp, -150);
    });

    test('an evaluation streams the latest score and stops on demand', () async {
      final harness = await makeHarness();
      final position = XiangqiPosition.initial();

      harness.notifier.startEvaluation(position);
      expect(harness.state.isBusy, isTrue);
      await pumpEventQueue();
      expect(harness.transport.takeCommands(), ['ucinewgame', 'isready']);

      harness.transport.emit('readyok');
      await pumpEventQueue();
      expect(harness.transport.takeCommands(), ['position fen ${position.toFen()}', 'go depth 9']);

      harness.transport.emit('info depth 1 score cp 5 nodes 20 time 1 pv h2e2');
      await pumpEventQueue();
      expect(harness.state.evaluation, const XiangqiEvaluation(cp: 5));

      harness.transport.emit('info depth 5 score cp 42 nodes 500 time 10 pv h2e2');
      await pumpEventQueue();
      expect(
        harness.state.evaluation,
        const XiangqiEvaluation(cp: 42),
        reason: 'the bar shows the latest score, not the first',
      );

      harness.notifier.stopEvaluation();
      expect(harness.state.isBusy, isFalse);
      expect(harness.transport.takeCommands(), ['stop']);

      // The engine's own answer, arriving after the stop, cannot bring the evaluation back.
      harness.transport.emit('bestmove h2e2');
      await pumpEventQueue();
      expect(harness.state.isBusy, isFalse);
      expect(harness.state.evaluation, const XiangqiEvaluation(cp: 42));
    });

    test('a second request stops the first search before starting its own', () async {
      final harness = await makeHarness();
      final secondPosition = XiangqiPosition.fromFen(_blackToMoveFen);

      final first = harness.notifier.requestHint(XiangqiPosition.initial());
      await pumpEventQueue();
      harness.transport.emit('readyok');
      await pumpEventQueue();
      harness.transport.takeCommands();

      final second = harness.notifier.requestHint(secondPosition);
      await pumpEventQueue();

      // The search in flight is dropped before the new one is handed to the engine.
      expect(harness.transport.takeCommands(), ['stop', 'isready']);

      // The engine answers the stopped search, which is what lets the new one start; the stale
      // answer is not offered as a hint.
      harness.transport.emit('bestmove h2e2');
      await pumpEventQueue();
      expect(harness.transport.takeCommands(), [
        'position fen ${secondPosition.toFen()}',
        'go depth 9',
      ]);
      await first;
      expect(harness.state.hint, isNull, reason: 'the first request was replaced and has no hint');

      harness.transport.emit('bestmove h9g7');
      await second;
      expect(harness.state.isBusy, isFalse);
      expect(harness.state.hint?.move, move('h9g7'));
    });

    test('a move this position cannot play is reported, and no hint is left', () async {
      final harness = await makeHarness();

      final hint = harness.notifier.requestHint(XiangqiPosition.initial());
      await pumpEventQueue();
      harness.transport.emit('readyok');
      await pumpEventQueue();

      // A chariot through its own soldier: the sort of thing an engine answers with when it is
      // broken, or when it has been sent a position that is not the one on the board.
      harness.transport.emit('bestmove a0a5');
      await hint;
      await pumpEventQueue();

      expect(harness.state.hint, isNull);
      expect(harness.state.isBusy, isFalse);
      expect(harness.events, [
        isA<ShowErrorEvent>(),
      ], reason: 'the player has to be told, because the board cannot show the move');
    });

    test('an engine that dies mid-search leaves the state clean and says so', () async {
      final harness = await makeHarness();

      final hint = harness.notifier.requestHint(XiangqiPosition.initial());
      await pumpEventQueue();
      harness.transport.emit('readyok');
      await pumpEventQueue();

      harness.transport.die();
      await hint;
      await pumpEventQueue();

      expect(harness.state.hint, isNull);
      expect(harness.state.isBusy, isFalse);
      expect(harness.events, [isA<ShowErrorEvent>()]);
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
      final watched = container.listen(xiangqiEngineAnalysisProvider, (_, _) {});
      addTearDown(watched.close);

      await container
          .read(xiangqiEngineAnalysisProvider.notifier)
          .requestHint(XiangqiPosition.initial());
      // The event reaches the bus on its own microtask, so it is there only after the queue has
      // been pumped.
      await pumpEventQueue();

      final state = container.read(xiangqiEngineAnalysisProvider);
      expect(state.hint, isNull);
      expect(state.isBusy, isFalse);
      expect(events, [isA<ShowErrorEvent>()]);
    });

    test('disposal stops the search on the shared engine', () async {
      // Standalone rather than through makeHarness: this test disposes the container itself, and
      // a second dispose from a tear-down would be the thing under test's noise rather than its
      // point.
      final transport = FakeTransport(
        spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
        startupLines: kPikafishHandshake,
      );
      final engine = Engine(transport);
      addTearDown(engine.dispose);
      final container = ProviderContainer(
        overrides: [xiangqiEngineProvider.overrideWith((Ref ref) => engine)],
      );
      container.listen(xiangqiEngineAnalysisProvider, (_, _) {});

      unawaited(
        container
            .read(xiangqiEngineAnalysisProvider.notifier)
            .requestHint(XiangqiPosition.initial()),
      );
      // The shared engine's first search: fresh on the engine, so it is told a new game and
      // asked to get ready before it is given anything to search.
      await pumpEventQueue();
      expect(transport.takeCommands(), ['ucinewgame', 'isready']);
      transport.emit('readyok');
      await pumpEventQueue();
      expect(transport.takeCommands(), [
        'position fen ${XiangqiPosition.initial().toFen()}',
        'go depth 9',
      ]);

      container.dispose();

      expect(transport.takeCommands(), [
        'stop',
      ], reason: 'a search must not outlive the screen that asked for it');
    });
  });
}
