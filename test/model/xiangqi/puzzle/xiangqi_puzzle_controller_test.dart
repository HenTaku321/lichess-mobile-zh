// Tests for the attempt at a puzzle: which moves the app plays, which ones it refuses, what it
// spends, and what it tells the server.
//
// The puzzle comes from `xiangqi_puzzle_fixture.dart`, which builds it out of the wire's shapes and
// a position this repository's own rules engine played. The reply pause is set to zero here, so a
// whole line runs without waiting out four hundred milliseconds per answer; what is left is the
// submission, which is a real request against a stubbed transport.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

import 'xiangqi_puzzle_fixture.dart';

/// A client answering the two endpoints an attempt talks to, and logging what it was asked.
MockClient attemptClient({
  required List<http.Request> requests,
  Map<String, Object?> completeAnswer = const {'p_rating': xiangqiTestPuzzleRating, 'status': 4},
  int completeStatus = 200,
  Map<String, Object?> usageAnswer = const {
    'feature': 'puzzle_hints',
    'allowed': true,
    'remaining': 4,
    'reason': 'ok',
  },
  int usageStatus = 200,
}) {
  return MockClient((request) {
    requests.add(request);
    if (request.url.path.endsWith('/complete')) {
      return xiangqiJsonResponse(jsonEncode(completeAnswer), completeStatus);
    }
    if (request.url.path == '/api/quota/usage') {
      return xiangqiJsonResponse(jsonEncode(usageAnswer), usageStatus);
    }
    return xiangqiJsonResponse('{}', 404);
  });
}

/// An attempt at [puzzle], with the controller kept alive for the rest of the test.
Future<({ProviderContainer container, XiangqiPuzzleController controller})> makeAttempt({
  required MockClient client,
  XiangqiPuzzle? puzzle,
  Duration replyDelay = Duration.zero,
  Duration wrongMoveDelay = Duration.zero,
}) async {
  final container = await makeXiangqiPuzzleContainer(
    client,
    replyDelay: replyDelay,
    wrongMoveDelay: wrongMoveDelay,
  );
  final provider = xiangqiPuzzleControllerProvider((
    puzzle: puzzle ?? xiangqiTestPuzzle,
    attempt: 0,
  ));
  final subscription = container.listen(provider, (_, _) {});
  addTearDown(subscription.close);
  return (container: container, controller: container.read(provider.notifier));
}

/// The state of the attempt [provider] names.
XiangqiPuzzleAttemptState stateOf(ProviderContainer container, [XiangqiPuzzle? puzzle]) => container
    .read(xiangqiPuzzleControllerProvider((puzzle: puzzle ?? xiangqiTestPuzzle, attempt: 0)));

/// A legal move in [position] that is not [notThis] — something to get wrong.
XiangqiMove otherLegalMove(XiangqiPuzzleAttemptState state) =>
    rules.legalMoves(state.position).firstWhere((move) => move != state.nextSolutionMove);

void main() {
  test('the blunder is played before the solver is given the board', () async {
    final attempt = await makeAttempt(client: attemptClient(requests: []));
    final state = stateOf(attempt.container);

    expect(state.moves, [xiangqiTestLine.blunder]);
    expect(state.positions, [
      xiangqiTestLine.before,
      rules.play(xiangqiTestLine.before, xiangqiTestLine.blunder),
    ]);
    expect(state.position, rules.play(xiangqiTestLine.before, xiangqiTestLine.blunder));
    expect(state.positions.length, state.moves.length + 1);
    // The blunder is the opponent's move, so the solver is to move once it is on the board.
    expect(state.isSolverTurn, isTrue);
    expect(state.phase, XiangqiPuzzlePhase.solving);
    expect(state.isPlayable, isTrue);
    expect(state.mistakes, 0);
    expect(state.hintsUsed, 0);
    expect(state.hint, isNull);
    expect(state.wrongMove, isNull);
  });

  test('a wrong move is played, counted, and then taken back', () async {
    final attempt = await makeAttempt(
      client: attemptClient(requests: []),
      wrongMoveDelay: const Duration(milliseconds: 100),
    );
    final before = stateOf(attempt.container);
    final wrong = otherLegalMove(before);

    attempt.controller.onUserMove(wrong);

    final during = stateOf(attempt.container);
    expect(during.position, rules.play(before.position, wrong));
    expect(during.moves, [...before.moves, wrong]);
    expect(during.mistakes, 1);
    expect(during.wrongMove, wrong);
    expect(during.isSolverTurn, isFalse, reason: 'nothing else can be played while it is shown');

    await waitUntil(
      () => stateOf(attempt.container).isSolverTurn,
      reason: 'the wrong move to be taken back',
    );

    final after = stateOf(attempt.container);
    expect(after.position, before.position);
    expect(after.positions, before.positions);
    expect(after.moves, before.moves);
    expect(after.mistakes, 1);
    expect(after.wrongMove, wrong, reason: 'the feedback stays until the next move');
    expect(after.isSolverTurn, isTrue, reason: 'the solver tries again from the same position');
  });

  test('the right move is played, and the opponent answers it', () async {
    final attempt = await makeAttempt(client: attemptClient(requests: []));
    final before = stateOf(attempt.container);

    attempt.controller.onUserMove(before.nextSolutionMove!);

    final after = stateOf(attempt.container);
    expect(after.moves, [
      xiangqiTestLine.blunder,
      xiangqiTestLine.solution[0],
      xiangqiTestLine.solution[1],
    ]);
    expect(after.positions.length, after.moves.length + 1);
    expect(
      after.position,
      rules.play(after.positions[after.positions.length - 2], after.moves.last),
    );
    // The answer is the opponent's, so the solver is to move again.
    expect(after.isSolverTurn, isTrue);
    expect(after.phase, XiangqiPuzzlePhase.solving, reason: 'the line is not over yet');
    expect(after.wrongMove, isNull);
  });

  test('the whole line is played and the attempt is submitted with its counts', () async {
    final requests = <http.Request>[];
    final attempt = await makeAttempt(client: attemptClient(requests: requests));

    _solve(attempt.container, attempt.controller);

    await waitUntil(
      () => stateOf(attempt.container).phase == XiangqiPuzzlePhase.recorded,
      reason: 'the attempt to be recorded',
    );

    final state = stateOf(attempt.container);
    expect(state.moves, [xiangqiTestLine.blunder, ...xiangqiTestLine.solution]);
    expect(state.positions.length, state.moves.length + 1);
    expect(state.nextSolutionMove, isNull);
    expect(state.isPlayable, isFalse);
    expect(state.recordedStatus, XiangqiPuzzleAttemptStatus.solved);

    final sent = requests.singleWhere((request) => request.url.path.endsWith('/complete'));
    expect(sent.method, 'POST');
    expect(jsonDecode(sent.body), {'mistakes': 0, 'hints_used': 0, 'attempt_mode': 'P'});
  });

  test('a submitting attempt does not expose the next action as complete', () async {
    final attempt = await makeAttempt(client: attemptClient(requests: []));
    final state = stateOf(attempt.container);
    expect(state.copyWith(phase: XiangqiPuzzlePhase.submitting).isLineComplete, isFalse);
    expect(state.copyWith(phase: XiangqiPuzzlePhase.recorded).isLineComplete, isTrue);
  });

  test('the mistakes and the hints are what the server is told about', () async {
    final requests = <http.Request>[];
    final attempt = await makeAttempt(
      client: attemptClient(
        requests: requests,
        // The server recomputes the status from the counts, and this is what it answers for an
        // attempt that got a move wrong on the way.
        completeAnswer: const {'p_rating': xiangqiTestPuzzleRating, 'status': 2},
      ),
    );

    attempt.controller.onUserMove(otherLegalMove(stateOf(attempt.container)));
    await waitUntil(
      () => stateOf(attempt.container).isSolverTurn,
      reason: 'the wrong move to be taken back',
    );
    await attempt.controller.hint();
    _solve(attempt.container, attempt.controller);

    await waitUntil(
      () => stateOf(attempt.container).phase == XiangqiPuzzlePhase.recorded,
      reason: 'the attempt to be recorded',
    );

    final sent = requests.singleWhere((request) => request.url.path.endsWith('/complete'));
    expect(jsonDecode(sent.body), {'mistakes': 1, 'hints_used': 1, 'attempt_mode': 'P'});
    expect(stateOf(attempt.container).recordedStatus, XiangqiPuzzleAttemptStatus.solvedByMistake);
  });

  test('a hint is asked for from the server, and it points at the next move', () async {
    final requests = <http.Request>[];
    final attempt = await makeAttempt(client: attemptClient(requests: requests));

    final usage = await attempt.controller.hint();

    expect(usage!.allowed, isTrue);
    final sent = requests.single;
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.xiangqi.com/api/quota/usage');
    expect(jsonDecode(sent.body), {'feature': 'puzzle_hints'});

    final state = stateOf(attempt.container);
    expect(state.hint, xiangqiTestLine.solution.first);
    expect(state.hintsUsed, 1);
  });

  test('a hint the server refuses is not shown, and is not counted', () async {
    final requests = <http.Request>[];
    final attempt = await makeAttempt(
      client: attemptClient(
        requests: requests,
        usageAnswer: const {
          'feature': 'puzzle_hints',
          'allowed': false,
          'remaining': 0,
          'reason': 'exhausted',
        },
      ),
    );

    final usage = await attempt.controller.hint();

    expect(usage!.allowed, isFalse);
    expect(usage.reason, 'exhausted');
    final state = stateOf(attempt.container);
    expect(state.hint, isNull);
    expect(state.hintsUsed, 0);
  });

  test('a hint is not asked for when it is not the solver to move', () async {
    final requests = <http.Request>[];
    final attempt = await makeAttempt(
      client: attemptClient(requests: requests),
      // A real pause, so that the attempt is caught between the solver's move and the answer to it.
      replyDelay: const Duration(milliseconds: 200),
    );

    attempt.controller.onUserMove(stateOf(attempt.container).nextSolutionMove!);
    expect(stateOf(attempt.container).isSolverTurn, isFalse);

    expect(await attempt.controller.hint(), isNull);
    expect(requests, isEmpty, reason: 'nothing to spend an allowance on');
  });

  test('a puzzle whose answer was withheld is a board nobody can play', () async {
    final requests = <http.Request>[];
    final attempt = await makeAttempt(
      client: attemptClient(requests: requests),
      puzzle: xiangqiTestPuzzleWithoutAnswer,
    );

    final state = stateOf(attempt.container, xiangqiTestPuzzleWithoutAnswer);
    expect(state.puzzle.solution, isNull);
    expect(state.isPlayable, isFalse);
    expect(state.canHint, isFalse);
    expect(state.nextSolutionMove, isNull);

    // The blunder is still played — the position is the server's, and the answer is not.
    expect(state.moves, [xiangqiTestLine.blunder]);
    expect(state.position, rules.play(xiangqiTestLine.before, xiangqiTestLine.blunder));

    attempt.controller.onUserMove(rules.legalMoves(state.position).first);
    expect(stateOf(attempt.container, xiangqiTestPuzzleWithoutAnswer).moves, state.moves);
    expect(await attempt.controller.hint(), isNull);
    expect(requests, isEmpty);
  });

  test('a submission that does not arrive leaves the line on the board', () async {
    final requests = <http.Request>[];
    final attempt = await makeAttempt(
      client: attemptClient(requests: requests, completeStatus: 500),
    );

    _solve(attempt.container, attempt.controller);
    await waitUntil(
      () => stateOf(attempt.container).phase == XiangqiPuzzlePhase.unrecorded,
      reason: 'the submission to fail',
    );

    final state = stateOf(attempt.container);
    expect(state.moves, [xiangqiTestLine.blunder, ...xiangqiTestLine.solution]);
    expect(state.recordedStatus, isNull);

    // And the same counts go out again: the mistakes and the hints are facts about the attempt and
    // do not change because a request was lost.
    await attempt.controller.retrySubmit();
    expect(stateOf(attempt.container).phase, XiangqiPuzzlePhase.unrecorded);
    final sent = requests.where((request) => request.url.path.endsWith('/complete'));
    expect(sent.length, 2);
    expect(jsonDecode(sent.last.body), {'mistakes': 0, 'hints_used': 0, 'attempt_mode': 'P'});
  });

  test('a move played after the line is complete changes nothing', () async {
    final attempt = await makeAttempt(client: attemptClient(requests: []));

    _solve(attempt.container, attempt.controller);
    final before = stateOf(attempt.container);
    expect(before.isPlayable, isFalse);

    attempt.controller.onUserMove(rules.legalMoves(before.position).first);

    expect(stateOf(attempt.container).moves, before.moves);
    expect(stateOf(attempt.container).mistakes, before.mistakes);
  });
}

/// Plays the solver's side of the fixture's line, and waits for nothing.
///
/// The opponent's answers are the app's, so this only has to play the moves that are the solver's —
/// which is what the turn check picks out. The submission that follows the last one is a request,
/// and the caller waits for that.
void _solve(ProviderContainer container, XiangqiPuzzleController controller) {
  for (var i = 0; i < xiangqiTestLine.solution.length; i++) {
    final state = stateOf(container);
    if (!state.isSolverTurn) continue;
    final move = state.nextSolutionMove;
    if (move == null) break;
    controller.onUserMove(move);
  }
}
