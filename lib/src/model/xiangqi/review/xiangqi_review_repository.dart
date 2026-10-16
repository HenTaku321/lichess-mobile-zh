import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/review/xiangqi_review.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart' show XiangqiEvaluation;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:logging/logging.dart';

final _logger = Logger('XiangqiReviewRepository');

/// How long the server is given to answer `g_v2.review`.
///
/// Generously, and not because the request is slow to make: the answer is the **whole** analysis of
/// the game in one frame, and a 143-move game was measured answering with 144 verdicts at once. A
/// long game on a busy server is a big frame, and a timeout that fired on one would look like a
/// failure of the review rather than of the patience.
const kXiangqiReviewTimeout = Duration(seconds: 45);

/// The event a client sends to be given a game's analysis.
const String kXiangqiReviewEvent = 'g_v2.review';

/// The event the analysis comes back on.
const String kXiangqiReviewSuccessEvent = 'game.review.success';

/// What went wrong with a review, in the app's own terms.
///
/// Three cases, and the screen says something different for each: a device with no session cannot
/// ask at all, a device that is offline cannot reach the server, and a server that answered is a
/// failure of the review itself.
enum XiangqiReviewFailure() {
  /// There is no xiangqi.com session to ask with.
  noSession,

  /// The device is offline.
  offline,

  /// The socket, the request or the answer failed.
  failed,
}

/// Thrown when a review cannot be produced, carrying which of the three reasons it was.
class const XiangqiReviewException(final XiangqiReviewFailure reason) implements Exception {
  @override
  String toString() => 'XiangqiReviewException: ${reason.name}';
}

/// A finished game, analysed, from `g_v2.get` and `g_v2.review`.
///
/// ## Why this is not the online game controller
///
/// The online controller is built around a game being *played*: it holds a clock that runs, it
/// takes moves, it offers a resign. A review is a game that is over — the snapshot it reads carries
/// `state: 3` and an `end_reason` — and everything the live controller does with it after that is
/// noise. What the two share is the socket and the two events, and those are shared properly.
///
/// ## The two requests, and the redirect between them
///
/// `g_v2.get` is asked first, because a review needs the moves and the server sends the analysis
/// keyed by ply. **A finished game answers with a redirect**: the ack names the event to send
/// instead (`game.archived.get`, measured on 2026-10-16) and the same payload goes with it, and
/// only then does the snapshot arrive. That walk is the same one
/// `xiangqi_online_game_controller.dart` makes, and it is made again here rather than shared
/// because the two controllers have different lifetimes and a shared walk would be a shared
/// subscription.
final xiangqiReviewProvider = FutureProvider.autoDispose.family<XiangqiReview, String>((
  Ref ref,
  String gameId,
) async {
  if (ref.watch(xiangqiAuthControllerProvider) == null) {
    throw const XiangqiReviewException(XiangqiReviewFailure.noSession);
  }
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw const XiangqiReviewException(XiangqiReviewFailure.offline);
  }

  final socket = ref.read(xiangqiSocketProvider);
  final subscription = socket.stream.listen((_) {});
  ref.onDispose(subscription.cancel);

  try {
    await socket.connect();

    // The snapshot first: without the moves there is nothing for the analysis to be keyed against.
    final snapshot = await _snapshotOf(socket, gameId);
    final moves = xiangqiReviewMovesFromHistory(snapshot['move_history']);
    final initial = _positionOf(snapshot['initial_fen']);
    if (moves == null || initial == null) {
      _logger.warning('The snapshot of game $gameId did not replay.');
      throw const XiangqiReviewException(XiangqiReviewFailure.failed);
    }
    final positions = xiangqiReviewPositions(initial, moves);
    if (positions == null) {
      _logger.warning('The moves of game $gameId do not fit its own starting position.');
      throw const XiangqiReviewException(XiangqiReviewFailure.failed);
    }

    final analysis = await _analysisOf(socket, gameId, moves);

    return XiangqiReview(
      gameId: gameId,
      initialPosition: initial,
      positions: positions,
      moves: moves,
      reviews: analysis,
      red: xiangqiLivePlayerFromJson(snapshot['rplayer']),
      black: xiangqiLivePlayerFromJson(snapshot['bplayer']),
      endReason: _int(snapshot['end_reason']),
      endedAt: _httpDate(snapshot['endedAt']),
    );
  } on XiangqiReviewException {
    rethrow;
  } catch (error, stackTrace) {
    _logger.warning('The review of game $gameId failed.', error, stackTrace);
    throw const XiangqiReviewException(XiangqiReviewFailure.failed);
  }
}, name: 'XiangqiReviewProvider');

/// The game's snapshot, following the redirect a finished game answers with.
///
/// The subscription is opened **before** the first emit, and that is not tidiness: the server may
/// answer with the snapshot before it acks the request, and a listener attached afterwards would
/// miss it and then wait out the whole timeout for a frame that had already gone by.
///
/// The walk is a loop because a redirect is answered by sending the event the ack named — the
/// snapshot does not arrive on the redirect itself. The set of names already followed is what stops
/// a server redirecting in a circle.
Future<Map<String, dynamic>> _snapshotOf(XiangqiSocketClient socket, String gameId) async {
  // The names the snapshot may arrive under. `game.get.success` is the plain one and is what a
  // redirect is answered with too — measured on 2026-10-16, where `game.archived.get` came back as
  // `game.get.success` and not as `game.archived.get.success`. The derived name is kept as well
  // because the server is the one that chooses, and a name it chose is a name to listen for.
  final events = <String>{'game.get.success'};
  final snapshot = socket.stream.firstWhere((event) => events.contains(event.name));

  var name = 'g_v2.get';
  final followed = <String>{name};
  while (true) {
    final ack = _asMap(await socket.emit(name, data: {'game_id': gameId}));
    if (ack == null) throw const XiangqiReviewException(XiangqiReviewFailure.failed);
    final redirect = ack['event'];
    if (ack['status'] != 'REDIRECT' || redirect is! String || redirect.isEmpty) break;
    if (!followed.add(redirect)) throw const XiangqiReviewException(XiangqiReviewFailure.failed);
    events.add('$redirect.success');
    name = redirect;
  }

  final frame = await snapshot.timeout(kXiangqiReviewTimeout);
  final map = _asMap(_unwrap(frame.data));
  if (map == null) throw const XiangqiReviewException(XiangqiReviewFailure.failed);
  return map;
}

/// The game's analysis, from `g_v2.review`.
///
/// One emit, one frame, the whole game: the server answers `game.review.success` with an entry per
/// position and nothing else — there is no progress frame and no second call. See
/// `xiangqi-com-re/docs/review.md`.
Future<IList<XiangqiMoveReview>> _analysisOf(
  XiangqiSocketClient socket,
  String gameId,
  IList<XiangqiMove> moves,
) async {
  final answer = socket.stream
      .firstWhere((event) => event.name == kXiangqiReviewSuccessEvent)
      .timeout(kXiangqiReviewTimeout);
  await socket.emit(
    kXiangqiReviewEvent,
    data: {'game_id': gameId, 'skip_missions': true},
    timeout: kXiangqiReviewTimeout,
  );
  final frame = await answer;
  final data = _asMap(_unwrap(frame.data));
  final entries = data?['analysis'];
  if (entries is! List) throw const XiangqiReviewException(XiangqiReviewFailure.failed);

  final evaluations = <XiangqiEvaluation>[];
  final bestMoves = <XiangqiMove?>[];
  final depths = <int>[];
  for (var ply = 0; ply < entries.length; ply++) {
    final entry = entries[ply];
    if (entry is! Map<String, dynamic>) {
      throw const XiangqiReviewException(XiangqiReviewFailure.failed);
    }
    final score = _asMap(entry['s']);
    if (score == null) throw const XiangqiReviewException(XiangqiReviewFailure.failed);
    // The server's score is in the **side to move's** point of view, and the side to move at
    // position `ply` is the side that played that ply: red on the even ones. Everything above this
    // file reads an evaluation as red's, so the flip happens here, once — the same rule
    // `xiangqiEvaluationFromEngine` follows for the engine's own scores.
    final sideToMove = ply.isEven ? XiangqiSide.red : XiangqiSide.black;
    final cp = _int(score['cp']);
    final mate = _int(score['mate']);
    evaluations.add(
      XiangqiEvaluation(
        cp: cp == null ? null : (sideToMove == XiangqiSide.red ? cp : -cp),
        mate: mate == null ? null : (sideToMove == XiangqiSide.red ? mate : -mate),
      ),
    );
    bestMoves.add(xiangqiMoveFromComUci(_string(entry['bm']) ?? ''));
    depths.add(_int(entry['d']) ?? 0);
  }

  return xiangqiMoveReviewsFromAnalysis(
    moves: moves,
    evaluations: evaluations.lock,
    bestMoves: bestMoves.lock,
    depths: depths.lock,
  );
}

/// The position [value] names, or null when it is not one this app can read.
XiangqiPosition? _positionOf(Object? value) {
  final fen = _string(value);
  if (fen == null) return null;
  try {
    return XiangqiPosition.fromFen(fen);
  } catch (_) {
    return null;
  }
}

/// The snapshot a socket event carries, unwrapped from the two envelopes it arrives in.
///
/// Two, and both are real: the frame's payload is the single-element list a socket.io event always
/// is, and the snapshot inside it is nested one level further down under `data` — measured on
/// 2026-10-16, where `game.get.success` really arrived as `[{data: {...}}]`. A payload that is not
/// nested is returned as it stands, because a frame this app reads should not depend on which of
/// the two shapes the server chose.
Object? _unwrap(Object? data) {
  final first = data is List && data.isNotEmpty ? data.first : data;
  final map = _asMap(first);
  return map?['data'] ?? first;
}

Map<String, dynamic>? _asMap(Object? value) => value is Map<String, dynamic> ? value : null;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;

/// The instant an RFC-1123 HTTP-date names, or null if it cannot be read.
DateTime? _httpDate(Object? value) {
  if (value is! String) return null;
  try {
    return HttpDate.parse(value);
  } catch (_) {
    return null;
  }
}
