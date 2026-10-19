import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Client, Request, Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// The four time controls the lobby's own picker offers, in its order.
///
/// Each is a `(label, configStr)` pair. **The wire carries the string, not a number**: a game is
/// asked for with a `config_str`, and these are exactly the four strings xiangqi.com's own bundle
/// builds — see `xiangqi-com-re/docs/game.md`. The label is what the lobby prints, which is the
/// total time in minutes.
///
/// The string has two spellings, and which one is used is not a matter of taste: `<total>/<move>`
/// when there is no increment, `<total>+<move>/<increment>` when there is. All four values are in
/// **minutes** except the increment, which is in **seconds**.
enum XiangqiTimeControl(final String label, final String configStr) {
  five('5', '5/1'),
  ten('10', '10/2'),
  fifteen('15', '15+2/5'),
  twenty('20', '20+5/5');

  /// The default the lobby opens on.
  static const defaultControl = XiangqiTimeControl.ten;

  /// The total time this control gives each side.
  Duration get total => switch (this) {
    .five => const Duration(minutes: 5),
    .ten => const Duration(minutes: 10),
    .fifteen => const Duration(minutes: 15),
    .twenty => const Duration(minutes: 20),
  };

  /// How long each move may take.
  Duration get perMove => switch (this) {
    .five => const Duration(minutes: 1),
    .ten => const Duration(minutes: 2),
    .fifteen => const Duration(minutes: 2),
    .twenty => const Duration(minutes: 5),
  };

  /// The increment each move earns, if any.
  Duration? get increment => switch (this) {
    .five || .ten => null,
    .fifteen || .twenty => const Duration(seconds: 5),
  };
}

/// Which side a new game is asked for, and the number the wire takes for it.
///
/// `0` is what the site's own client sends for "either", and it is what the server is handed rather
/// than a side this app picked: the coin toss is the server's.
enum XiangqiSideChoice(final int wireValue) {
  red(1),
  either(0),
  black(2),
}

/// A custom game to create, in the shape `POST /api/v2/games/create-custom` takes.
///
/// **Every field here was measured**, and the three that are not obvious are worth naming: the
/// rating window is a **string** (`"50"`, `"100"`, `"200"`, `"Any"`), the times are **minutes**
/// except the increment which is **seconds**, and a daily game sends `move_time` alone, in minutes,
/// with `24 * days * 60` in it. This app offers the timed game only — see
/// `xiangqi-com-re/docs/game.md`.
@immutable
final class const XiangqiCustomGameRequest({
  required final XiangqiTimeControl timeControl,
  final XiangqiSideChoice side = XiangqiSideChoice.either,
  final bool rated = false,
  final bool private = true,
  final String ratingDiff = 'Any',

  /// The opponent's username, or null for an open challenge.
  final String? opponent,

  /// The opponent's email, or null. The two are exclusive on the wire.
  final String? opponentEmail,
}) {
  /// The body the endpoint takes.
  Map<String, Object?> toJson() {
    final (total, move, increment) = switch (timeControl) {
      .five => (5, 1, 0),
      .ten => (10, 2, 0),
      .fifteen => (15, 2, 5),
      .twenty => (20, 5, 5),
    };
    return {
      'is_rated': rated,
      'is_private': private,
      'is_daily': false,
      'is_timed': true,
      'side': side.wireValue,
      'opponent': opponent,
      'opponent_email': opponentEmail,
      'rating_diff': ratingDiff,
      'move_time': move,
      'game_time': total,
      'increment': increment,
    };
  }
}

/// Where a quick match has got to.
sealed class const XiangqiChallengeStatus();

/// Still looking.
final class const XiangqiChallengeSearching() extends XiangqiChallengeStatus;

/// An opponent was found and the game is [gameId].
final class const XiangqiChallengeMatched(final String gameId) extends XiangqiChallengeStatus;

/// One account that could be invited into a game.
///
/// The same user shape the rest of the site writes, read only for what an invite row draws.
@immutable
final class const XiangqiOnlinePlayer({
  required final int id,
  required final String username,
  final int? rating,
  final String? countryCode,
  final String? countryName,
  final String? profileImage,
});

/// The calls that start a game on xiangqi.com.
///
/// **A real account is needed for all of them**, which is why nothing here is a provider that can be
/// watched without one: a game has two seats and one of them is this account's.
class const XiangqiNewGameRepository(final Client _client) {
  /// Creates the custom game [request] describes.
  ///
  /// Answers the new game's id — measured on 2026-10-16, the answer is `{"game_id": "..."}` and the
  /// same id is what `v2/games/my-games` then lists.
  Future<String> createCustom(XiangqiCustomGameRequest request) async {
    final json = await _post('v2/games/create-custom', request.toJson());
    final id = _string(json['game_id']);
    if (id == null) {
      throw ServerException(
        200,
        'xiangqi.com created a game without naming it.',
        xiangqiUri('v2/games/create-custom'),
        null,
      );
    }
    return id;
  }

  /// Asks to be matched with somebody at [control].
  ///
  /// **The body is one field.** Everything else about the game is decided by the server from the
  /// `config_str` — see [XiangqiTimeControl.configStr]. The answer is
  /// `{"message": "Successfully scheduled request"}` and it means *queued*, not *playing*: the game
  /// id comes from [challengeStatus]. Measured on 2026-10-19; the site pairs within a couple of
  /// seconds, and with a bot when no person is queued.
  Future<void> quickChallenge(XiangqiTimeControl control) =>
      _post('v2/games/quick-challenge', {'config_str': control.configStr});

  /// Whether the quick match has found an opponent yet.
  ///
  /// The endpoint answers `{"message": "Search in progress..."}` while it is looking and
  /// `{"game_id": "..."}` once it has, which is the whole of the state machine.
  Future<XiangqiChallengeStatus> challengeStatus() async {
    final json = await _get('games/check-challenge-status', const {});
    final id = _string(json['game_id']);
    return id == null ? const XiangqiChallengeSearching() : XiangqiChallengeMatched(id);
  }

  /// Gives up on a quick match.
  Future<void> cancelQuickChallenge() => _get('games/cancel-quick-challenge', const {});

  /// Invites [username] into the game [gameId].
  ///
  /// Measured on 2026-10-19: the body is `{game_id, opponent}` and a name that does not exist is
  /// answered `400 {"message": "未找到对手"}` — the complaint is about the *opponent*, so the field
  /// names are right.
  Future<void> invite({required String gameId, required String username}) =>
      _post('v2/games/custom_game_invite', {'game_id': gameId, 'opponent': username});

  /// The accounts that could be invited into the game [gameId].
  ///
  /// A standard page envelope. `type` is accepted by the server and changes nothing this app could
  /// measure, so it is not sent — see `xiangqi-com-re/docs/game.md`.
  Future<IList<XiangqiOnlinePlayer>> onlineUsers({required String gameId, int page = 1}) async {
    final json = await _get('users/online_users', {'game_id': gameId, 'page': '$page'});
    final rows = json['items'];
    if (rows is! List) return const IListConst<XiangqiOnlinePlayer>([]);
    final players = <XiangqiOnlinePlayer>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = row['id'];
      final username = _string(row['username']);
      if (id is! num || username == null) continue;
      final country = row['country'];
      players.add(
        XiangqiOnlinePlayer(
          id: id.toInt(),
          username: username,
          rating: row['rating'] is num ? (row['rating'] as num).toInt() : null,
          countryCode: country is Map<String, dynamic> ? _string(country['code']) : null,
          countryName: country is Map<String, dynamic> ? _string(country['name']) : null,
          profileImage: _string(row['profile_image']),
        ),
      );
    }
    return players.lock;
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final uri = xiangqiUri(path, query.isEmpty ? null : query);
    final response = await _client.get(uri, headers: const {'Accept': 'application/json'});
    return _read(response, uri, path);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body) async {
    final uri = xiangqiUri(path);
    final response = await _client
        .send(
          Request('POST', uri)
            ..headers.addAll(const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            })
            ..body = jsonEncode(body),
        )
        .then(Response.fromStream);
    return _read(response, uri, path);
  }

  Map<String, dynamic> _read(Response response, Uri uri, String path) {
    if (response.statusCode >= 400) {
      throw ServerException(response.statusCode, 'xiangqi.com $path failed.', uri, null);
    }
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return json is Map<String, dynamic> ? json : const {};
    } catch (_) {
      throw FormatException('xiangqi.com answered $path with something that is not JSON.');
    }
  }
}

/// A provider for [XiangqiNewGameRepository].
final xiangqiNewGameRepositoryProvider = Provider<XiangqiNewGameRepository>((Ref ref) {
  return XiangqiNewGameRepository(ref.read(xiangqiClientProvider));
}, name: 'XiangqiNewGameRepositoryProvider');

/// Whether a game can be started at all: a real account, and a network to start it over.
///
/// Not a gate on the screens — the screens are what say *why* — but the one question every caller
/// asks before it offers to start anything.
final canStartXiangqiGameProvider = Provider<bool>((Ref ref) {
  final session = ref.watch(xiangqiAuthControllerProvider);
  return session != null && !session.isGuest && ref.watch(isDeviceOnlineProvider);
}, name: 'CanStartXiangqiGameProvider');

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}
