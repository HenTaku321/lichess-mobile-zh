import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';

part 'xiangqi_social.freezed.dart';

/// One notification, from the socket's `get.notifications.success`.
///
/// The list is **not REST**: the shipped client asks over the socket and the answer comes back as
/// `{data: {notifications: {...}}}`, a page of them at a time. See
/// `xiangqi-com-re/docs/social.md`.
@freezed
sealed class const XiangqiNotification._() with _$XiangqiNotification {
  const factory({
    required int id,

    /// xiangqi.com's own kind code. `2` is a system message, which is the only one measured; the
    /// rest of the enum is not pinned, so nothing here branches on it.
    required int type,

    /// The headline.
    required String title,

    /// The body, already in the reader's language: the server sends it translated.
    required String message,

    /// Where the notification points, or null when it points nowhere.
    ///
    /// An absolute URL for a link off the site and a path for one on it — measured both ways on
    /// 2026-10-16, where one notification carried `https://play.xiangqi.com/lessons/topic/...` and
    /// another `/leaders`.
    String? url,

    required bool isRead,

    /// When it was sent, or null when the server did not say.
    DateTime? createdAt,

    /// Who sent it, or null for a system message.
    ///
    /// A system notification carries `sender_id: null` **and** `username: null` — measured that way
    /// on every row this account has — so a null sender is the ordinary case and not a thin payload.
    String? senderName,
  }) = _XiangqiNotification;
}

/// A page of notifications.
@freezed
sealed class const XiangqiNotifications._() with _$XiangqiNotifications {
  const factory({
    required IList<XiangqiNotification> items,
    required int totalPages,

    /// The next page to ask for, or null when this is the last one.
    int? nextPage,
  }) = _XiangqiNotifications;

  /// Whether there is a page after this one.
  bool get hasNextPage => nextPage != null;

  /// How many of [items] have not been read.
  int get unreadCount => items.where((item) => !item.isRead).length;
}

/// One friend, from `GET /api/friends/<username>`.
///
/// **The item shape is inferred, not measured.** Every read of this endpoint this project could make
/// answered with an empty list — the one account has no friends — so what an item looks like is read
/// off the site's one user shape, which is the same object everywhere else it appears. The reader
/// accepts either a bare seat or a seat wrapped under `user`, because those are the two spellings
/// the site uses for "a user in a list", and it is written to drop anything it cannot place rather
/// than to guess. See `xiangqi-com-re/docs/social.md`.
@freezed
sealed class const XiangqiFriend._() with _$XiangqiFriend {
  const factory({required XiangqiLivePlayer player}) = _XiangqiFriend;
}

/// A page of friends.
@freezed
sealed class const XiangqiFriends._() with _$XiangqiFriends {
  const factory({required IList<XiangqiFriend> friends, required int totalPages, int? nextPage}) =
      _XiangqiFriends;

  /// Whether there is a page after this one.
  bool get hasNextPage => nextPage != null;
}

/// One pending friend request, from `GET /api/friends/friend-requests`.
///
/// The same caveat as [XiangqiFriend]: the endpoint answered with an empty list, so the item shape
/// is the site's user shape rather than a measured one. The envelope is measured — it is
/// `{friend_requests: [...]}` and **not** the `{items: [...]}` the friend list uses.
@freezed
sealed class const XiangqiFriendRequest._() with _$XiangqiFriendRequest {
  const factory({required XiangqiLivePlayer player}) = _XiangqiFriendRequest;
}

/// A page of notifications, read from a `get.notifications.success` payload.
///
/// The payload is `{data: {notifications: {...}}}`, and this reads the inner envelope. A payload
/// that is not one is an empty page rather than a failure: a list this app cannot read is a list
/// with nothing in it, and the screen behind it says so in a sentence.
XiangqiNotifications xiangqiNotificationsFromJson(Object? json) {
  final outer = _map(json);
  final data = _map(outer?['data']) ?? outer;
  final envelope = _map(data?['notifications']) ?? data;
  final items = <XiangqiNotification>[];
  final rows = envelope?['items'];
  if (rows is List) {
    for (final row in rows) {
      final map = _map(row);
      if (map == null) continue;
      final id = _int(map['id']);
      if (id == null) continue;
      items.add(
        XiangqiNotification(
          id: id,
          type: _int(map['type']) ?? 0,
          title: _string(map['title']) ?? '',
          message: _string(map['msg']) ?? '',
          url: _string(map['url']),
          isRead: map['is_read'] == true,
          createdAt: _dateTime(map['created_on']),
          senderName: _string(map['username']),
        ),
      );
    }
  }
  return XiangqiNotifications(
    items: items.lock,
    totalPages: _int(envelope?['total_pages']) ?? 0,
    nextPage: _int(envelope?['next_page_num']),
  );
}

/// A page of friends, read from a `friends/<username>` body.
XiangqiFriends xiangqiFriendsFromJson(Object? json) {
  final map = _map(json);
  return XiangqiFriends(
    friends: _playersOf(map?['items']),
    totalPages: _int(map?['total_pages']) ?? 0,
    nextPage: _int(map?['next_page_num']),
  );
}

/// The pending requests in a `friends/friend-requests` body.
IList<XiangqiFriendRequest> xiangqiFriendRequestsFromJson(Object? json) =>
    _playersOf(_map(json)?['friend_requests'])
        .map((friend) => XiangqiFriendRequest(player: friend.player))
        .toIList();

/// The friends [rows] describes, dropping anything that cannot be placed.
IList<XiangqiFriend> _playersOf(Object? rows) {
  if (rows is! List) return const IListConst<XiangqiFriend>([]);
  final friends = <XiangqiFriend>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    // A seat, or a seat under `user`: the site writes a user in a list both ways, and which one
    // this endpoint uses has not been measured.
    final player = xiangqiLivePlayerFromJson(map) ?? xiangqiLivePlayerFromJson(map['user']);
    if (player == null) continue;
    friends.add(XiangqiFriend(player: player));
  }
  return friends.lock;
}

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;

DateTime? _dateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}
