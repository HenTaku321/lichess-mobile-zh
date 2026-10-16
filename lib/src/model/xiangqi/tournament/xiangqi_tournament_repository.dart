import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/tournament/xiangqi_tournament.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// The tournaments, from `GET /api/tournament/list`.
///
/// **Two arrays and not a page**: the endpoint splits them itself and takes no page parameter. See
/// `xiangqi-com-re/docs/tournament.md`.
final xiangqiTournamentsProvider = FutureProvider.autoDispose<XiangqiTournaments>((ref) async {
  return xiangqiTournamentsFromJson(await _getJson(ref, 'tournament/list', const {}));
}, name: 'XiangqiTournamentsProvider');

/// One tournament, from `GET /api/tournament/<id>`.
///
/// The three fields the list does not carry — `can_register`, `user_can_join`, `user_has_joined` —
/// are this account's own, which is why the detail is a call of its own and not a row the list
/// already had.
final xiangqiTournamentProvider = FutureProvider.autoDispose.family<XiangqiTournament, String>((
  ref,
  id,
) async {
  final json = await _getJson(ref, 'tournament/$id', const {});
  final tournament = xiangqiTournamentFromJson(json);
  if (tournament == null) {
    throw ServerException(
      200,
      'xiangqi.com answered the tournament with something else.',
      xiangqiUri('tournament/$id'),
      null,
    );
  }
  return tournament;
}, name: 'XiangqiTournamentProvider');

/// A tournament's standings, from `GET /api/tournament/<id>/leaders?page=`.
///
/// The list key is `participants` and not the `items` every other page uses — measured on
/// 2026-10-16.
final xiangqiTournamentLeadersProvider = FutureProvider.autoDispose
    .family<XiangqiMasterPageLike<XiangqiTournamentParticipant>, (String id, int page)>((
      ref,
      key,
    ) async {
      final (id, page) = key;
      return xiangqiTournamentLeadersFromJson(
        await _getJson(ref, 'tournament/$id/leaders', {'page': '$page'}),
      );
    }, name: 'XiangqiTournamentLeadersProvider');

/// A tournament's participants, from `GET /api/tournament/<id>/participants/invited`.
///
/// **A bare array**, not a page — measured that way. The `joined` list is the same shape and is not
/// asked for: a tournament that has not started has nobody in a seat, and the two lists are the same
/// people before it does.
final xiangqiTournamentParticipantsProvider = FutureProvider.autoDispose
    .family<IList<XiangqiTournamentParticipant>, String>((ref, id) async {
      return xiangqiTournamentParticipantsFromJson(
        await _getJson(ref, 'tournament/$id/participants/invited', const {}),
      );
    }, name: 'XiangqiTournamentParticipantsProvider');

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
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    throw FormatException('xiangqi.com answered $path with something that is not JSON.');
  }
}
