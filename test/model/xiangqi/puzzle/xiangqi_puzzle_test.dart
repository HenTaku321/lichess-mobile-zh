// Tests for the xiangqi.com puzzle reader and the endpoints around it.
//
// The payloads come from `xiangqi_puzzle_fixture.dart`, which builds them from the shapes the
// 2026-10-15/16 probe measured and from a position this repository's own rules engine played. What
// is asserted is the reading of those shapes — which key holds the solver's side, what a withheld
// answer looks like, which payloads are dropped — and not the values inside them.

import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/quota/xiangqi_quota.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/network/http.dart';

import 'xiangqi_puzzle_fixture.dart';

/// The payload as a JSON object, which is what the reader takes.
Map<String, dynamic> payload(Map<String, Object?> json) => json.cast<String, dynamic>();

/// A response carrying [bytes] as UTF-8, which is what the xiangqi.com client reads.
///
/// `http.Response(body)` would encode a `String` as Latin-1 and throw on anything non-ASCII, so the
/// bytes are built here the way the real server sends them: UTF-8, with no charset in the headers.
Future<http.Response> respond(List<int> bytes, int status) =>
    Future.value(http.Response.bytes(bytes, status));

/// A client answering `GET /api/puzzle/P/<id>` with [body] and [status], and nothing else.
MockClient puzzleClient(String body, {int status = 200, void Function(http.Request)? onRequest}) {
  return MockClient((request) {
    onRequest?.call(request);
    if (request.method == 'GET' && request.url.path.startsWith('/api/puzzle/P/')) {
      return respond(utf8.encode(body), status);
    }
    return respond(const [], 404);
  });
}

void main() {
  group('xiangqiPuzzleFromJson', () {
    test('reads the measured payload', () {
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload()));

      expect(puzzle, isNotNull);
      expect(puzzle!.id, xiangqiTestPuzzleId);
      expect(puzzle.title, isNull);
      expect(puzzle.rating, xiangqiTestPuzzleRating);
      expect(puzzle.theme, XiangqiPuzzleTheme.tactic);
      expect(puzzle.fullMoves, 2);
      expect(puzzle.state, 300);
      expect(puzzle.passRate, 50.0);
      expect(puzzle.tags, isEmpty);
      expect(puzzle.attempt?.status, XiangqiPuzzleAttemptStatus.started);
      expect(puzzle.attempt?.userRating, xiangqiTestUserRating);
    });

    test('the position is the one before the blunder, and the blunder is legal in it', () {
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload()))!;

      expect(puzzle.position, xiangqiTestLine.before);
      expect(rules.isLegal(puzzle.position, puzzle.blunderMove), isTrue);
      expect(puzzle.blunderMove, xiangqiTestLine.blunder);
    });

    test('the solver is the side that is not to move, and player_turn says which', () {
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload()))!;

      // The measured rule: the side to move in `initial_fen` is the one that blundered, so the
      // solver is the other one. The fixture's `player_turn` is the number for that side.
      expect(puzzle.position.turn, XiangqiSide.red);
      expect(puzzle.playerSide, XiangqiSide.black);
      expect(puzzle.playerSide, puzzle.position.turn.opposite);
    });

    test('player_turn 1 is red and 2 is black', () {
      expect(
        xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(playerTurn: 1)))!.playerSide,
        XiangqiSide.red,
      );
      expect(
        xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(playerTurn: 2)))!.playerSide,
        XiangqiSide.black,
      );
    });

    test('a payload with no player_turn falls back to the side that is not to move', () {
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(playerTurn: null)))!;

      expect(puzzle.playerSide, puzzle.position.turn.opposite);
    });

    test('the solution is the answer without the blunder that opens it', () {
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload()))!;

      expect(puzzle.solution, xiangqiTestLine.solution);
      expect(puzzle.solution, isNot(contains(puzzle.blunderMove)));
      // The wire's own list, put back together: the blunder and then the solution.
      expect(puzzle.modelAnswer, xiangqiTestLine.answer);
    });

    test('a withheld answer is a puzzle with no solution, not a broken payload', () {
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(modelAnswer: null)));

      expect(puzzle, isNotNull);
      expect(puzzle!.solution, isNull);
      expect(puzzle.modelAnswer, isEmpty);
      // Everything else is still there: the position is what the server keeps when it withholds the
      // answer, and it is the whole reason the screen can still draw a board.
      expect(puzzle.blunderMove, xiangqiTestLine.blunder);
      expect(puzzle.position, xiangqiTestLine.before);
    });

    test('an answer of one move cannot describe a blunder and an answer to it', () {
      final answer = xiangqiTestLine.answer.map((move) => move.iccs).toList();

      expect(xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(modelAnswer: []))), isNull);
      expect(
        xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(modelAnswer: [answer.first]))),
        isNull,
      );
    });

    test('an answer holding something that is not a move is dropped', () {
      final answer = xiangqiTestLine.answer.map((move) => move.iccs).toList()..[1] = 'zz99';

      expect(xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(modelAnswer: answer))), isNull);
    });

    test('a puzzle that is not published is not a puzzle to solve', () {
      // `-100` is the measured draft state, and 100 and 200 are on their way to publication. None of
      // them has an answer yet.
      for (final state in const <Object?>[-100, 0, 100, 200, null]) {
        expect(
          xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(state: state))),
          isNull,
          reason: 'state: $state',
        );
      }
    });

    test('an initial_fen that will not parse is dropped', () {
      for (final fen in const <Object?>['', 'not a fen', '9/9/9/9/9/9/9/9/9/9 x - - 0 1']) {
        expect(
          xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(initialFen: fen))),
          isNull,
          reason: 'initial_fen: $fen',
        );
      }
    });

    test('a blunder_move that is not a move is dropped', () {
      for (final move in const <Object?>[null, '', 'zz99', 'h3e3e3']) {
        expect(
          xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(blunderMove: move))),
          isNull,
          reason: 'blunder_move: $move',
        );
      }
    });

    test('a blunder that cannot be played in the position is dropped', () {
      // A move that is well formed and legal *somewhere* — the opening cannon — played from the
      // fixture's position, where that cannon is no longer on h2. The app plays the blunder itself,
      // so a puzzle whose blunder is not a move here is a puzzle that cannot be set up.
      final illegal = XiangqiMove.parseIccs('h2e2')!.iccs;

      expect(xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(blunderMove: illegal))), isNull);
    });

    test('a missing puzzle_id is dropped', () {
      expect(xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(puzzleId: null))), isNull);
    });

    test('full_moves is read, and derived from the answer when it is not there', () {
      expect(xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(fullMoves: 7)))!.fullMoves, 7);
      expect(
        xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(fullMoves: null)))!.fullMoves,
        xiangqiTestLine.solution.length ~/ 2,
      );
    });

    test('a pass rate that is not there is null, not a zero', () {
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(passRate: null)));

      expect(puzzle!.passRate, isNull);
    });

    test('an attempt that is not there is null, and an unknown status is a null status', () {
      expect(xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(attempt: null)))!.attempt, isNull);
      expect(
        xiangqiPuzzleFromJson(
          payload(xiangqiPuzzlePayload(attempt: const {'status': 99, 'u_rating': 1200})),
        )!.attempt!.status,
        isNull,
      );
    });

    test('tags are read as ids, whether the wire spells them as numbers or as objects', () {
      expect(
        xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(tags: const <Object?>[46, 48])))!.tags,
        [46, 48],
      );
      expect(
        xiangqiPuzzleFromJson(
          payload(
            xiangqiPuzzlePayload(
              tags: const <Object?>[
                {'id': 46, 'theme': 2, 'en': 'Breakthrough'},
                {'theme': 2},
                'nonsense',
              ],
            ),
          ),
        )!.tags,
        [46],
      );
      expect(
        xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(tags: 'not a list')))!.tags,
        isEmpty,
      );
    });

    test('a theme this app does not know leaves the puzzle readable', () {
      // The wire has exactly two themes and the themes endpoint lists them; a third would be a
      // protocol change, and a puzzle filed under one is still a puzzle. The label falls back
      // rather than the puzzle being dropped.
      final puzzle = xiangqiPuzzleFromJson(payload(xiangqiPuzzlePayload(theme: 3)));

      expect(puzzle, isNotNull);
      expect(puzzle!.theme, XiangqiPuzzleTheme.tactic);
    });
  });

  group('xiangqiPuzzleProvider', () {
    test('asks for the puzzle by id and reads it', () async {
      http.Request? sent;
      final container = await makeXiangqiPuzzleContainer(
        puzzleClient(jsonEncode(xiangqiPuzzlePayload()), onRequest: (r) => sent = r),
      );

      final puzzle = await readKeepingAlive(container, xiangqiPuzzleProvider(xiangqiTestPuzzleId));

      expect(sent!.method, 'GET');
      expect(sent!.url.toString(), 'https://api.xiangqi.com/api/puzzle/P/$xiangqiTestPuzzleId');
      expect(puzzle.id, xiangqiTestPuzzleId);
      expect(puzzle.solution, xiangqiTestLine.solution);
    });

    test('a 429 that carries the puzzle is a read, with the answer struck out', () async {
      final container = await makeXiangqiPuzzleContainer(
        puzzleClient(jsonEncode(xiangqiPuzzleQuotaExceededBody()), status: 429),
      );

      final puzzle = await readKeepingAlive(container, xiangqiPuzzleProvider(xiangqiTestPuzzleId));

      expect(puzzle.id, xiangqiTestPuzzleId);
      expect(puzzle.solution, isNull);
      expect(puzzle.position, xiangqiTestLine.before);
    });

    test('a 429 that carries no puzzle is the refusal it is', () async {
      final container = await makeXiangqiPuzzleContainer(
        puzzleClient(
          jsonEncode(const {
            'error': 'quota_exceeded',
            'feature': 'puzzles',
            'remaining': 0,
            'reason': 'exhausted',
          }),
          status: 429,
        ),
      );

      await expectLater(
        readKeepingAlive(container, xiangqiPuzzleProvider(xiangqiTestPuzzleId)),
        throwsA(
          isA<XiangqiQuotaExceededException>()
              .having((e) => e.feature, 'feature', 'puzzles')
              .having((e) => e.remaining, 'remaining', 0)
              .having((e) => e.reason, 'reason', 'exhausted'),
        ),
      );
    });

    test('any other failure is a ServerException', () async {
      final container = await makeXiangqiPuzzleContainer(puzzleClient('', status: 404));

      await expectLater(
        readKeepingAlive(container, xiangqiPuzzleProvider(xiangqiTestPuzzleId)),
        throwsA(isA<ServerException>()),
      );
    });

    test('no session means no request', () async {
      var requests = 0;
      final container = await makeXiangqiPuzzleContainer(
        puzzleClient(jsonEncode(xiangqiPuzzlePayload()), onRequest: (_) => requests++),
        signedIn: false,
      );

      await expectLater(
        readKeepingAlive(container, xiangqiPuzzleProvider(xiangqiTestPuzzleId)),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0);
    });

    test('being offline is an Error, and the request is never sent', () async {
      var requests = 0;
      final container = await makeXiangqiPuzzleContainer(
        puzzleClient(jsonEncode(xiangqiPuzzlePayload()), onRequest: (_) => requests++),
        offline: true,
      );

      await expectLater(
        readKeepingAlive(container, xiangqiPuzzleProvider(xiangqiTestPuzzleId)),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0);
    });
  });

  group('xiangqiPuzzleSearchProvider', () {
    test('posts the documented body and reads the id it answers with', () async {
      http.Request? sent;
      final container = await makeXiangqiPuzzleContainer(
        MockClient((request) {
          sent = request;
          return respond(
            utf8.encode(jsonEncode(const {'puzzle_id': xiangqiTestPuzzleId, 'title': null})),
            200,
          );
        }),
      );

      final id = await readKeepingAlive(
        container,
        xiangqiPuzzleSearchProvider(xiangqiDefaultPuzzleSearch),
      );

      expect(sent!.method, 'POST');
      expect(sent!.url.toString(), 'https://api.xiangqi.com/api/puzzle/search');
      expect(jsonDecode(sent!.body), {
        'previously_failed': false,
        'previously_played': false,
        'rating_range': [0, 3000],
        'themes': <Object?>[],
        'tags': <Object?>[],
      });
      expect(id, xiangqiTestPuzzleId);
    });

    test('an empty queue is a null id, not a failure', () async {
      final container = await makeXiangqiPuzzleContainer(
        MockClient(
          (request) => respond(
            utf8.encode(jsonEncode(const {'message': "There's no next puzzle available"})),
            200,
          ),
        ),
      );

      expect(
        await readKeepingAlive(container, xiangqiPuzzleSearchProvider(xiangqiDefaultPuzzleSearch)),
        isNull,
      );
    });

    test('the themes and tags that were asked for are what goes out', () async {
      http.Request? sent;
      final container = await makeXiangqiPuzzleContainer(
        MockClient((request) {
          sent = request;
          return respond(utf8.encode('{}'), 200);
        }),
      );

      await readKeepingAlive(
        container,
        xiangqiPuzzleSearchProvider((
          previouslyFailed: true,
          previouslyPlayed: true,
          minRating: 800,
          maxRating: 1600,
          themes: const IListConst([1]),
          tags: const IListConst([46]),
        )),
      );

      expect(jsonDecode(sent!.body), {
        'previously_failed': true,
        'previously_played': true,
        'rating_range': [800, 1600],
        'themes': [1],
        'tags': [46],
      });
    });

    test('no session means no request', () async {
      var requests = 0;
      final container = await makeXiangqiPuzzleContainer(
        MockClient((request) {
          requests++;
          return respond(utf8.encode('{}'), 200);
        }),
        signedIn: false,
      );

      await expectLater(
        readKeepingAlive(container, xiangqiPuzzleSearchProvider(xiangqiDefaultPuzzleSearch)),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0);
    });
  });

  group('XiangqiPuzzleRepository.complete', () {
    test('posts the counts and the mode, and reads what the server recorded', () async {
      http.Request? sent;
      final container = await makeXiangqiPuzzleContainer(
        MockClient((request) {
          sent = request;
          return respond(utf8.encode(jsonEncode(const {'p_rating': 1500, 'status': 2})), 200);
        }),
      );

      final result = await container
          .read(xiangqiPuzzleRepositoryProvider)
          .complete(
            xiangqiTestPuzzleId,
            mistakes: 1,
            hintsUsed: 0,
            mode: XiangqiPuzzleAttemptMode.practice,
          );

      expect(sent!.method, 'POST');
      expect(
        sent!.url.toString(),
        'https://api.xiangqi.com/api/puzzle/$xiangqiTestPuzzleId/complete',
      );
      // `status` is deliberately absent: the server recomputes it, and sending one is a 400.
      expect(jsonDecode(sent!.body), {'mistakes': 1, 'hints_used': 0, 'attempt_mode': 'P'});
      expect(result.puzzleRating, 1500);
      expect(result.status, XiangqiPuzzleAttemptStatus.solvedByMistake);
    });

    test('a refusal is a ServerException, not a made-up result', () async {
      final container = await makeXiangqiPuzzleContainer(
        MockClient((request) => respond(const [], 500)),
      );

      await expectLater(
        container
            .read(xiangqiPuzzleRepositoryProvider)
            .complete(
              xiangqiTestPuzzleId,
              mistakes: 0,
              hintsUsed: 0,
              mode: XiangqiPuzzleAttemptMode.practice,
            ),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('XiangqiQuotaRepository', () {
    test('reads the allowances the server reports', () async {
      final container = await makeXiangqiPuzzleContainer(
        MockClient(
          (request) => respond(
            utf8.encode(
              jsonEncode(const {
                'user_type': 'free',
                'reset_in_seconds': 32022,
                'features': {
                  'puzzles': {'remaining': 3, 'limit': 15},
                  'puzzle_hints': {'remaining': 0, 'limit': 5},
                },
              }),
            ),
            200,
          ),
        ),
      );

      final state = await readKeepingAlive(container, xiangqiQuotaStateProvider);

      expect(state.userType, 'free');
      expect(state.resetIn, const Duration(seconds: 32022));
      expect(state.feature(kXiangqiQuotaPuzzles)!.remaining, 3);
      expect(state.feature(kXiangqiQuotaPuzzles)!.limit, 15);
      expect(state.feature(kXiangqiQuotaPuzzles)!.isExhausted, isFalse);
      expect(state.feature(kXiangqiQuotaPuzzleHints)!.isExhausted, isTrue);
      expect(state.feature('a_feature_that_does_not_exist'), isNull);
    });

    test('asks the server to spend an allowance, and reports what it said', () async {
      http.Request? sent;
      final container = await makeXiangqiPuzzleContainer(
        MockClient((request) {
          sent = request;
          return respond(
            utf8.encode(
              jsonEncode(const {
                'feature': 'puzzle_hints',
                'allowed': true,
                'remaining': 2,
                'reason': 'ok',
              }),
            ),
            200,
          );
        }),
      );

      final usage = await container
          .read(xiangqiQuotaRepositoryProvider)
          .consume(kXiangqiQuotaPuzzleHints);

      expect(sent!.method, 'POST');
      expect(sent!.url.toString(), 'https://api.xiangqi.com/api/quota/usage');
      expect(jsonDecode(sent!.body), {'feature': 'puzzle_hints'});
      expect(usage.allowed, isTrue);
      expect(usage.remaining, 2);
      expect(usage.reason, 'ok');
    });

    test('an exhausted allowance is an answer, not an error', () async {
      final container = await makeXiangqiPuzzleContainer(
        MockClient(
          (request) => respond(
            utf8.encode(
              jsonEncode(const {
                'feature': 'puzzle_hints',
                'allowed': false,
                'remaining': 0,
                'reason': 'exhausted',
              }),
            ),
            200,
          ),
        ),
      );

      final usage = await container
          .read(xiangqiQuotaRepositoryProvider)
          .consume(kXiangqiQuotaPuzzleHints);

      expect(usage.allowed, isFalse);
      expect(usage.reason, 'exhausted');
    });

    test('no session means no request', () async {
      var requests = 0;
      final container = await makeXiangqiPuzzleContainer(
        MockClient((request) {
          requests++;
          return respond(utf8.encode('{}'), 200);
        }),
        signedIn: false,
      );

      await expectLater(
        readKeepingAlive(container, xiangqiQuotaStateProvider),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0);
    });
  });
}
