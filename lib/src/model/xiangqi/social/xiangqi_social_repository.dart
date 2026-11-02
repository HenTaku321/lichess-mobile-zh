import 'dart:async';
import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Client, Request, Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_pagination.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket_request_queue.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// The event a client sends to be given its notifications.
const String kXiangqiNotificationsEvent = 'get.notifications';

/// The event the notifications come back on.
const String kXiangqiNotificationsSuccessEvent = 'get.notifications.success';

/// The event a client sends to mark every notification read.
const String kXiangqiMarkAllReadEvent = 'mark.all.notifications.read';

/// The event the server answers that with.
///
/// **Not the name the shipped bundle uses.** Its action constants spell this
/// `mark.all.notifications.read.success`; the server was measured answering `mark.all.notif.read.success`
/// on 2026-10-16 — one word shorter. The server's own spelling is the one this client waits for. See
/// `xiangqi-com-re/docs/social.md`.
const String kXiangqiMarkAllReadSuccessEvent = 'mark.all.notif.read.success';

/// How long the socket is given to answer a notification request.
const Duration kXiangqiSocialTimeout = Duration(seconds: 20);

/// What went wrong with a social request, in the app's own terms.
enum XiangqiSocialFailure() {
  /// There is no xiangqi.com session to ask with.
  noSession,

  /// The device is offline.
  offline,

  /// The request or the answer failed.
  failed,
}

/// Thrown when a social request cannot be made or answered.
class const XiangqiSocialException(final XiangqiSocialFailure reason) implements Exception {
  @override
  String toString() => 'XiangqiSocialException: ${reason.name}';
}

/// The account's notifications, from the socket.
///
/// **Not REST.** The list is a socket conversation: `get.notifications` goes out and
/// `get.notifications.success` comes back carrying a page of them. The one part of notifications
/// that *is* REST is the preferences, and those are a different screen's business — see
/// `xiangqi-com-re/docs/social.md`.
///
/// The subscription is opened **before** the emit, and that is not tidiness: the answer can beat the
/// ack, and a listener attached afterwards would miss it and then wait out the whole timeout for a
/// frame that had already gone by. The same rule the review's two requests follow.
///
/// **A real account only.** Notifications are the one thing on the socket a guest is not given:
/// measured on 2026-10-16, a guest's `get.notifications` was answered by the server **disconnecting
/// the namespace** (`41/xiangqi,`) rather than by a message. See `xiangqi-com-re/docs/social.md`.
final xiangqiNotificationsProvider = FutureProvider.autoDispose<XiangqiNotifications>((ref) async {
  final page = await ref.watch(xiangqiNotificationsControllerProvider.future);
  return XiangqiNotifications(
    items: page.items,
    totalPages: page.totalPages ?? 0,
    nextPage: page.nextPage,
  );
}, name: 'XiangqiNotificationsProvider');

class XiangqiNotificationsRepository({
  required final XiangqiSocketClient _socket,
  required final XiangqiSessionStore _sessions,
  required final bool Function() _online,
}) {
  late final _requests = XiangqiSocketRequestQueue(socket: _socket, timeout: kXiangqiSocialTimeout);
  bool _disposed = false;

  Stream<void> get connectionResets => _requests.resets;

  Future<void> _prepare() async {
    if (_disposed) throw const XiangqiSocialException(.failed);
    if (!_online()) throw const XiangqiSocialException(.offline);
    final session = await _sessions.read();
    if (_disposed || session == null || session.isGuest) {
      throw const XiangqiSocialException(.noSession);
    }
  }

  Future<XiangqiPage<XiangqiNotification>> loadPage(int page) {
    if (page < 1) return Future.error(RangeError.range(page, 1, null, 'page'));
    int? generation;
    return _requests.read(
      event: kXiangqiNotificationsEvent,
      data: {'page': page},
      response: kXiangqiNotificationsSuccessEvent,
      ack: true,
      key: ('notifications', _sessions.accountGeneration, page),
      prepare: () async {
        await _prepare();
        generation = _sessions.accountGeneration;
      },
      isCurrent: () =>
          !_disposed && (generation == null || generation == _sessions.accountGeneration),
      decode: (data) => xiangqiNotificationsPageFromJson(data, requestedPage: page),
    );
  }

  Future<bool> markAllRead() {
    int? generation;
    return _requests.read(
      event: kXiangqiMarkAllReadEvent,
      data: const {},
      response: kXiangqiMarkAllReadSuccessEvent,
      ack: true,
      key: ('mark-all-read', _sessions.accountGeneration),
      prepare: () async {
        await _prepare();
        generation = _sessions.accountGeneration;
      },
      isCurrent: () =>
          !_disposed && (generation == null || generation == _sessions.accountGeneration),
      decode: (_) => true,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requests.dispose();
  }
}

final xiangqiNotificationsRepositoryProvider = Provider<XiangqiNotificationsRepository>((ref) {
  ref.watch(xiangqiAccountGenerationProvider);
  final repository = XiangqiNotificationsRepository(
    socket: ref.read(xiangqiSocketProvider),
    sessions: ref.read(xiangqiSessionStoreProvider),
    online: () => ref.read(isDeviceOnlineProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
}, name: 'XiangqiNotificationsRepositoryProvider');

final xiangqiNotificationsControllerProvider =
    AsyncNotifierProvider.autoDispose<
      XiangqiNotificationsController,
      XiangqiPagedState<XiangqiNotification>
    >(XiangqiNotificationsController.new, name: 'XiangqiNotificationsControllerProvider');

class XiangqiNotificationsController() extends XiangqiPagedController<XiangqiNotification> {
  late XiangqiNotificationsRepository _repository;

  @override
  Future<XiangqiPagedState<XiangqiNotification>> build() async {
    // The restored account boundary must settle before its repository is selected. Otherwise a
    // cold-start generation-zero repository can start a handshake and be replaced immediately.
    await ref.watch(xiangqiSessionReadyProvider.future);
    if (!ref.mounted) throw StateError('Notification load cancelled.');
    _repository = ref.watch(xiangqiNotificationsRepositoryProvider);
    final resets = _repository.connectionResets.listen((_) {
      if (ref.mounted && state.hasValue && !state.requireValue.busy) unawaited(refresh());
    });
    ref.onDispose(() => unawaited(resets.cancel()));
    return await super.build();
  }

  @override
  Future<XiangqiPage<XiangqiNotification>> loadPage(int page) => _repository.loadPage(page);

  @override
  Object itemKey(XiangqiNotification item) => item.id;

  Future<bool> markAllRead() async {
    final generation = ref.read(xiangqiAccountGenerationProvider);
    final marked = await _repository.markAllRead();
    if (!ref.mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return false;
    updateItems((item) => item.copyWith(isRead: true));
    unawaited(refresh());
    return marked;
  }
}

/// The account's friends, from `GET /api/friends/<username>`.
///
/// The list is **by username** — `friends/` on its own is a 404, and so is `friends/<id>` — and it
/// takes an optional `search` to filter by. See `xiangqi-com-re/docs/social.md`.
final xiangqiFriendsProvider = FutureProvider.autoDispose
    .family<XiangqiFriends, (String username, String? search)>((ref, key) async {
      final (username, search) = key;
      return xiangqiFriendsFromJson(
        await _getJson(ref, 'friends/$username', {'page': '1', 'search': ?search}),
      );
    }, name: 'XiangqiFriendsProvider');

/// The friend requests waiting to be answered, from `GET /api/friends/friend-requests`.
///
/// The envelope is `{friend_requests: [...]}` and not the `{items: [...]}` the friend list uses —
/// measured on 2026-10-16, where both answered with an empty list of their own shape.
///
/// **A real account only**, where the friend list above is public: this endpoint answered `401` to
/// both an anonymous request and a guest's. Requests are somebody's own, and the server treats them
/// that way.
final xiangqiFriendRequestsProvider = FutureProvider.autoDispose<IList<XiangqiFriendRequest>>((
  ref,
) async {
  await ref.watch(xiangqiSessionReadyProvider.future);
  if (!ref.watch(isXiangqiLoggedInProvider)) {
    throw const XiangqiSocialException(XiangqiSocialFailure.noSession);
  }
  return xiangqiFriendRequestsFromJson(await _getJson(ref, 'friends/friend-requests', const {}));
}, name: 'XiangqiFriendRequestsProvider');

/// The calls that change something in the social domain.
///
/// A class rather than providers, because they are actions a screen runs rather than values it
/// watches — the same split the puzzle repository makes for its own one write.
class const XiangqiSocialRepository(final Client _client) {
  /// Asks [username] to be a friend.
  ///
  /// The field is `receiver_username`, **not** `username`: measured on 2026-10-16, where a body
  /// carrying `username` was answered `400 Unknown field.` with `receiver_username` named as the
  /// missing one. See `xiangqi-com-re/docs/social.md`.
  Future<void> sendFriendRequest(String username) =>
      _post('friends/send-friend-request', {'receiver_username': username});

  /// Removes [username] from the friends.
  ///
  /// A `DELETE` **with a body**, which is unusual enough to be worth saying: the field is
  /// `friend_username`, measured the same way.
  Future<void> unfriend(String username) =>
      _post('friends/unfriend', {'friend_username': username}, method: 'DELETE');

  /// Answers the request [senderId] sent.
  ///
  /// The two fields are `sender_id` and `reply`, measured from the endpoint's own complaint about a
  /// body that had neither. What `reply` may hold is **not** pinned: the shipped client sends a
  /// boolean-looking value and the server was never seen accepting one, because there was no request
  /// to answer.
  Future<void> replyToFriendRequest({required int senderId, required bool accept}) =>
      _post('friends/reply-friend-request', {'sender_id': senderId, 'reply': accept});

  Future<void> _post(String path, Map<String, Object?> body, {String method = 'POST'}) async {
    final uri = xiangqiUri(path);
    final response = await _client
        .send(
          Request(method, uri)
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

/// A provider for [XiangqiSocialRepository].
final xiangqiSocialRepositoryProvider = Provider<XiangqiSocialRepository>((Ref ref) {
  return XiangqiSocialRepository(ref.read(xiangqiClientProvider));
}, name: 'XiangqiSocialRepositoryProvider');

/// Marks every notification read, over the socket.
///
/// Returns whether the server said it had. The answer is the server's own spelling of the event —
/// see [kXiangqiMarkAllReadSuccessEvent] — and a request that is not answered is a failure rather
/// than a success this app assumes.
Future<bool> markAllXiangqiNotificationsRead(WidgetRef ref) =>
    ref.read(xiangqiNotificationsRepositoryProvider).markAllRead();

/// Reads [path] over the xiangqi.com client, with no session required.
///
/// **The one endpoint that goes through here is public** — `friends/<username>` answered `200` to a
/// request with no `Authorization` header at all, measured on 2026-10-16 — so there is no session
/// gate. The two that do want an account ([xiangqiFriendRequestsProvider] and
/// [xiangqiNotificationsProvider]) check for one themselves, and say which of the two things is
/// missing when it is.
///
/// Watch network and account identity so a public lookup can recover after connectivity changes.
Future<Object?> _getJson(Ref ref, String path, Map<String, String> query) async {
  ref.watch(xiangqiAccountGenerationProvider);
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw const XiangqiSocialException(XiangqiSocialFailure.offline);
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
