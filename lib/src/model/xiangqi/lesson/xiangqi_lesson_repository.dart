import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Client, Request, Response;
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// Every course topic on xiangqi.com, from `GET /api/lessons/levels`.
///
/// One page for the whole list: the endpoint takes no page parameter and none was found. The
/// progress on each topic is this account's — `complete_lessons` — so the list is worth asking for
/// again when the account has done something, which is what the screens behind it do.
final xiangqiTopicsProvider = FutureProvider.autoDispose.family<IList<XiangqiTopic>, String>((
  ref,
  locale,
) async {
  return xiangqiTopicsFromJson(await _getJson(ref, 'lessons/levels', {'locale': locale}));
}, name: 'XiangqiTopicsProvider');

/// One topic and its lessons, from `GET /api/lessons/topic/<id>`.
final xiangqiTopicProvider = FutureProvider.autoDispose
    .family<XiangqiTopicDetail, (String id, String locale)>((ref, key) async {
      final (id, locale) = key;
      final json = await _getJson(ref, 'lessons/topic/$id', {'locale': locale});
      final detail = xiangqiTopicDetailFromJson(json);
      if (detail == null) {
        throw ServerException(
          200,
          'xiangqi.com answered the topic with something else.',
          xiangqiUri('lessons/topic/$id'),
          null,
        );
      }
      return detail;
    }, name: 'XiangqiTopicProvider');

/// One lesson's chapters, from `GET /api/lessons/lesson/<id>/chapters`.
///
/// **This is the only way a chapter is read.** `GET /api/lessons/chapter/<id>` and
/// `POST /api/lessons/chapter` are the *editor's* endpoints and answer an ordinary account
/// `401 Admin access required` — measured on 2026-10-16. See `xiangqi-com-re/docs/lesson.md`.
final xiangqiChaptersProvider = FutureProvider.autoDispose
    .family<IList<XiangqiChapter>, (String lessonId, String locale)>((ref, key) async {
      final (lessonId, locale) = key;
      return xiangqiChaptersFromJson(
        await _getJson(ref, 'lessons/lesson/$lessonId/chapters', {'locale': locale}),
      );
    }, name: 'XiangqiChaptersProvider');

/// The calls that change something in the lesson domain.
class const XiangqiLessonRepository(final Client _client) {
  /// Marks the chapter [id] as done.
  ///
  /// The body is `{solved: true}` — measured on 2026-10-16, where the answer was
  /// `{"message":"Lesson chapter completed successfully","topic_completed":false}` and the chapter
  /// came back `completed: true` on the next read.
  ///
  /// **It is called by playing the chapter, and by nothing else.** A chapter is marked done when
  /// its whole script has been played — see [XiangqiChapterController], which is the only caller —
  /// so a button that marked a chapter done without playing it would be a button that lies about
  /// what the reader did.
  Future<void> completeChapter(String id) =>
      _post('lessons/chapter/$id/complete', {'solved': true});

  Future<void> _post(String path, Map<String, Object?> body) async {
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

    if (response.statusCode >= 400) {
      throw ServerException(response.statusCode, 'xiangqi.com $path failed.', uri, null);
    }
  }
}

/// A provider for [XiangqiLessonRepository].
final xiangqiLessonRepositoryProvider = Provider<XiangqiLessonRepository>((Ref ref) {
  return XiangqiLessonRepository(ref.read(xiangqiClientProvider));
}, name: 'XiangqiLessonRepositoryProvider');

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
