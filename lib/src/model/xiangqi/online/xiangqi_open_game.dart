import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:logging/logging.dart';

part 'xiangqi_open_game.freezed.dart';

final _logger = Logger('XiangqiOpenGame');

/// A game the signed-in user is currently playing on xiangqi.com.
///
/// This is the xiangqi counterpart of [OngoingGame], not a translation of it:
/// xiangqi.com hands out its own side names (red and black, via [XiangqiSide]),
/// its own clock and its own move count, and it has no variant, no perf and no
/// speed. Only the two fields the merged list actually needs — [isMyTurn] and
/// the two clocks — line up with the chess model, and they line up by meaning,
/// not by shape, so they are carried here rather than derived from a shared
/// scalar.
@freezed
sealed class const XiangqiOpenGame._() with _$XiangqiOpenGame {
  const factory({
    required String id,
    required bool isRated,

    /// The side this user plays, derived by matching the `rplayer`/`bplayer` id
    /// against the JWT `sub`.
    required XiangqiSide mySide,
    required int gameTimeSeconds,
    required int incrementSeconds,

    /// The other seat, or null while nobody is in it.
    ///
    /// Nullable for the same reason `OngoingGame.opponent` is: a game the user
    /// has opened but nobody has joined is one of the user's ongoing games, and
    /// it has no opponent yet to name.
    LightUser? opponent,
    int? opponentRating,
    required bool isMyTurn,
    required int movesCount,
    required String fen,
    int? redSecondsLeft,
    int? blackSecondsLeft,
  }) = _XiangqiOpenGame;
}

/// The games a `GET /api/v2/games/my-games` body holds, in the order it lists them.
///
/// The body is a **bare JSON array** — the list itself, not an object wrapping one. Measured on
/// 2026-10-15: a guest session is answered `200` with `[]`, and the shipped client stores the parsed
/// body as its own `myGames` list without unwrapping anything (`Yi = games => ({type: fx, games})`
/// feeding `d.set("myGames", v.games)` in `main.js`).
///
/// An entry this reader cannot place is dropped rather than guessed at — see
/// [xiangqiOpenGameFromJson] — and a body that is not an array at all is an empty list, because a
/// list this app cannot read is a list with nothing in it, not a failure of the whole screen.
IList<XiangqiOpenGame> xiangqiOpenGamesFromJson(Object? json, {required String? myUserId}) {
  if (json is! List) return const IListConst<XiangqiOpenGame>([]);
  final games = <XiangqiOpenGame>[];
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) continue;
    final game = xiangqiOpenGameFromJson(entry, myUserId: myUserId);
    if (game != null) games.add(game);
  }
  return games.lock;
}

/// One entry of that array, or null when it cannot be placed.
///
/// ## The entry, as it was measured
///
/// A real entry, captured on 2026-10-15 from `GET /api/v2/games/my-games` with a signed-in account
/// and a private game of its own waiting for an opponent. Fields this reader does not use are
/// dropped from the quote; nothing else is changed:
///
/// ```json
/// {
///   "id": "YKeIzcBbtY",
///   "rplayer": {
///     "id": 536174, "username": "astralisxq", "identity": "astralisxq",
///     "rating": 900, "seconds": 600, "side": 1, "p_type": 10, "factor": 0, "result": -10,
///     "country": {"name": "Hong Kong, China", "code": "HK"}
///   },
///   "bplayer": null,
///   "game_timer": 10, "increment": 0, "move_timer": 2, "moves_count": 0,
///   "is_timed": true, "is_rated": false,
///   "timestamp": "2026-10-15T14:06:20.089295", "last_move_time": null
/// }
/// ```
///
/// Four things about that shape are worth stating outright, because each of them is a way this
/// reader could have been wrong:
///
/// * **`bplayer` is `null`, not an empty object.** A seat nobody has taken is the key with a null
///   value, and there is no `username: ""` to read. [_seat] answers an empty seat for both, which
///   is what makes the waiting-for-an-opponent row work.
/// * **There is no `fen` and no `turn_now`.** The list is a summary of the two clocks and the move
///   count; the position is not in it. Nothing in this file assumes otherwise — see below.
/// * **`game_timer` is minutes and `increment` is seconds.** This entry reads `game_timer: 10` and
///   `rplayer.seconds: 600`, which is the same game: ten minutes is six hundred seconds. The
///   sibling `GET /api/v2/games/active` projection agrees — a `game_timer: 15, increment: 5` game
///   was listed with 577 s and 660 s left on its clocks 841 s after it started, which is fifteen
///   minutes plus the increments and not fifteen seconds plus them.
/// * **There is no `end_reason` key at all** on a game still being played. Measured separately on
///   `GET /api/users/games/<username>`, the same key is `null` on the one live game in that list
///   and a code on every finished one.
///
/// ## The position, and why this reader does not have one
///
/// No REST endpoint of xiangqi.com carries a game's position. `v2/games/my-games`,
/// `v2/games/active` and `users/games/<username>` were each measured with a game in them, and none
/// of the three has a `fen`; the shapes `v2/games/<id>`, `v2/game/<id>`, `games/<id>` and four more
/// spellings of the same idea all answer `404`. The only place a position exists is the socket's
/// `game.get.success` snapshot.
///
/// So [XiangqiOpenGame.fen] is the starting position on every row this reader builds, and the log
/// line below says so at [Level.FINE] rather than as a warning: it is not an anomaly to be
/// investigated, it is the shape of the endpoint. A row that needs the real position has to ask the
/// socket for that game's snapshot, and that is a different call from this one.
///
/// ## The two reads that are the client's own field names
///
/// [isMyTurn] prefers `turn_now` — the field the server names the side to move in on the socket —
/// and falls back to `moves_count` parity when the list does not carry it, which is every row
/// measured so far. The parity rule is the server's own: red opens every game and the sides
/// alternate, so an even number of plies played means red is to move.
XiangqiOpenGame? xiangqiOpenGameFromJson(Map<String, dynamic> json, {required String? myUserId}) {
  final id = _string(json['id']);
  if (id == null) return null;

  // A game that is over is not an ongoing game. `end_reason` is where the server writes that down:
  // measured on `GET /api/users/games/<username>`, a game still being played carries `null` there
  // and a finished one a code. A list that still holds a finished game is a list to filter.
  if (json['end_reason'] != null) return null;

  final red = _seat(json['rplayer']);
  final black = _seat(json['bplayer']);
  final mySide = _sideOf(red, black, myUserId);
  // A row this device is not in is not this device's game. The side is what orients the board and
  // decides which clock the row counts down, so a row that cannot be placed is left out rather than
  // given a side it might not have.
  if (mySide == null) return null;

  final otherSeat = mySide == XiangqiSide.red ? black : red;
  final invitee = _seat(json['invitee']);
  // The other seat first, then the invitee: a challenge this user sent has nobody in the other seat
  // yet, and the person it was sent to is the opponent the row is about. An invitee that is this
  // user is a challenge *to* them, which the client reads as the other seat being the opponent.
  final opponent = otherSeat.isTaken
      ? otherSeat
      : (invitee.isTaken && invitee.id != myUserId ? invitee : null);

  // Expected, not exceptional: no REST list of xiangqi.com carries a position, so every row this
  // reader builds falls back here. See the doc comment on this function.
  final fen = _string(json['fen']);
  if (fen == null) {
    _logger.fine('The xiangqi.com list entry for game $id carried no position.');
  }

  return XiangqiOpenGame(
    id: id,
    isRated: json['is_rated'] == true,
    mySide: mySide,
    // `game_timer` is minutes. An entry that carries none is an untimed game, which this model has
    // no way to say: it reads as `0+0` rather than as a game that is not there.
    gameTimeSeconds: (_int(json['game_timer']) ?? 0) * 60,
    incrementSeconds: _int(json['increment']) ?? 0,
    opponent: opponent == null ? null : LightUser(id: UserId(opponent.id), name: opponent.name),
    opponentRating: opponent?.rating,
    isMyTurn: _isMyTurn(
      mySide: mySide,
      hasOpponent: opponent != null,
      turnNow: _string(json['turn_now']),
      movesCount: _int(json['moves_count']),
    ),
    movesCount: _int(json['moves_count']) ?? 0,
    fen: fen ?? kXiangqiInitialFen,
    redSecondsLeft: red.seconds,
    blackSecondsLeft: black.seconds,
  );
}

/// Whether it is this device's move.
///
/// `turn_now` is the field the server names the side to move in — measured in the `g_v2.get`
/// snapshot and in the `game.move.*` frames — and it wins whenever it is there. A list entry that
/// does not carry it is read from `moves_count` instead: red opens every game and the two sides
/// alternate, so the side to move is red after an even number of plies and black after an odd one.
/// That is the same rule the server's own `turn_now` follows, which is why the two readings agree
/// wherever both are available.
///
/// A game with nobody in the other seat is nobody's move: it is waiting for an opponent, and a row
/// that said "your turn" for it would be asking for a move that cannot be played.
bool _isMyTurn({
  required XiangqiSide mySide,
  required bool hasOpponent,
  required String? turnNow,
  required int? movesCount,
}) {
  if (!hasOpponent) return false;
  if (turnNow != null) return turnNow == mySide.name;
  if (movesCount == null) return false;
  return (movesCount.isEven ? XiangqiSide.red : XiangqiSide.black) == mySide;
}

/// One of the two seats of a list entry: who is in it, how strong they are, and what their clock
/// reads.
///
/// A seat nobody has taken is not a seat with an empty name — it is a seat whose fields are absent
/// — so [isTaken] is asked of both the id and the name rather than of either alone.
typedef _Seat = ({String id, String name, int? rating, int? seconds});

extension on _Seat {
  bool get isTaken => id.isNotEmpty || name.isNotEmpty;
}

/// The seat [value] describes, or an empty seat when it describes none.
_Seat _seat(Object? value) {
  if (value is! Map<String, dynamic>) return (id: '', name: '', rating: null, seconds: null);
  return (
    id: _string(value['id']) ?? '',
    name: _string(value['username']) ?? '',
    rating: _int(value['rating']),
    seconds: _int(value['seconds']),
  );
}

/// Which side this device plays, by matching the token's subject against the two seats' ids.
///
/// Null for a game this device is in neither seat of. Ids are compared as strings because the wire
/// spells them both ways: a real account's id is a number (`457524`) and a guest's is the string the
/// guest was named with (`guest7zuq8`), while the token's `sub` is read as a string either way.
XiangqiSide? _sideOf(_Seat red, _Seat black, String? myUserId) {
  if (myUserId == null || myUserId.isEmpty) return null;
  if (red.id == myUserId) return XiangqiSide.red;
  if (black.id == myUserId) return XiangqiSide.black;
  return null;
}

/// [value] as a non-empty string, or null.
///
/// Numbers are accepted as well as strings: an account id is a JSON number on some payloads and the
/// same id is a string on others, and both spell the same account.
String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

/// [value] as an integer, or null. A JSON number may arrive as a double, so both are accepted.
int? _int(Object? value) => value is num ? value.toInt() : null;
