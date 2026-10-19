import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';

/// One public room of `GET /api/chat_rooms/`.
///
/// **The name is the address.** The socket's `room` field takes the room's `name` and not its
/// `code` — measured on 2026-10-19, the Chinese room is `"中文"` on the wire and its `code` is
/// `"CN"`, and the two are not interchangeable. See `xiangqi-com-re/docs/chat.md`.
@immutable
final class const XiangqiChatRoom({
  /// What the room is called, and what the socket is told it is.
  required final String name,

  /// What the room is for, as the server describes it.
  final String? description,

  /// The two-letter country the room is filed under, which is not its address.
  final String? code,
});

/// Where a chat's messages are being read from.
///
/// Two kinds, and the wire spells them the same way it spells everything else: `"lobby"` for a
/// public room and `"game"` for a game's own chat, whose `room` is the game's id.
enum XiangqiChatKind(final String wire) {
  lobby('lobby'),
  game('game'),
}

/// One message of a public room or a game's chat.
///
/// Read from the `items` of `chat.lobby.messages.success`, one page of which is a hundred messages,
/// newest first. The three things that make this shape different from a private message are all
/// here: it has a server-side [id], it has a [senderName], and its [timestamp] is written the way
/// HTTP writes a date rather than the way a private message writes one.
@immutable
final class const XiangqiChatMessage({
  /// The server's own id for the message, which is what makes two readings of the same page the
  /// same message rather than two.
  ///
  /// Null when the payload did not carry one. Every message of a history page has an id, and the
  /// new-message broadcast's shape is not pinned — see `xiangqi-com-re/docs/chat.md`, which says so
  /// outright — so a broadcast that arrives without one is still a message and is still shown.
  final int? id,

  required final String message,

  /// Who wrote it, by account id.
  final int? senderId,

  /// What they are called, or a placeholder when they have hidden their name.
  final String? senderName,

  /// The account kind, on the same scale as a game's players: 10 human, 20 guest, 30 bot, 40 guest
  /// bot.
  final int? senderType,

  /// When it was written, or null when the timestamp could not be read.
  final DateTime? timestamp,
});

/// The rooms of a `GET /api/chat_rooms/` body.
///
/// The body is a bare array — no envelope, no paging — measured on 2026-10-19.
IList<XiangqiChatRoom> xiangqiChatRoomsFromJson(Object? json) {
  if (json is! List) return const IListConst([]);
  final rooms = <XiangqiChatRoom>[];
  for (final row in json) {
    if (row is! Map<String, dynamic>) continue;
    final name = row['name'];
    if (name is! String || name.isEmpty) continue;
    rooms.add(
      XiangqiChatRoom(
        name: name,
        description: row['description'] is String ? row['description'] as String : null,
        code: row['code'] is String ? row['code'] as String : null,
      ),
    );
  }
  return rooms.lock;
}

/// The messages of a `chat.lobby.messages.success` body.
///
/// The envelope is `{data: {has_next_page: bool, items: [...]}}`, and a page is a hundred messages
/// with the newest first — so the list is reversed here, once, at the edge where the wire's order
/// enters the model. Everything above this reads a chat the way it is read on screen: oldest first,
/// newest at the bottom.
IList<XiangqiChatMessage> xiangqiChatMessagesFromJson(Object? json) {
  final data = json is Map<String, dynamic> ? json['data'] : null;
  final items = data is Map<String, dynamic> ? data['items'] : null;
  if (items is! List) return const IListConst([]);
  final messages = <XiangqiChatMessage>[];
  for (final row in items) {
    final message = xiangqiChatMessageFromJson(row);
    if (message != null) messages.add(message);
  }
  return IList(messages.reversed);
}

/// One message of a chat, or null when the row is not one.
XiangqiChatMessage? xiangqiChatMessageFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final text = json['message'];
  if (text is! String || text.isEmpty) return null;
  final id = json['id'];
  return XiangqiChatMessage(
    id: id is num ? id.toInt() : null,
    message: text,
    senderId: json['sender_id'] is num ? (json['sender_id'] as num).toInt() : null,
    senderName: json['sender_name'] is String ? json['sender_name'] as String : null,
    senderType: json['sender_type'] is num ? (json['sender_type'] as num).toInt() : null,
    timestamp: _timestampOf(json['timestamp']),
  );
}

/// The date an RFC 1123 timestamp names, or null when it names nothing this app can read.
///
/// A public room's message carries `Mon, 19 Oct 2026 08:37:29 GMT` — HTTP's own date format, and
/// not the ISO one a private message carries. Written out here rather than reached for: the parser
/// for it lives in `dart:io`, which a web build and a widget test do not have.
DateTime? _timestampOf(Object? value) {
  if (value is! String) return null;
  // `Mon, 19 Oct 2026 08:37:29 GMT`: six fields, of which the weekday is decoration.
  final parts = value.split(' ');
  if (parts.length < 6) return null;
  final day = int.tryParse(parts[1]);
  final month = _months.indexOf(parts[2]) + 1;
  final time = parts[4].split(':');
  if (day == null || month == 0 || time.length != 3) return null;
  final hour = int.tryParse(time[0]);
  final minute = int.tryParse(time[1]);
  final second = int.tryParse(time[2]);
  final year = int.tryParse(parts[3]);
  if (hour == null || minute == null || second == null || year == null) return null;
  return DateTime.utc(year, month, day, hour, minute, second);
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
