import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// One page of the master-games player list, from `GET /api/master-games/players`.
///
/// [search] filters by name when it is not empty, which the endpoint takes as its own
/// `players/search` path rather than as a parameter on the list — see
/// `xiangqi-com-re/docs/database.md`.
final xiangqiMasterPlayersProvider = FutureProvider.autoDispose
    .family<XiangqiMasterPage<XiangqiMasterPlayer>, (String? search, int page)>((ref, key) async {
      final (search, page) = key;
      final path = search == null || search.isEmpty
          ? 'master-games/players'
          : 'master-games/players/search';
      return xiangqiMasterPlayersFromJson(
        await _getJson(ref, path, {
          if (search != null && search.isNotEmpty) 'q': search,
          'locale': _locale,
          'page': '$page',
        }),
      );
    }, name: 'XiangqiMasterPlayersProvider');

/// One player's record, from `GET /api/master-games/players/<id>/stats`.
final xiangqiMasterStatsProvider = FutureProvider.autoDispose.family<XiangqiMasterStats, int>((
  ref,
  id,
) async {
  return xiangqiMasterStatsFromJson(
    await _getJson(ref, 'master-games/players/$id/stats', {'locale': _locale}),
  );
}, name: 'XiangqiMasterStatsProvider');

/// One page of a player's games, from `GET /api/master-games/players/<id>/games`.
final xiangqiMasterGamesProvider = FutureProvider.autoDispose
    .family<XiangqiMasterPage<XiangqiMasterGameRow>, (int playerId, int page)>((ref, key) async {
      final (playerId, page) = key;
      return xiangqiMasterGamesFromJson(
        await _getJson(ref, 'master-games/players/$playerId/games', {
          'locale': _locale,
          'page': '$page',
        }),
      );
    }, name: 'XiangqiMasterGamesProvider');

/// One game out of the database, from `GET /api/master-games/games/<slug>`.
final xiangqiMasterGameProvider = FutureProvider.autoDispose.family<XiangqiMasterGame, String>((
  ref,
  slug,
) async {
  final json = await _getJson(ref, 'master-games/games/$slug', {'locale': _locale});
  final game = xiangqiMasterGameFromJson(json);
  if (game == null) {
    throw ServerException(
      200,
      'xiangqi.com answered the game with something else.',
      xiangqiUri('master-games/games/$slug'),
      null,
    );
  }
  return game;
}, name: 'XiangqiMasterGameProvider');

/// The language the database is asked to name things in.
///
/// Fixed rather than taken from the device: the fields this app reads are names of people and
/// tournaments, which the server does not translate, and the one field it might — an opening's name
/// — was measured as `"-"` on every game this project has seen. Asking for a language the app is
/// not showing would be asking for something it does not use.
const String _locale = 'en';

Future<Object?> _getJson(Ref ref, String path, Map<String, String> query) async {
  if (ref.watch(xiangqiAuthControllerProvider) == null) {
    throw StateError('No xiangqi.com session; not asking for $path.');
  }
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
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    throw FormatException('xiangqi.com answered $path with something that is not JSON.');
  }
}
