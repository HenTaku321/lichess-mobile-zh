import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// One speed's record for [username], from `GET /api/users/multiplayer_stats/<username>`.
///
/// **A guest token is enough for this endpoint**, the same way it is for the account lookup: it is a
/// public read of somebody else's record. The fetch is gated on the device being online and on
/// nothing else.
final xiangqiGameStatsProvider = FutureProvider.autoDispose
    .family<XiangqiGameStats, (String username, XiangqiRatingType type)>((ref, key) async {
      final (username, type) = key;
      return xiangqiGameStatsFromJson(
        _asMap(
          await _getJson(ref, 'users/multiplayer_stats/$username', {
            'rating_type': type.wireName,
            'days': '$kXiangqiStatsDays',
          }),
        ),
      );
    }, name: 'XiangqiGameStatsProvider');

/// An account's puzzle record, from `GET /api/users/puzzle_stats/<username>`.
final xiangqiPuzzleStatsProvider = FutureProvider.autoDispose.family<XiangqiPuzzleStats, String>((
  ref,
  username,
) async {
  return xiangqiPuzzleStatsFromJson(
    _asMap(
      await _getJson(ref, 'users/puzzle_stats/$username', {
        'rating_type': XiangqiRatingType.puzzle.wireName,
        'days': '$kXiangqiStatsDays',
      }),
    ),
  );
}, name: 'XiangqiPuzzleStatsProvider');

/// How far back the two stats endpoints are asked to look.
///
/// Ninety days, and it is a choice rather than a measurement: the endpoints take a window and the
/// app has no setting for one, so the number is the widest the screen has any use for. The
/// `rating_history` the window covers is not drawn yet — see `docs/profile.md`.
const int kXiangqiStatsDays = 90;

/// One page of a leaderboard, from `GET /api/leaders/v2/list`.
///
/// **An empty board is not a failure.** Measured on 2026-10-16, the three game boards answered
/// `total_players: 0` and `data: []` — the site is not running them — so a screen that treated an
/// empty board as an error would be reporting a fault where there is none. See
/// `xiangqi-com-re/docs/profile.md`.
final xiangqiLeaderboardProvider = FutureProvider.autoDispose
    .family<XiangqiLeaderboard, (XiangqiRatingType mode, String? country, int page)>((ref, key) {
      final (mode, country, page) = key;
      return _getJson(ref, 'leaders/v2/list', {
        'mode': _leaderboardModeOf(mode),
        'country': ?country,
        'page': '$page',
      }).then(xiangqiLeaderboardFromJson);
    }, name: 'XiangqiLeaderboardProvider');

/// One page of [username]'s finished games, from `GET /api/users/games/<username>`.
final xiangqiGameHistoryProvider = FutureProvider.autoDispose
    .family<XiangqiGameHistory, (String username, int page)>((ref, key) async {
      final (username, page) = key;
      return xiangqiGameHistoryFromJson(
        await _getJson(ref, 'users/games/$username', {'page': '$page'}),
      );
    }, name: 'XiangqiGameHistoryProvider');

/// The country table, from `GET /api/users/countries`.
///
/// Kept for the whole session rather than per screen: it is a static list of two hundred-odd rows
/// that changes about once a decade, and the leaderboard's country filter would otherwise refetch
/// it every time the filter was opened.
final xiangqiCountriesProvider = FutureProvider<IMap<String, String>>((ref) async {
  final json = await _getJson(ref, 'users/countries', const {});
  final countries = <String, String>{};
  if (json is List) {
    for (final row in json) {
      if (row is! Map<String, dynamic>) continue;
      final code = row['code'];
      final name = row['name'];
      if (code is String && name is String) countries[code] = name;
    }
  }
  return countries.lock;
}, name: 'XiangqiCountriesProvider');

/// The name `leaders/v2/list` files [mode] under.
///
/// The board names are the short ones — `rapid`, `bullet`, `daily`, `puzzle` — and not the
/// `rating_type` spellings the stats endpoints take. The two vocabularies are the server's own and
/// neither is derivable from the other, which is why this is a switch rather than a suffix.
String _leaderboardModeOf(XiangqiRatingType mode) => switch (mode) {
  .rapid => 'rapid',
  .bullet => 'bullet',
  .daily => 'daily',
  .puzzle => 'puzzle',
};

/// [value] as a string-keyed map, or an empty one when it is not one.
///
/// A body that is not an object is read as an object with nothing in it rather than as a failure:
/// every field of every model here is optional, so an empty map is a model with nothing filled in,
/// which is the honest reading of a payload that carried nothing.
Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

/// **No session is needed.** These endpoints answer a device that has never signed in to
/// xiangqi.com — measured on 2026-10-16, where every one of them answered `200` to a request with no
/// `Authorization` header at all. Gating them on a session would leave a screen that has nothing to
/// do with an account showing an error instead of what it asked for; see
/// `xiangqi-com-re/docs/api-map.md`.
///
/// Offline is still an [Error] rather than an empty answer, for the reason every other xiangqi
/// provider gives — `lichessProviderRetry` never retries an [Error], so being offline is settled at
/// once instead of six times over with a back-off in between.
Future<Object?> _getJson(Ref ref, String path, Map<String, String> query) async {
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw StateError('The device is offline; not asking xiangqi.com for $path.');
  }

  final uri = xiangqiUri(path, query.isEmpty ? null : query);
  final response = await ref
      .read(xiangqiClientProvider)
      .get(uri, headers: const {'Accept': 'application/json'});

  if (response.statusCode >= 400) {
    throw ServerException(response.statusCode, 'xiangqi.com $path lookup failed.', uri, null);
  }

  // `Response.body` falls back to Latin-1 when the server sends no charset, which would mangle a
  // non-ASCII username — and these payloads are full of them; the bytes are what is on the wire.
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    throw FormatException('xiangqi.com answered $path with something that is not JSON.');
  }
}
