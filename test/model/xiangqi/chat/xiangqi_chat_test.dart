// Tests for reading xiangqi.com's chat.
//
// The shapes are the ones the 2026-10-19 probe measured — see `xiangqi-com-re/docs/chat.md` — with
// every value replaced. The three things that make a public room's message different from a private
// one are all pinned here, because they are what a reader of the two would get wrong: the server's
// id, the sender's name, and a timestamp written the way HTTP writes one.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';

/// One public room of `chat_rooms/`.
Map<String, Object?> room({
  String name = 'A room',
  String? description = 'This is a channel.',
  String? code = 'XX',
}) => {'name': name, 'description': description, 'code': code};

/// One message of a room.
Map<String, Object?> message({
  Object? id = 1,
  String text = 'hello',
  Object? senderId = 42,
  Object? senderName = 'a-player',
  Object? senderType = 10,
  Object? timestamp = 'Mon, 19 Oct 2026 08:37:29 GMT',
}) => {
  'id': id,
  'message': text,
  'message_type': 1,
  'sender_active': true,
  'sender_country': {'code': 'CN', 'name': 'China'},
  'sender_hidden_profile_icon': false,
  'sender_hidden_username': false,
  'sender_id': senderId,
  'sender_name': senderName,
  'sender_profile_image': null,
  'sender_profile_link_token': null,
  'sender_type': senderType,
  'timestamp': timestamp,
};

/// The envelope a history page arrives in.
///
/// The items are typed loosely on purpose: a page is a list of whatever the server put in it, and
/// one of the cases below is about a row that is not a message at all.
Map<String, Object?> page(List<Object?> items, {bool hasNext = true}) => {
  'data': {'has_next_page': hasNext, 'items': items},
};

void main() {
  group('the rooms', () {
    test('are read with the name the socket is given', () {
      final rooms = xiangqiChatRoomsFromJson([
        room(name: 'English', description: 'This is global channel.', code: 'US'),
        room(name: '中文', description: 'This is Chinese Channel. ', code: 'CN'),
      ]);
      expect(rooms.length, 2);
      expect(rooms.first.name, 'English');
      // **The name is the address.** The socket's `room` field takes this and not the code, which
      // is why the two are kept apart here.
      expect(rooms.last.name, '中文');
      expect(rooms.last.code, 'CN');
    });

    test('drop a row with no name, and are empty for a body that is not a list', () {
      expect(xiangqiChatRoomsFromJson([room(name: ''), room(name: 'kept')]).single.name, 'kept');
      expect(xiangqiChatRoomsFromJson(null), isEmpty);
      expect(xiangqiChatRoomsFromJson(const {'name': 'nope'}), isEmpty);
    });
  });

  group('the messages of a room', () {
    test('are read oldest first, whichever way the page came in', () {
      // A page is a hundred messages with the newest first; a chat is read from its oldest. The
      // reversal happens once, here, at the edge where the wire's order enters the model.
      final messages = xiangqiChatMessagesFromJson(
        page([
          message(id: 3, text: 'third'),
          message(id: 2, text: 'second'),
          message(id: 1, text: 'first'),
        ]),
      );
      expect(messages.map((m) => m.message), ['first', 'second', 'third']);
    });

    test('carry the server id, the sender and the time', () {
      final first = xiangqiChatMessagesFromJson(page([message()])).single;
      expect(first.id, 1);
      expect(first.message, 'hello');
      expect(first.senderId, 42);
      expect(first.senderName, 'a-player');
      expect(first.senderType, 10);
      // `Mon, 19 Oct 2026 08:37:29 GMT`, read as the UTC instant it names.
      expect(first.timestamp, DateTime.utc(2026, 10, 19, 8, 37, 29));
    });

    test('are dropped when they have no text, and kept when they have no id', () {
      // The new-message broadcast's shape is not pinned, so a message without an id is still a
      // message; one without any text is not.
      final messages = xiangqiChatMessagesFromJson(
        page([message(id: null, text: 'no id'), message(text: ''), 'nope']),
      );
      expect(messages.single.message, 'no id');
      expect(messages.single.id, isNull);
    });

    test('have no time when the timestamp is not one this app can read', () {
      expect(
        xiangqiChatMessagesFromJson(page([message(timestamp: 'not a date')])).single.timestamp,
        isNull,
      );
      expect(
        xiangqiChatMessagesFromJson(page([message(timestamp: null)])).single.timestamp,
        isNull,
      );
    });

    test('are empty for a body that is not a page', () {
      expect(xiangqiChatMessagesFromJson(null), isEmpty);
      expect(xiangqiChatMessagesFromJson(const {'data': 'nope'}), isEmpty);
      expect(
        xiangqiChatMessagesFromJson(const {
          'data': <String, Object?>{'items': 7},
        }),
        isEmpty,
      );
    });
  });
}
