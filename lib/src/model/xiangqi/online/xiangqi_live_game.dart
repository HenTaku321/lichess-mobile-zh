import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart' show XiangqiSide;
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

part 'xiangqi_live_game.freezed.dart';

/// One seat of a game being played on xiangqi.com, as the live list reports it.
///
/// Deliberately not `LightUser`, for the reason every xiangqi model here is its own: a xiangqi.com
/// account carries a country, a rating on xiangqi.com's own scale and a `p_type` that says whether
/// it is even a person, and none of those are lichess's fields. What the two share is a name and a
/// number, and those are shared by having the same names here.
@freezed
sealed class const XiangqiLivePlayer._() with _$XiangqiLivePlayer {
  const factory({
    /// The account id, as a string. A real account's id is a number on the wire and a guest's is the
    /// name the guest was given, so both are read as strings — the same rule
    /// `xiangqi_open_game.dart` follows when it matches a seat against a token's subject.
    required String id,

    /// The name to show, from `identity` rather than `username`.
    ///
    /// The two differ exactly when the account has hidden its name — `hidden_username` is the flag
    /// — and `identity` is the one the server itself prints in that case. Measured on
    /// `GET /api/v2/games/active` on 2026-10-16, where both fields were present on all twenty rows
    /// and equal on every one of them.
    required String name,

    /// The rating the list carries, or null when it carries none.
    int? rating,

    /// What this seat's clock reads, or null for a game with no clock.
    ///
    /// **Seconds left, not seconds used.** A `game_timer: 20` game was measured listing 423 and 281
    /// here, which is the same reading the `timers` object of a socket snapshot carries.
    int? secondsLeft,

    /// Whether this seat is a computer.
    ///
    /// `p_type` is `{AUTHENTICATED: 10, GUEST: 20, BOT: 30, GUEST_BOT: 40}` in the shipped bundle,
    /// and the two bot values are what this reads. A seat with no `p_type` at all is read as a
    /// person: the field is on every row measured, and a missing one is not evidence of a bot.
    required bool isBot,

    /// The country's name, or null when the account has not set one.
    String? countryName,

    /// The country's ISO code, or null. What a flag is drawn from.
    String? countryCode,
  }) = _XiangqiLivePlayer;
}

/// A game being played on xiangqi.com right now, as `GET /api/v2/games/active` lists it.
///
/// The counterpart of [XiangqiOpenGame], and the difference between the two is the whole reason
/// this class exists rather than that one being reused: an open game is one this device is in a seat
/// of, and this one is a game between two other people. Nothing here says whose turn it is *for the
/// reader*, because the reader is nobody in it.
///
/// There is no position. No REST list of xiangqi.com carries one — see `xiangqi_open_game.dart` for
/// the measurements — so a row of this list cannot draw a board, and the screen that shows it draws
/// the two names, the time control and the move count instead.
@freezed
sealed class const XiangqiLiveGame._() with _$XiangqiLiveGame {
  const factory({
    /// The game's id, which is what `g_v2.get` is asked for.
    required String id,

    required bool isRated,

    /// The total time each side gets, in seconds. `game_timer` is minutes on the wire.
    required int gameTimeSeconds,

    /// The increment each move adds, in seconds.
    required int incrementSeconds,

    /// How long a single move may take, in seconds. `move_timer` is minutes on the wire.
    required int moveTimeSeconds,

    /// How many plies have been played.
    required int movesCount,

    required XiangqiLivePlayer red,
    required XiangqiLivePlayer black,

    /// When the game started, or null when the list does not say.
    DateTime? startedAt,

    /// When the last move was played, or null before the first one.
    DateTime? lastMoveAt,
  }) = _XiangqiLiveGame;

  /// Which side is to move, read from the move count.
  ///
  /// Red opens every game and the two sides alternate, so an even number of plies played means red
  /// is to move. This is the rule the server's own `turn_now` follows — see
  /// `xiangqi_open_game.dart`, where the same fallback is documented — and it is the only rule
  /// available here, since this list carries no `turn_now`.
  XiangqiSide get turn => movesCount.isEven ? XiangqiSide.red : XiangqiSide.black;
}

/// The games `GET /api/v2/games/active` is listing, in the order it lists them.
///
/// **A bare JSON array, and always twenty of them.** Measured on 2026-10-16: the body is the list
/// itself rather than an object wrapping one, it held exactly twenty entries, and none of the twenty
/// was the signed-in account's own game. There is no page parameter in the shipped client's call
/// (`ke.T1(qe.Ay, "v2/games/active")` in `main.js`, with no options at all) and none was tried.
///
/// An entry this reader cannot place is dropped rather than guessed at, and a body that is not an
/// array at all is an empty list: a list this app cannot read is a list with nothing in it, not a
/// failure of the whole screen.
IList<XiangqiLiveGame> xiangqiLiveGamesFromJson(Object? json) {
  if (json is! List) return const IListConst<XiangqiLiveGame>([]);
  final games = <XiangqiLiveGame>[];
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) continue;
    final game = xiangqiLiveGameFromJson(entry);
    if (game != null) games.add(game);
  }
  return games.lock;
}

/// One entry of that array, or null when it cannot be placed.
///
/// ## The entry, as it was measured
///
/// A real entry, captured on 2026-10-16 from `GET /api/v2/games/active`. Fields this reader does not
/// use are dropped from the quote; nothing else is changed:
///
/// ```json
/// {
///   "id": "0VlPk47H3I",
///   "is_rated": true, "is_timed": true,
///   "game_timer": 20, "move_timer": 5, "increment": 5,
///   "moves_count": 144,
///   "timestamp": "2026-10-16T07:56:58.241092",
///   "last_move_time": "2026-10-16T08:37:27.313354",
///   "rplayer": {
///     "id": 157013, "username": "hmamoc891", "identity": "hmamoc891", "rating": 2815,
///     "p_type": 30, "side": 1, "seconds": 423, "result": -10, "factor": 0,
///     "country": {"name": "Viet Nam", "code": "VN"}
///   },
///   "bplayer": { "...": "" }
/// }
/// ```
///
/// Four things about that shape are worth stating outright, because each of them is a way this
/// reader could have been wrong:
///
/// * **The two seats are the same projection `v2/games/my-games` uses.** Every field name matches,
///   which is why the two lists can be read by two readers that agree on what a seat is — and why
///   neither of them has to unwrap anything.
/// * **`game_timer` and `move_timer` are minutes and `increment` is seconds.** The entry above reads
///   `game_timer: 20` with `seconds: 423` on a clock, which is the same game: twenty minutes is
///   twelve hundred seconds, and a game that has been running for a while has less than that left.
/// * **`result: -10` means the game is not over.** The bundle's own enum is
///   `{WAITING: -20, NO_RESULT: -10, LOST: 10, DRAW: 20, WON: 30}`, and every one of the twenty rows
///   measured carried `-10` on both seats. This reader does not read it: a row that is listed here
///   is a row being played, and the field is only ever the sentinel.
/// * **There is no `fen`, no `turn_now` and no `end_reason`.** The list is a summary of two clocks
///   and a move count. A row that needs the position has to ask the socket for that game's snapshot,
///   which is a different call from this one.
XiangqiLiveGame? xiangqiLiveGameFromJson(Map<String, dynamic> json) {
  final id = _string(json['id']);
  if (id == null) return null;

  final red = xiangqiLivePlayerFromJson(json['rplayer']);
  final black = xiangqiLivePlayerFromJson(json['bplayer']);
  // A game with a seat nobody is in is not a game being played. The live list has not been measured
  // with one — all twenty rows had both seats filled — but an empty seat is a shape this reader
  // knows from `my-games`, and a row that drew "Red vs Black" for two empty seats would be worse
  // than no row at all.
  if (red == null || black == null) return null;

  return XiangqiLiveGame(
    id: id,
    isRated: json['is_rated'] == true,
    gameTimeSeconds: (_int(json['game_timer']) ?? 0) * 60,
    incrementSeconds: _int(json['increment']) ?? 0,
    moveTimeSeconds: (_int(json['move_timer']) ?? 0) * 60,
    movesCount: _int(json['moves_count']) ?? 0,
    red: red,
    black: black,
    startedAt: _dateTime(json['timestamp']),
    lastMoveAt: _dateTime(json['last_move_time']),
  );
}

/// The seat [value] describes, or null when nobody is in it.
///
/// A seat nobody has taken is not a seat with an empty name — it is a seat whose fields are absent,
/// or the key with a null value — so an empty seat is one where both the id and the name are
/// missing. This is the same rule `xiangqi_open_game.dart` follows, restated here because the two
/// files do not share their private helpers.
///
/// Public because a seat is the same shape wherever a game is written down: the live list and the
/// archived snapshot a review is built from carry the very same object, and reading it twice would
/// be two chances to read it differently.
XiangqiLivePlayer? xiangqiLivePlayerFromJson(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final id = _string(value['id']) ?? '';
  final name = _string(value['identity']) ?? _string(value['username']) ?? '';
  if (id.isEmpty && name.isEmpty) return null;
  final country = value['country'];
  return XiangqiLivePlayer(
    id: id,
    name: name,
    rating: _int(value['rating']),
    secondsLeft: _int(value['seconds']),
    isBot: const {30, 40}.contains(_int(value['p_type'])),
    countryName: country is Map<String, dynamic> ? _string(country['name']) : null,
    countryCode: country is Map<String, dynamic> ? _string(country['code']) : null,
  );
}

/// The games being played on xiangqi.com right now, from `GET /api/v2/games/active`.
///
/// **A guest token is enough for this endpoint**, and that is what makes the watch list work for a
/// device that has never signed in to xiangqi.com: it is a public list of games between other
/// people. The fetch is therefore gated on the device being online and on nothing else — the same
/// arrangement `xiangqiUserProvider` uses, and for the same reason.
///
/// Offline, this throws a [StateError] rather than asking. An [Error] and not an [Exception],
/// deliberately: `lichessProviderRetry` never retries an [Error], so being offline is settled at
/// once instead of six times over with a back-off in between (see `utils/riverpod.dart`).
final xiangqiLiveGamesProvider = FutureProvider.autoDispose<IList<XiangqiLiveGame>>((
  Ref ref,
) async {
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw StateError('The device is offline; not asking xiangqi.com for the live games.');
  }

  final uri = xiangqiUri('v2/games/active');
  final response = await ref
      .read(xiangqiClientProvider)
      .get(uri, headers: const {'Accept': 'application/json'});

  if (response.statusCode >= 400) {
    throw ServerException(response.statusCode, 'xiangqi.com live games lookup failed.', uri, null);
  }

  // `Response.body` falls back to Latin-1 when the server sends no charset, which would mangle a
  // non-ASCII username — and this list is full of them; the bytes are what is actually on the wire.
  final Object? body;
  try {
    body = jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    throw const FormatException('xiangqi.com answered with something that is not JSON.');
  }

  return xiangqiLiveGamesFromJson(body);
}, name: 'XiangqiLiveGamesProvider');

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

/// The instant [value] names, or null if it is not one.
///
/// The wire spells its timestamps as ISO-8601 **without a timezone** (`"2026-10-16T07:56:58.241092"`),
/// which `DateTime.parse` reads as local time. A value this app cannot read is dropped rather than
/// turned into a made-up instant.
DateTime? _dateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}
