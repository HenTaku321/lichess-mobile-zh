import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page_selection.dart';
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
    .family<XiangqiMasterPage<XiangqiMasterPlayer>, ({String? search, int page, String locale})>((
      ref,
      key,
    ) async {
      final (:search, :page, :locale) = key;
      final path = search == null || search.isEmpty
          ? 'master-games/players'
          : 'master-games/players/search';
      return xiangqiMasterPlayersFromJson(
        await _getJson(ref, path, {
          if (search != null && search.isNotEmpty) 'q': search,
          'locale': locale,
          'page': '$page',
        }),
      );
    }, name: 'XiangqiMasterPlayersProvider');

final xiangqiMasterPlayersControllerProvider = AsyncNotifierProvider.autoDispose
    .family<
      XiangqiMasterPlayersController,
      XiangqiSelectedPage<XiangqiMasterPage<XiangqiMasterPlayer>>,
      ({String? search, String locale})
    >(XiangqiMasterPlayersController.new, name: 'XiangqiMasterPlayersControllerProvider');

class XiangqiMasterPlayersController(final ({String? search, String locale}) key)
    extends XiangqiPageSelectionController<XiangqiMasterPage<XiangqiMasterPlayer>> {
  @override
  Future<XiangqiMasterPage<XiangqiMasterPlayer>> loadPage(int number) async {
    final (:search, :locale) = key;
    final json = await _getJson(
      ref,
      search == null || search.isEmpty ? 'master-games/players' : 'master-games/players/search',
      {'q': ?search, 'locale': locale, 'page': '$number'},
      watchConnectivity: false,
    );
    if (json is! Map<String, dynamic> || json['items'] is! List) {
      throw const FormatException('Invalid xiangqi.com master player page envelope.');
    }
    final result = xiangqiMasterPlayersFromJson(json);
    XiangqiPage.fromMetadata(items: result.items, requestedPage: number, metadata: json);
    return result;
  }

  @override
  int? totalPages(XiangqiMasterPage<XiangqiMasterPlayer> page) => page.totalPages;
  @override
  bool isEmpty(XiangqiMasterPage<XiangqiMasterPlayer> page) => page.items.isEmpty;
}

/// One player's record, from `GET /api/master-games/players/<id>/stats`.
final xiangqiMasterStatsProvider = FutureProvider.autoDispose
    .family<XiangqiMasterStats, ({int id, String locale})>((ref, key) async {
      final (:id, :locale) = key;
      return xiangqiMasterStatsFromJson(
        await _getJson(ref, 'master-games/players/$id/stats', {'locale': locale}),
      );
    }, name: 'XiangqiMasterStatsProvider');

/// One page of a player's games, from `GET /api/master-games/players/<id>/games`.
final xiangqiMasterGamesProvider = FutureProvider.autoDispose
    .family<XiangqiMasterPage<XiangqiMasterGameRow>, ({int playerId, int page, String locale})>((
      ref,
      key,
    ) async {
      final (:playerId, :page, :locale) = key;
      return xiangqiMasterGamesFromJson(
        await _getJson(ref, 'master-games/players/$playerId/games', {
          'locale': locale,
          'page': '$page',
        }),
      );
    }, name: 'XiangqiMasterGamesProvider');

/// One game out of the database, from `GET /api/master-games/games/<slug>`.
final xiangqiMasterGameProvider = FutureProvider.autoDispose
    .family<XiangqiMasterGame, ({String slug, String locale})>((ref, key) async {
      final (:slug, :locale) = key;
      final json = await _getJson(ref, 'master-games/games/$slug', {'locale': locale});
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

/// **No session is needed.** These endpoints answer a device that has never signed in to
/// xiangqi.com — measured on 2026-10-16, where every one of them answered `200` to a request with no
/// `Authorization` header at all. Gating them on a session would leave a screen that has nothing to
/// do with an account showing an error instead of what it asked for; see
/// `xiangqi-com-re/docs/api-map.md`.
///
/// Offline is still an [Error] rather than an empty answer, for the reason every other xiangqi
/// provider gives — `lichessProviderRetry` never retries an [Error], so being offline is settled at
/// once instead of six times over with a back-off in between.
Future<Object?> _getJson(
  Ref ref,
  String path,
  Map<String, String> query, {
  bool watchConnectivity = true,
}) async {
  final online = watchConnectivity
      ? ref.watch(isDeviceOnlineProvider)
      : ref.read(isDeviceOnlineProvider);
  if (!online) {
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
