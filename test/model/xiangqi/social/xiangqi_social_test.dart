// Tests for reading notifications, friends and friend requests.
//
// The notification shapes are the ones the 2026-10-16 probe measured off the socket — see
// `xiangqi-com-re/docs/social.md` — with every value replaced. The friend shapes are **not**
// measured: every read of those endpoints answered with an empty list, so what is pinned here is
// that the reader accepts the two spellings the site uses for a user in a list and drops what it
// cannot place, rather than that it reads a shape somebody saw.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social.dart';

/// One notification, with the fields the socket was measured to carry.
Map<String, Object?> notification({
  int id = 1,
  int type = 2,
  String title = 'A title',
  String message = 'A body',
  Object? url = '/leaders',
  bool isRead = false,
  String? sender = 'somebody',
}) => {
  'id': id,
  'type': type,
  'title': title,
  'msg': message,
  'url': url,
  'is_read': isRead,
  'created_on': '2026-10-15T14:05:20.215677',
  'sender_id': sender == null ? null : 42,
  'username': sender,
  'profile_image': null,
  'profile_link_token': null,
  'hidden_username': false,
  'hidden_profile_icon': false,
};

/// The payload `get.notifications.success` really carries.
Map<String, Object?> payload({
  required List<Map<String, Object?>> items,
  int totalPages = 1,
  int? nextPage,
}) => {
  'data': {
    'notifications': {
      'items': items,
      'total_pages': totalPages,
      'has_next_page': nextPage != null,
      'next_page_num': nextPage,
      'prev_page_num': null,
    },
  },
};

/// A user as the site writes one in a list.
Map<String, Object?> user(String name) => {
  'id': 1,
  'username': name,
  'identity': name,
  'rating': 1500,
  'country': {'name': 'Viet Nam', 'code': 'VN'},
  'hidden_username': false,
  'hidden_profile_icon': false,
  'profile_image': null,
  'profile_link_token': null,
};

void main() {
  group('notifications', () {
    test('are read out of the two envelopes they arrive in', () {
      // The frame's payload is `{data: {notifications: {...}}}`: two levels, and both are real.
      final notifications = xiangqiNotificationsFromJson(payload(items: [notification()]));

      expect(notifications.items.length, 1);
      final item = notifications.items.single;
      expect(item.id, 1);
      expect(item.type, 2);
      expect(item.title, 'A title');
      expect(item.message, 'A body');
      expect(item.url, '/leaders');
      expect(item.isRead, isFalse);
      expect(item.createdAt, DateTime(2026, 10, 15, 14, 5, 20, 215, 677));
      expect(item.senderName, 'somebody');
    });

    test('carry no sender on a system message', () {
      // Measured that way on every row this account has: `sender_id` and `username` are both null.
      final notifications = xiangqiNotificationsFromJson(
        payload(items: [notification(sender: null)]),
      );
      expect(notifications.items.single.senderName, isNull);
    });

    test('count how many are unread', () {
      final notifications = xiangqiNotificationsFromJson(
        payload(
          items: [notification(id: 1), notification(id: 2, isRead: true), notification(id: 3)],
        ),
      );
      expect(notifications.unreadCount, 2);
    });

    test('say whether there is a page after them', () {
      expect(xiangqiNotificationsFromJson(payload(items: [])).hasNextPage, isFalse);
      expect(
        xiangqiNotificationsFromJson(payload(items: [], totalPages: 3, nextPage: 2)).hasNextPage,
        isTrue,
      );
      expect(
        xiangqiNotificationsFromJson(payload(items: [], totalPages: 3, nextPage: 2)).nextPage,
        2,
      );
    });

    test('are empty for a payload that is not one', () {
      expect(xiangqiNotificationsFromJson(null).items, isEmpty);
      expect(xiangqiNotificationsFromJson('nope').items, isEmpty);
      expect(xiangqiNotificationsFromJson(const <String, Object?>{}).items, isEmpty);
    });

    test('drop a row with no id', () {
      final notifications = xiangqiNotificationsFromJson(
        payload(
          items: [
            notification(id: 1),
            {...notification(id: 2)}..remove('id'),
          ],
        ),
      );
      expect(notifications.items.length, 1);
    });
  });

  group('friends', () {
    test('are read from the items envelope, and from a seat written either way', () {
      // The site writes a user in a list both as a bare object and wrapped under `user`, and which
      // one this endpoint uses has not been measured — so both are accepted.
      final friends = xiangqiFriendsFromJson({
        'items': [
          user('bare'),
          {'user': user('wrapped')},
        ],
        'total_pages': 2,
        'next_page_num': 2,
      });

      expect(friends.friends.map((f) => f.player.name), ['bare', 'wrapped']);
      expect(friends.totalPages, 2);
      expect(friends.hasNextPage, isTrue);
    });

    test('are empty for an account with no friends, and for a body that is not one', () {
      final empty = xiangqiFriendsFromJson(const {
        'items': <Object?>[],
        'total_pages': 0,
        'next_page_num': null,
      });
      expect(empty.friends, isEmpty);
      expect(empty.hasNextPage, isFalse);
      expect(xiangqiFriendsFromJson(null).friends, isEmpty);
    });

    test('drop a row that is not a user', () {
      final friends = xiangqiFriendsFromJson({
        'items': [user('a'), 'nope', const <String, Object?>{}, user('b')],
      });
      expect(friends.friends.map((f) => f.player.name), ['a', 'b']);
    });
  });

  group('friend requests', () {
    test('are read from their own envelope, which is not the friends one', () {
      // Measured on 2026-10-16: the two endpoints answer with two different keys, `friend_requests`
      // and `items`, and neither is an empty list of the other's shape.
      final requests = xiangqiFriendRequestsFromJson({
        'friend_requests': [user('a'), user('b')],
      });
      expect(requests.map((r) => r.player.name), ['a', 'b']);
    });

    test('are empty for the friends envelope, which is what a wrong reader would have read', () {
      expect(xiangqiFriendRequestsFromJson(const {'items': <Object?>[]}), isEmpty);
      expect(xiangqiFriendRequestsFromJson(null), isEmpty);
    });
  });
}
