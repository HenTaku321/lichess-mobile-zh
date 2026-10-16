import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Client, Request, Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/saved/xiangqi_saved.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// The folders of one kind of content, from `GET /api/items/folders/<user>/<slug>/`.
///
/// [parentId] lists the folders **inside** one folder rather than at the root, which the endpoint
/// takes as its own `parent_id` parameter.
final xiangqiSavedFoldersProvider = FutureProvider.autoDispose
    .family<XiangqiSavedFolders, (String username, XiangqiSavedKind kind, String? parentId)>((
      ref,
      key,
    ) async {
      final (username, kind, parentId) = key;
      return xiangqiSavedFoldersFromJson(
        await _getJson(ref, 'items/folders/$username/${kind.wireSlug}/', {
          'page': '1',
          'parent_id': ?parentId,
        }),
      );
    }, name: 'XiangqiSavedFoldersProvider');

/// The puzzles this account has created, from `GET /api/puzzle/puzzles/<user>`.
///
/// The same endpoint the puzzle domain reads for "puzzles by this account" — see
/// `xiangqi-com-re/docs/puzzle.md` — and the same envelope.
final xiangqiSavedPuzzlesProvider = FutureProvider.autoDispose.family<XiangqiSavedPuzzles, String>((
  ref,
  username,
) async {
  return xiangqiSavedPuzzlesFromJson(
    await _getJson(ref, 'puzzle/puzzles/$username', {'page': '1'}),
  );
}, name: 'XiangqiSavedPuzzlesProvider');

/// The notes this account has saved, from `GET /api/game-note/game-notes/<user>`.
final xiangqiSavedNotesProvider = FutureProvider.autoDispose.family<XiangqiSavedNotes, String>((
  ref,
  username,
) async {
  return xiangqiSavedNotesFromJson(
    await _getJson(ref, 'game-note/game-notes/$username', {'page': '1'}),
  );
}, name: 'XiangqiSavedNotesProvider');

/// The calls that change the folder tree.
///
/// Every one of them acts on **this account's own content** and on nothing else: the tree is the
/// account's own, and a folder id is meaningless to anybody else.
class const XiangqiSavedRepository(final Client _client) {
  /// Makes a folder called [name] at the root of [kind]'s tree, or inside [parentId].
  ///
  /// The body's `item_type` is the **number** and the URL's is the **slug** — measured on
  /// 2026-10-16, where `POST items/folders/puzzle/` with `{"item_type": 2, ...}` answered `201` with
  /// the folder. See `xiangqi-com-re/docs/saved.md`.
  Future<void> createFolder({
    required XiangqiSavedKind kind,
    required String name,
    String? parentId,
  }) => _send('POST', 'items/folders/${kind.wireSlug}/', {
    'item_type': kind.itemType,
    'name': name,
    'parent_encrypted_id': parentId,
  });

  /// Renames the folder [id].
  Future<void> renameFolder({required String id, required String name}) =>
      _send('PUT', 'items/folders/$id', {'name': name});

  /// Deletes the folder [id].
  ///
  /// What happens to what was inside it is **not pinned**: the folder this project made was empty
  /// when it was deleted, and the site's own client offers no confirmation about the contents. See
  /// `xiangqi-com-re/docs/saved.md`.
  Future<void> deleteFolder(String id) => _send('DELETE', 'items/folders/$id', null);

  Future<void> _send(String method, String path, Map<String, Object?>? body) async {
    final uri = xiangqiUri(path);
    final request = Request(method, uri)..headers.addAll(const {'Accept': 'application/json'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client.send(request).then(Response.fromStream);

    if (response.statusCode >= 400) {
      throw ServerException(response.statusCode, 'xiangqi.com $path failed.', uri, null);
    }
  }
}

/// A provider for [XiangqiSavedRepository].
final xiangqiSavedRepositoryProvider = Provider<XiangqiSavedRepository>((Ref ref) {
  return XiangqiSavedRepository(ref.read(xiangqiClientProvider));
}, name: 'XiangqiSavedRepositoryProvider');

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
