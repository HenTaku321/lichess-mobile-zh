// The puzzle payloads below are the *shapes* the 2026-10-15/16 probe measured against
// xiangqi.com — the key names, the rank-0 move spelling, the enums, the 429 envelope — with every
// value replaced. Not one puzzle id, rating, FEN or move here is the capture's.
//
// The position is not typed out either, and that is the point: the opening is played through this
// repository's own rules engine, the blunder is the first legal move in the position that reaches,
// and the answer is a line of legal moves played on from there. A fixture that could not be played
// would throw while this file loaded, so the parser is never handed a position no board could hold
// and the tests below are about the wire rather than about a string someone wrote down.
//
// What is *not* here is a good puzzle: the moves are the first the generator found, not a tactic. A
// puzzle's quality is not something this reader reads.

import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';

import '../../../network/fake_http_client_factory.dart';
import '../../../test_container.dart';

/// The puzzle id every payload here carries.
///
/// Six characters, the shape the wire uses, and a stand-in: the capture's own ids are not reused.
const xiangqiTestPuzzleId = 'AbCdEf';

/// The opening the fixture position is reached through, in this repo's ICCS.
///
/// Four plies of an ordinary opening, so that the position is neither the start of the game nor a
/// position either side has already won. Played through [rules.play], so a wrong one is loud.
const _openingIccs = ['h2e2', 'h9g7', 'h0g2', 'i9h9'];

/// How many moves the answer has after the blunder.
///
/// Even, which makes the line end on the solver's opponent's move — the shape the capture's own
/// `ReQaXR` had, where three solver moves are answered three times. The odd shape, a line that ends
/// on the solver's own move, is exercised by truncating the payload rather than by a second fixture.
const _answerLength = 4;

/// The fixture line: the position before the blunder, the blunder, and the whole answer with it.
final xiangqiTestLine = _buildFixture();

/// The rating the payload claims, and a stand-in for the capture's own.
const xiangqiTestPuzzleRating = 1500;

/// The account's own puzzle rating in the payload, likewise a stand-in.
const xiangqiTestUserRating = 1200;

/// The fixture line, as the reader reads it.
///
/// Parsed from the same payload the tests below hand the reader, so a test that drives the
/// controller is driving the puzzle the wire would really have produced.
final xiangqiTestPuzzle = xiangqiPuzzleFromJson(xiangqiPuzzlePayload().cast<String, dynamic>())!;

/// The same puzzle with the server's answer withheld.
///
/// The shape a `429` carries once the day's puzzles are spent: the position comes back, the answer
/// does not. See `xiangqi-com-re/docs/quota.md`.
final xiangqiTestPuzzleWithoutAnswer = xiangqiPuzzleFromJson(
  xiangqiPuzzlePayload(modelAnswer: null).cast<String, dynamic>(),
)!;

/// A response carrying [body] as UTF-8 bytes, which is what the xiangqi.com client reads.
///
/// `http.Response(body)` would encode a `String` as Latin-1 and throw on anything non-ASCII, so the
/// bytes are built here the way the real server sends them: UTF-8, with no charset in the headers.
Future<http.Response> xiangqiJsonResponse(String body, int status) =>
    Future.value(http.Response.bytes(utf8.encode(body), status));

/// A session, so that the providers that refuse to ask without one have one to find.
///
/// **A real account and not a guest**, because the puzzle domain needs one: the search and the fetch
/// are open to anybody, but `complete` and `quota/usage` are `401` to a guest — measured on
/// 2026-10-16 — so the screen and its providers gate on [isXiangqiLoggedInProvider] rather than on
/// "any session". A fixture that handed them a guest would be testing a state the screen never
/// reaches.
const xiangqiTestSession = XiangqiSession(
  userId: '100001',
  name: 'a-player',
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  isGuest: false,
);

/// A stand-in for "this argument was not given".
///
/// The payload below has a default for every key, and most of those defaults are not null — so a
/// parameter that defaulted to null could not tell "leave the key out" from "put a null in it", and
/// the null cases are half of what the tests are about. Passing [_unset] means the default; passing
/// null means null.
const _unset = Object();

/// A puzzle payload with the measured key set and this file's own values.
///
/// Every parameter is a way to take one of the measured keys away or to change its shape, which is
/// what the tests below are about; the defaults are the shape a `200` from
/// `GET /api/puzzle/P/<id>` really has.
Map<String, Object?> xiangqiPuzzlePayload({
  Object? puzzleId = _unset,
  Object? title = _unset,
  Object? rating = _unset,
  Object? theme = _unset,
  Object? fullMoves = _unset,
  Object? initialFen = _unset,
  Object? playerTurn = _unset,
  Object? blunderMove = _unset,
  Object? modelAnswer = _unset,
  Object? tags = _unset,
  Object? state = _unset,
  Object? passRate = _unset,
  Object? attempt = _unset,
}) => {
  'puzzle_id': puzzleId == _unset ? xiangqiTestPuzzleId : puzzleId,
  'title': title == _unset ? null : title,
  'rating': rating == _unset ? xiangqiTestPuzzleRating : rating,
  'theme': theme == _unset ? 2 : theme,
  'full_moves': fullMoves == _unset ? xiangqiTestLine.solution.length ~/ 2 : fullMoves,
  'initial_fen': initialFen == _unset ? xiangqiTestLine.before.toFen() : initialFen,
  'player_turn': playerTurn == _unset ? 2 : playerTurn,
  'blunder_move': blunderMove == _unset ? xiangqiTestLine.blunder.iccs : blunderMove,
  'model_answer': modelAnswer == _unset
      ? xiangqiTestLine.answer.map((move) => move.iccs).toList()
      : modelAnswer,
  'tags': tags == _unset ? const <Object?>[] : tags,
  'state': state == _unset ? 300 : state,
  'pass_rate': passRate == _unset ? 50.0 : passRate,
  'attempt': attempt == _unset
      ? const {
          'status': 1,
          'p_rating': xiangqiTestPuzzleRating,
          'u_rating': xiangqiTestUserRating,
          'win_factor': 20,
          'lose_factor': -20,
          'u_correct_rate': 0,
        }
      : attempt,
};

/// The body a `429` from `GET /api/puzzle/P/<id>` really carries, once the day's puzzles are spent.
///
/// The envelope is the measured one and the nested puzzle is the same payload as a `200` would
/// carry, with `model_answer` struck out — which is exactly what the server does: the position comes
/// back, the answer does not. See `xiangqi-com-re/docs/quota.md`.
Map<String, Object?> xiangqiPuzzleQuotaExceededBody() => {
  'error': 'quota_exceeded',
  'feature': 'puzzles',
  'remaining': 0,
  'reason': 'exhausted',
  'puzzle': xiangqiPuzzlePayload(modelAnswer: null),
};

/// A container whose xiangqi client is stubbed at the HTTP layer, with a session in hand.
///
/// The session is put in place through [XiangqiAuthController.checkToken] rather than by overriding
/// the controller: the storage provider is a plain provider and the controller is not, so the fake
/// store is what AGENTS.md allows and the real controller is what ends up holding the session.
Future<ProviderContainer> makeXiangqiPuzzleContainer(
  MockClient client, {
  bool signedIn = true,
  bool offline = false,
  Duration replyDelay = Duration.zero,
}) async {
  final container = await makeContainer(
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => client);
      }),
      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
        (ref) => FakeXiangqiAuthStorage(signedIn ? xiangqiTestSession : null),
      ),
      xiangqiPuzzleReplyDelayProvider: xiangqiPuzzleReplyDelayProvider.overrideWithValue(
        replyDelay,
      ),
      if (offline) isDeviceOnlineProvider: isDeviceOnlineProvider.overrideWithValue(false),
    },
  );
  // A subscription, not a read: an `autoDispose` provider that nothing listens to is thrown away
  // between two reads, and the session would go with it.
  final subscription = container.listen(xiangqiAuthControllerProvider, (_, _) {});
  addTearDown(subscription.close);
  await container.read(xiangqiAuthControllerProvider.notifier).checkToken();
  return container;
}

/// Waits until [condition] holds, or fails the test.
///
/// The controller plays the opponent's answer on a timer and submits on a future, so a test that
/// only awaited the move it made would be reading the state in the middle of the line. Polling is
/// what the socket tests do for the same reason; the deadline is what stops a broken controller from
/// hanging the suite.
Future<void> waitUntil(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for ${reason ?? 'the controller'}.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Reads [provider]'s first value, keeping the provider alive for the rest of the test.
///
/// A bare `container.read(provider.future)` does **not** hold an `autoDispose` provider open: the
/// temporary subscription is closed as soon as the read returns, and a provider disposed while its
/// request is still in flight completes its future with a disposal error instead of the answer —
/// which is a test harness artefact and not something the app ever sees, since a screen watches the
/// provider it reads. Every test reads through here so that what it asserts on is the answer.
Future<T> readKeepingAlive<T>(ProviderContainer container, FutureProvider<T> provider) {
  final subscription = container.listen(provider, (_, _) {});
  addTearDown(subscription.close);
  return container.read(provider.future);
}

/// A session store that never touches the disk.
class FakeXiangqiAuthStorage([var XiangqiSession? session]) implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession value) async => session = value;

  @override
  Future<void> delete() async => session = null;
}

/// The fixture, built by playing legal moves.
///
/// Returns the position **before** the blunder, the blunder itself, and the whole answer with the
/// blunder first — the three things a payload is made of.
({
  XiangqiPosition before,
  XiangqiMove blunder,
  IList<XiangqiMove> answer,
  IList<XiangqiMove> solution,
})
_buildFixture() {
  var position = XiangqiPosition.initial();
  for (final iccs in _openingIccs) {
    final move = XiangqiMove.parseIccs(iccs);
    if (move == null) throw ArgumentError('Not a move: $iccs');
    position = rules.play(position, move);
  }

  final before = position;
  final blunder = rules.legalMoves(position).first;
  var after = rules.play(position, blunder);

  final answer = <XiangqiMove>[blunder];
  for (var i = 0; i < _answerLength; i++) {
    final move = rules.legalMoves(after).first;
    answer.add(move);
    after = rules.play(after, move);
  }

  return (
    before: before,
    blunder: blunder,
    answer: answer.lock,
    solution: answer.skip(1).toIList(),
  );
}
