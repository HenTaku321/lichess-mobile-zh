import 'dart:async';
import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Client, Request, Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';
import 'package:logging/logging.dart';

final _logger = Logger('XiangqiSocial');

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
  if (!ref.watch(isXiangqiLoggedInProvider)) {
    throw const XiangqiSocialException(XiangqiSocialFailure.noSession);
  }
  final socket = await _socketOf(ref);
  final answer = socket.stream
      .firstWhere((event) => event.name == kXiangqiNotificationsSuccessEvent)
      .timeout(kXiangqiSocialTimeout);
  await socket.emit(kXiangqiNotificationsEvent, data: const {}, timeout: kXiangqiSocialTimeout);
  final frame = await answer;
  return xiangqiNotificationsFromJson(_unwrap(frame.data));
}, name: 'XiangqiNotificationsProvider');

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
Future<bool> markAllXiangqiNotificationsRead(WidgetRef ref) async {
  if (!ref.read(isXiangqiLoggedInProvider)) {
    throw const XiangqiSocialException(XiangqiSocialFailure.noSession);
  }
  final socket = await _connect(
    online: ref.read(isDeviceOnlineProvider),
    socket: ref.read(xiangqiSocketProvider),
  );
  final answer = socket.stream
      .firstWhere((event) => event.name == kXiangqiMarkAllReadSuccessEvent)
      .timeout(kXiangqiSocialTimeout);
  await socket.emit(kXiangqiMarkAllReadEvent, data: const {}, timeout: kXiangqiSocialTimeout);
  await answer;
  return true;
}

/// The connected socket, or a [XiangqiSocialException] saying why there is none.
///
/// **No session check here**, and that is not an oversight: the socket opens a guest session of its
/// own when there is none — see `xiangqiSocketProvider` — so "is there a token" is its question and
/// not this one's. What the two callers that need a *real* account do is ask
/// [isXiangqiLoggedInProvider] first and throw [XiangqiSocialFailure.noSession] themselves, which is
/// the only place that reason is true.
///
/// The two things it does need are passed in rather than read from a container, because there are
/// two kinds of container here: a provider's own `Ref` and a widget's `WidgetRef` are different
/// types with the same `read`, and the one function that opens the socket is worth more than the two
/// it would take to open it from both.
Future<XiangqiSocketClient> _connect({
  required bool online,
  required XiangqiSocketClient socket,
}) async {
  if (!online) throw const XiangqiSocialException(XiangqiSocialFailure.offline);
  try {
    await socket.connect();
  } catch (error, stackTrace) {
    _logger.warning('The xiangqi.com socket would not open.', error, stackTrace);
    throw const XiangqiSocialException(XiangqiSocialFailure.failed);
  }
  return socket;
}

/// The connected socket a provider asks with.
///
/// **`watch`, not `read`, for the session and the network.** Both are things that arrive after the
/// first build — the session is restored from storage a microtask later — and a provider that read
/// them once would settle into "no session" and stay there for the life of the screen. The socket
/// itself is read, because it is a client rather than a state: the same one is handed back whenever
/// it is asked for, and watching it would subscribe to nothing.
Future<XiangqiSocketClient> _socketOf(Ref ref) =>
    _connect(online: ref.watch(isDeviceOnlineProvider), socket: ref.read(xiangqiSocketProvider));

/// Reads [path] over the xiangqi.com client, with no session required.
///
/// **The one endpoint that goes through here is public** — `friends/<username>` answered `200` to a
/// request with no `Authorization` header at all, measured on 2026-10-16 — so there is no session
/// gate. The two that do want an account ([xiangqiFriendRequestsProvider] and
/// [xiangqiNotificationsProvider]) check for one themselves, and say which of the two things is
/// missing when it is.
///
/// `watch` and not `read` for the network, for the reason [_socketOf] gives.
Future<Object?> _getJson(Ref ref, String path, Map<String, String> query) async {
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

/// The payload a socket event carries, unwrapped from the two envelopes it arrives in.
Object? _unwrap(Object? data) {
  final first = data is List && data.isNotEmpty ? data.first : data;
  final map = first is Map<String, dynamic> ? first : null;
  return map?['data'] ?? first;
}
