// Tests for the xiangqi.com private-message protocol layer.
//
// The payloads below are the measured ones: their shapes are copied from the 2026-08-30 capture of
// a real inbox session (`主动私信.har`, entry 5), so the shapes are the server's — a chat row's
// `user_id` is a JSON number, a message's `created_on` is an ISO-8601 string with no timezone
// designator, and every frame nests what it has to say one level down under `data`. What is
// asserted is the reading of those shapes, not the values inside them: every id, name and instant
// here is a stand-in, and none of them is the capture's.
//
// Two of the rules under test are not visible in any single frame, and both are the reason this
// layer exists at all: that at most one `inbox.chat.user` is ever in flight (a response names no
// conversation, so two would cross), and that two emits are never sent inside the spacing window
// (the server drops what arrives too close, silently). The transport is the fixture's fake channel,
// so the tests play the server's half of the conversation rather than a socket.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';

import '../xiangqi/online/xiangqi_online_game_fixture.dart' as fx;

/// The account the fixture's own frames belong to.
///
/// Every capture of the inbox is of a signed-in account, not a guest: the `sender_id` on its frames
/// is a JSON number and its token's `sub` is the same number. The number here is a stand-in.
const xiangqiAccountId = '100001';

/// The first conversation: its id, and the peer it is with.
const xiangqiFirstChatId = 'qAAAAA';
const xiangqiFirstPeerId = 200001;
const xiangqiFirstPeerName = '象棋高手阿豹';

/// The second conversation.
const xiangqiSecondChatId = 'qBBBBB';

/// One `inbox.chats` row, in the shape the capture wrote.
const xiangqiFirstChatRow = <String, Object?>{
  'chat_id': xiangqiFirstChatId,
  'last_message': 'c',
  'last_seen': '2024-05-06T09:12:33.123456',
  'profile_image': null,
  'unread_messages': 0,
  'user_id': xiangqiFirstPeerId,
  'username': xiangqiFirstPeerName,
};

/// A second row, with a different peer and an older message.
const xiangqiSecondChatRow = <String, Object?>{
  'chat_id': xiangqiSecondChatId,
  'last_message': '哈哈哈',
  'last_seen': '2024-05-04T18:03:11.654321',
  'profile_image': null,
  'unread_messages': 0,
  'user_id': 200002,
  'username': 'riverbend',
};

/// The row an `inbox.new.chat` frame carries, which is the measured shape of an *unread* chat.
///
/// The capture's own chat list has every count at zero, so this is the one row in the file that
/// shows a non-zero `unread_messages` — and it is still measured: it is the `inbox.new.chat` frame
/// the capture received when the peer replied (entry 69), with its `is_friend` field dropped because
/// nothing here reads it.
const xiangqiUnreadChatRow = <String, Object?>{
  'chat_id': 'qCCCCC',
  'last_message': 'Hi',
  'last_seen': '2024-05-07T21:47:05.987654',
  'profile_image': null,
  'unread_messages': 1,
  'user_id': 200003,
  'username': '棋友甲',
};

/// One `inbox.chat.user.messages` item, in the shape the capture wrote.
Map<String, Object?> xiangqiMessageRow(
  String text, {
  int senderId = 100001,
  String createdOn = '2024-05-06T09:12:33.123456',
}) => {'created_on': createdOn, 'message': text, 'read': false, 'sender_id': senderId};

/// A page payload — the envelope every list frame in this protocol shares — carrying [rows].
Map<String, Object?> xiangqiPagePayload(List<Map<String, Object?>> rows) => {
  'data': {
    'has_next_page': false,
    'items': rows,
    'next_page_num': null,
    'prev_page_num': null,
    'total_pages': 1,
  },
};

/// The `inbox.chats` frame carrying [rows].
String xiangqiChatsFrame(List<Map<String, Object?>> rows) =>
    fx.xiangqiEventFrame(kXiangqiInboxChatsEvent, xiangqiPagePayload(rows));

/// The `inbox.chat.user.messages` frame carrying [rows].
String xiangqiMessagesFrame(List<Map<String, Object?>> rows) =>
    fx.xiangqiEventFrame(kXiangqiInboxUserMessagesEvent, xiangqiPagePayload(rows));

/// The `42/xiangqi,<id>[` prefix of an emit that asks for an ack.
///
/// Nothing in this layer uses one — no inbox event is ever acked — but the handshake frame and any
/// ack-carrying emit have to be told apart from the emit form when the test reads the wire.
final _ackIdPrefix = RegExp(r'^42/xiangqi,\d+\[');

/// One emit the client wrote: its event name and its payload.
typedef SentEmit = ({String event, Object? data});

/// A repository under test, with the server's half of its socket in the test's hands.
class XiangqiInboxHarness({
  required final XiangqiInboxRepository repository,
  required final fx.FakeXiangqiChannelFactory factory,
}) {
  fx.FakeXiangqiChannel get channel => factory.channel;

  /// The `42` frames the client wrote, as emits.
  ///
  /// The handshake frame is skipped: it is the socket's, not the inbox's.
  List<SentEmit> get emits {
    final result = <SentEmit>[];
    for (final frame in channel.sent.whereType<String>()) {
      if (!frame.startsWith('42/xiangqi,') || _ackIdPrefix.hasMatch(frame)) continue;
      final decoded = jsonDecode(frame.substring('42/xiangqi,'.length));
      if (decoded is! List) continue;
      result.add((event: decoded.first as String, data: decoded.length > 1 ? decoded[1] : null));
    }
    return result;
  }

  /// The names of the emits the client wrote, in order.
  List<String> get events => [for (final emit in emits) emit.event];

  /// The payload of the first emit named [event], or null if it was never sent.
  Object? payloadOf(String event) {
    for (final emit in emits) {
      if (emit.event == event) return emit.data;
    }
    return null;
  }
}

/// A repository over a fake channel, already able to talk.
///
/// The spacing is zero by default so that a test that is not about the spacing does not spend it;
/// the one test that is passes its own.
Future<XiangqiInboxHarness> makeHarness({
  String userId = xiangqiAccountId,
  Duration spacing = Duration.zero,
  Duration responseTimeout = kXiangqiInboxResponseTimeout,
}) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final token = fx.xiangqiTestToken(userId);
  final socket = XiangqiSocketClient(channelFactory: factory, getToken: () async => token);
  addTearDown(socket.dispose);

  final repository = XiangqiInboxRepository(
    socket: socket,
    storage: fx.FakeXiangqiAuthStorage(fx.xiangqiTestSession(token, userId: userId)),
    spacing: spacing,
    responseTimeout: responseTimeout,
  );
  addTearDown(repository.dispose);

  return XiangqiInboxHarness(repository: repository, factory: factory);
}

/// Pushes the two frames that complete the socket handshake.
///
/// The client writes its connect frame from the first operation's own `connect()`, so this is called
/// after an operation has been started and before it is expected to reach the wire.
Future<void> completeHandshake(XiangqiInboxHarness harness) async {
  await pumpEventQueue();
  harness.channel.fromServer(fx.openFrame);
  harness.channel.fromServer(fx.connectAckFrame);
  await pumpEventQueue();
}

void main() {
  group('xiangqiContactsFromChats', () {
    test('reads every measured field and namespaces the id', () {
      final contacts = xiangqiContactsFromChats(
        xiangqiPagePayload([xiangqiFirstChatRow, xiangqiSecondChatRow]),
      );

      expect(contacts, hasLength(2));
      final first = contacts.first;
      expect(first.user.name, xiangqiFirstPeerName);
      // The id is a JSON number on the wire and a string in this app's id space; the prefix is what
      // keeps an integer xiangqi id from ever colliding with a lichess one.
      expect(first.user.id.value, 'xq:$xiangqiFirstPeerId');
      expect(first.lastMessage.text, 'c');
      expect(first.lastMessage.date, DateTime(2024, 5, 6, 9, 12, 33, 123, 456));
      expect(first.xiangqi?.chatId, xiangqiFirstChatId);
      expect(first.xiangqi?.peerId, xiangqiFirstPeerId);
      expect(first.xiangqi?.unreadMessages, 0);
      expect(first.lastMessage.read, isTrue);
    });

    test('an unread conversation is unread, and the count is what says so', () {
      final contacts = xiangqiContactsFromChats(xiangqiPagePayload([xiangqiUnreadChatRow]));

      final row = contacts.single;
      expect(row.xiangqi?.unreadMessages, 1);
      expect(row.lastMessage.read, isFalse);
      // The peer is the only other party a 1:1 chat can have, so it is what the lichess-shaped
      // `userId` is filled with — not this device's own id, which the row never carries.
      expect(row.lastMessage.userId.value, 'xq:200003');
    });

    test('drops a row it cannot read rather than inventing a field', () {
      final contacts = xiangqiContactsFromChats(
        xiangqiPagePayload([
          xiangqiFirstChatRow,
          // No `last_message` and no `last_seen`: a row that cannot become a Contact without
          // making up a text and a date.
          {'chat_id': 'nope', 'user_id': 1, 'username': 'someone'},
        ]),
      );

      expect(contacts, hasLength(1));
      expect(contacts.single.xiangqi?.chatId, xiangqiFirstChatId);
    });

    test('an empty payload is an empty list, not an error', () {
      expect(
        xiangqiContactsFromChats(const {
          'data': {'items': <Object?>[]},
        }),
        isEmpty,
      );
      expect(xiangqiContactsFromChats(null), isEmpty);
    });
  });

  group('xiangqiMessagesFromPayload', () {
    test("keeps the server's own order, which is newest first", () {
      final messages = xiangqiMessagesFromPayload(
        xiangqiPagePayload([
          xiangqiMessageRow('c'),
          xiangqiMessageRow('b', createdOn: '2024-05-05T11:22:44.222222'),
          xiangqiMessageRow('a', createdOn: '2024-05-05T08:41:19.333333'),
        ]),
      );

      expect(messages.map((m) => m.text), ['c', 'b', 'a']);
      expect(messages.first.userId.value, 'xq:$xiangqiAccountId');
      expect(messages.first.date, DateTime(2024, 5, 6, 9, 12, 33, 123, 456));
    });

    test('reads a single message object, which is what msg.success carries once unwrapped', () {
      // The frame's own envelope is `{"data": {...}}`; the repository unwraps it before calling
      // this, so what arrives here is the bare object.
      final message = xiangqiMessageFromPayload(xiangqiMessageRow('hi'));

      expect(message?.text, 'hi');
      expect(message?.userId.value, 'xq:$xiangqiAccountId');
    });

    test('a message missing its text or its date is dropped, not repaired', () {
      expect(xiangqiMessageFromPayload(const {'message': 'x', 'sender_id': 1}), isNull);
      expect(
        xiangqiMessageFromPayload(const {
          'sender_id': 1,
          'created_on': '2024-05-06T09:12:33.123456',
        }),
        isNull,
      );
      expect(
        xiangqiMessageFromPayload(const {
          'message': 'x',
          'created_on': 'not a date',
          'sender_id': 1,
        }),
        isNull,
      );
    });
  });

  group('XiangqiInboxRepository', () {
    test('asks for the chat list with inbox.join and resolves on the event', () async {
      final harness = await makeHarness();
      final chats = harness.repository.loadChats();
      await completeHandshake(harness);

      expect(harness.events, [kXiangqiInboxJoinEvent]);
      expect(harness.payloadOf(kXiangqiInboxJoinEvent), {'page': 1});

      harness.channel.fromServer(xiangqiChatsFrame([xiangqiFirstChatRow]));
      final contacts = await chats;

      expect(contacts, hasLength(1));
      expect(contacts.single.user.name, xiangqiFirstPeerName);
    });

    test('never has two inbox.chat.user requests in flight at once', () async {
      final harness = await makeHarness();

      final first = harness.repository.loadMessages(xiangqiFirstChatId);
      await completeHandshake(harness);
      expect(harness.events, [kXiangqiInboxChatUserEvent]);
      expect(harness.payloadOf(kXiangqiInboxChatUserEvent), {'chat_id': xiangqiFirstChatId});

      final second = harness.repository.loadMessages(xiangqiSecondChatId);
      await pumpEventQueue();
      // The second question is queued, not asked: a response names no conversation, so two in
      // flight at once would hand one chat's messages to the other.
      expect(harness.emits, hasLength(1));

      harness.channel.fromServer(xiangqiMessagesFrame([xiangqiMessageRow('c')]));
      await pumpEventQueue();
      expect((await first).single.text, 'c');

      // Only now, with the first answered, does the second go out.
      expect(harness.events, [kXiangqiInboxChatUserEvent, kXiangqiInboxChatUserEvent]);
      expect(harness.payloadOf(kXiangqiInboxChatUserEvent), {'chat_id': xiangqiFirstChatId});
      expect(harness.emits.last.data, {'chat_id': xiangqiSecondChatId});

      harness.channel.fromServer(
        xiangqiMessagesFrame([xiangqiMessageRow('哈哈哈', senderId: 200002)]),
      );
      await pumpEventQueue();
      expect((await second).single.text, '哈哈哈');
    });

    test('drops a page no request is waiting for instead of attaching it to the next', () async {
      final harness = await makeHarness();
      harness.repository.loadChats().ignore();
      await completeHandshake(harness);

      harness.channel.fromServer(xiangqiMessagesFrame([xiangqiMessageRow('orphan')]));
      await pumpEventQueue();

      final messages = harness.repository.loadMessages(xiangqiFirstChatId);
      await pumpEventQueue();
      harness.channel.fromServer(xiangqiMessagesFrame([xiangqiMessageRow('real')]));

      expect((await messages).single.text, 'real');
    });

    test('holds a second emit back until the spacing has passed', () async {
      final harness = await makeHarness(spacing: const Duration(milliseconds: 300));

      harness.repository.loadChats().ignore();
      await completeHandshake(harness);
      expect(harness.emits, hasLength(1));

      harness.repository.markRead(xiangqiFirstChatId).ignore();
      await pumpEventQueue();
      // The gap is at the call site, so the second frame is not on the wire yet — this is the whole
      // point of the spacer: the server drops a request that arrives inside the window and never
      // says so, which is indistinguishable from a conversation with no messages.
      expect(harness.emits, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(harness.events, [kXiangqiInboxJoinEvent, kXiangqiInboxMarkReadEvent]);
      expect(harness.payloadOf(kXiangqiInboxMarkReadEvent), {'chat_id': xiangqiFirstChatId});
    });

    test("sends a message with the session's own id, and a null chat id for a new one", () async {
      final harness = await makeHarness();
      final send = harness.repository.sendMessage(
        chatId: '',
        peerId: 200003,
        peerName: '棋友甲',
        text: 'hi',
      );
      await completeHandshake(harness);
      await send;

      expect(harness.events, [kXiangqiInboxNewMessageEvent]);
      expect(harness.payloadOf(kXiangqiInboxNewMessageEvent), {
        'sender_id': int.parse(xiangqiAccountId),
        'receiver_username': '棋友甲',
        'receiver_id': 200003,
        'message': 'hi',
        // No conversation yet, and the server wants a literal null for that: the capture's first
        // message to a stranger carries one, and the send is what creates the chat.
        'chat_id': null,
      });
    });

    test("writes a guest's id back as the string it is", () async {
      final harness = await makeHarness(userId: fx.xiangqiTestViewerId);
      final send = harness.repository.sendMessage(
        chatId: xiangqiFirstChatId,
        peerId: xiangqiFirstPeerId,
        peerName: xiangqiFirstPeerName,
        text: 'hi',
      );
      await completeHandshake(harness);
      await send;

      // An account's `sub` is a number and a guest's is a string; the payload carries whatever the
      // token carries rather than a number invented for a guest.
      final payload = harness.payloadOf(kXiangqiInboxNewMessageEvent)! as Map<String, Object?>;
      expect(payload['sender_id'], fx.xiangqiTestViewerId);
      expect(payload['chat_id'], xiangqiFirstChatId);
    });

    test('never emits chat.agreement, which mutes a guest session', () async {
      final harness = await makeHarness();
      harness.repository.loadChats().ignore();
      await completeHandshake(harness);
      harness.repository.loadMessages(xiangqiFirstChatId).ignore();
      harness.repository.markRead(xiangqiFirstChatId).ignore();
      harness.repository
          .sendMessage(
            chatId: xiangqiFirstChatId,
            peerId: xiangqiFirstPeerId,
            peerName: xiangqiFirstPeerName,
            text: 'hi',
          )
          .ignore();
      await pumpEventQueue();

      expect(harness.emits, isNotEmpty);
      expect(harness.events, isNot(contains('chat.agreement')));
    });

    test('gives up on a request the server never answers', () async {
      final harness = await makeHarness(responseTimeout: const Duration(milliseconds: 50));
      final messages = harness.repository.loadMessages(xiangqiFirstChatId);
      await completeHandshake(harness);

      await expectLater(messages, throwsA(isA<TimeoutException>()));
    });

    test('leaves the inbox when it is disposed, and never closes the shared socket', () async {
      final harness = await makeHarness();
      harness.repository.loadChats().ignore();
      await completeHandshake(harness);

      harness.repository.dispose();
      await pumpEventQueue();

      expect(harness.events, [kXiangqiInboxJoinEvent, kXiangqiInboxLeaveEvent]);
      // The socket is shared with the online-game controller, so a disposed inbox must not take it
      // down with it.
      expect(harness.channel.closed, isFalse);
    });
  });
}
