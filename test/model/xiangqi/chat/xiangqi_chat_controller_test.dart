// Tests for reading and writing one xiangqi.com chat room.
//
// The controller is driven over a fake socket, and the frames it writes are read back as text: what
// is being pinned is the conversation — which request goes out when, and what is never sent at all.
// The one thing that must never be sent is `chat.agreement`: a guest that sends it has its whole
// session go quiet, silently, and reading a room does not need it. See
// `xiangqi-com-re/docs/chat.md`.
//
// The values are invented. The shapes come from the 2026-10-19 probe.

import 'dart:async';
import 'dart:convert';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../network/fake_http_client_factory.dart';
import '../../../test_container.dart';

/// The server's open frame, announcing the heartbeat the client should use.
const _openFrame =
    '0{"sid":"s1","upgrades":[],"pingInterval":8000,"pingTimeout":20000,"maxPayload":1000000}';

/// The connect ack for the `/xiangqi` namespace.
const _connectAckFrame = '40/xiangqi,{"sid":"s1"}';

/// A `WebSocketChannel` that carries raw text frames and records what was written to it.
class FakeChatChannel() implements WebSocketChannel {
  /// Every frame the client wrote, in order.
  final List<Object?> sent = [];

  final StreamController<dynamic> _incoming = StreamController<dynamic>.broadcast();

  late final WebSocketSink _sink = _FakeChatSink(this);

  /// Pushes one raw frame from the server.
  void fromServer(dynamic data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  /// Pushes one event, spelled the way the server spells one.
  void event(String name, [Object? data]) {
    fromServer('42/xiangqi,${jsonEncode([name, ?data])}');
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  void pipe(StreamChannel<dynamic> other) {}

  @override
  StreamChannel<S> cast<S>() => throw UnimplementedError();

  @override
  StreamChannel<dynamic> changeSink(StreamSink<dynamic> Function(StreamSink<dynamic>) change) =>
      throw UnimplementedError();

  @override
  StreamChannel<dynamic> changeStream(Stream<dynamic> Function(Stream<dynamic>) change) =>
      throw UnimplementedError();

  @override
  StreamChannel<S> transform<S>(StreamChannelTransformer<S, dynamic> transformer) =>
      throw UnimplementedError();

  @override
  StreamChannel<dynamic> transformSink(StreamSinkTransformer<dynamic, dynamic> transformer) =>
      throw UnimplementedError();

  @override
  StreamChannel<dynamic> transformStream(StreamTransformer<dynamic, dynamic> transformer) =>
      throw UnimplementedError();
}

class _FakeChatSink(final FakeChatChannel _channel) implements WebSocketSink {
  @override
  void add(dynamic data) => _channel.sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<dynamic> get done => Future<void>.value();
}

/// Hands out [FakeChatChannel]s and keeps them, so a test can drive the server's side.
class FakeChatChannelFactory() implements WebSocketChannelFactory {
  final List<FakeChatChannel> channels = [];

  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final channel = FakeChatChannel();
    channels.add(channel);
    return channel;
  }
}

/// A storage with no disk behind it.
class FakeChatStorage(final XiangqiSession? session) implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession session) async {}

  @override
  Future<void> delete() async {}
}

/// One message of a room, as the wire writes one.
Map<String, Object?> message({required int id, required String text, int senderId = 42}) => {
  'id': id,
  'message': text,
  'message_type': 1,
  'sender_id': senderId,
  'sender_name': 'a-player',
  'sender_type': 10,
  'timestamp': 'Mon, 19 Oct 2026 08:37:29 GMT',
};

/// The envelope a history page arrives in.
Map<String, Object?> page(List<Map<String, Object?>> items, {bool hasNext = false}) => {
  'data': {'has_next_page': hasNext, 'items': items},
};

/// The room these tests read: the Chinese one, whose name is not its code.
const _key = (kind: XiangqiChatKind.lobby, room: '中文');

/// A container with a signed-in account and a fake socket, and the channel it opened.
Future<(ProviderContainer, FakeChatChannel)> openRoom({XiangqiChatRoomKey key = _key}) async {
  final factory = FakeChatChannelFactory();
  final container = await makeContainer(
    overrides: {
      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
        FakeChatStorage(
          const XiangqiSession(
            userId: '100001',
            name: 'a-player',
            accessToken: 'stored-token',
            isGuest: false,
          ),
        ),
      ),
      webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(factory),
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
        (ref) =>
            FakeHttpClientFactory(() => MockClient((request) async => http.Response('{}', 200))),
      ),
    },
  );

  // A listener is what a screen is: without one the controller is collected between two statements
  // of a test, and the room would be read again from the beginning every time.
  final subscription = container.listen(xiangqiChatControllerProvider(key), (_, _) {});
  addTearDown(subscription.close);

  await pumpEventQueue();
  final channel = factory.channels.single;
  channel.fromServer(_openFrame);
  channel.fromServer(_connectAckFrame);
  await pumpEventQueue();
  return (container, channel);
}

/// The events a channel was asked for, in order, with their payloads.
List<(String, Object?)> requestsOf(FakeChatChannel channel) {
  final requests = <(String, Object?)>[];
  for (final frame in channel.sent) {
    if (frame is! String || !frame.startsWith('42')) continue;
    final decoded = jsonDecode(frame.substring(frame.indexOf('[')));
    if (decoded is! List || decoded.isEmpty) continue;
    requests.add((decoded[0] as String, decoded.length > 1 ? decoded[1] : null));
  }
  return requests;
}

void main() {
  group('joining a room', () {
    test("asks for the first page of the room's history, and nothing else", () async {
      final (_, channel) = await openRoom();

      final requests = requestsOf(channel);
      expect(requests.length, 1);
      expect(requests.single.$1, 'chat_v2.messages');
      expect(requests.single.$2, {'type': 'lobby', 'room': '中文', 'page': 1});
      // **The trap.** A guest that sends this has its whole session go quiet, and reading a room
      // does not need it — so it is never sent, by anyone.
      expect(requests.map((r) => r.$1), isNot(contains('chat.agreement')));
    });

    test('reads the page oldest first, and says whether there is more', () async {
      final (container, channel) = await openRoom();
      channel.event(
        'chat.lobby.messages.success',
        page([message(id: 2, text: 'second'), message(id: 1, text: 'first')], hasNext: true),
      );
      await pumpEventQueue();

      final state = container.read(xiangqiChatControllerProvider(_key));
      expect(state.messages.map((m) => m.message), ['first', 'second']);
      expect(state.hasMore, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.isConnected, isTrue);
    });

    test('puts an older page in front of what is already read', () async {
      final (container, channel) = await openRoom();
      channel.event(
        'chat.lobby.messages.success',
        page([message(id: 2, text: 'second')], hasNext: true),
      );
      await pumpEventQueue();

      container.read(xiangqiChatControllerProvider(_key).notifier).loadMore();
      // The request waits out the spacing the server needs between two of them.
      await Future<void>.delayed(kXiangqiChatRequestSpacing + const Duration(milliseconds: 200));
      expect(requestsOf(channel).last.$2, {'type': 'lobby', 'room': '中文', 'page': 2});

      channel.event('chat.lobby.messages.success', page([message(id: 1, text: 'first')]));
      await pumpEventQueue();
      expect(container.read(xiangqiChatControllerProvider(_key)).messages.map((m) => m.message), [
        'first',
        'second',
      ]);
    });
  });

  group('a message that arrives', () {
    test('is added to the room, and its echo is not added twice', () async {
      final (container, channel) = await openRoom();
      channel.event('chat.lobby.messages.success', page([message(id: 1, text: 'first')]));
      await pumpEventQueue();

      channel.event('chat.new.lobby.message.success', message(id: 2, text: 'second'));
      await pumpEventQueue();
      expect(container.read(xiangqiChatControllerProvider(_key)).messages.map((m) => m.message), [
        'first',
        'second',
      ]);

      // The same message again — which is what a reconnect and a re-read of a page looks like.
      channel.event('chat.new.lobby.message.success', message(id: 2, text: 'second'));
      await pumpEventQueue();
      expect(container.read(xiangqiChatControllerProvider(_key)).messages.length, 2);
    });
  });

  group('sending', () {
    test('writes the room, the kind and the text, and asks for no receipt', () async {
      final (container, channel) = await openRoom();
      channel.event('chat.lobby.messages.success', page([]));
      await pumpEventQueue();

      await container.read(xiangqiChatControllerProvider(_key).notifier).send('  hello  ');
      // The spacing is what the wait is for: the request goes out a beat after the last one.
      await Future<void>.delayed(kXiangqiChatRequestSpacing + const Duration(milliseconds: 200));

      final sent = requestsOf(channel).last;
      expect(sent.$1, 'chat_v2.new.message');
      expect(sent.$2, {'type': 'lobby', 'room': '中文', 'message': 'hello'});
      // No ack id: the server does not ack a message, and asking for one would burn ten seconds
      // waiting for a frame that never comes.
      final frame = channel.sent.last! as String;
      expect(frame.startsWith('42/xiangqi,['), isTrue);
    });

    test('sends nothing at all for an empty message', () async {
      final (container, channel) = await openRoom();
      channel.event('chat.lobby.messages.success', page([]));
      await pumpEventQueue();
      final before = requestsOf(channel).length;

      await container.read(xiangqiChatControllerProvider(_key).notifier).send('   ');
      expect(requestsOf(channel).length, before);
    });
  });

  group("a game's own chat", () {
    test("is the same conversation under the game's id", () async {
      final (_, channel) = await openRoom(key: (kind: XiangqiChatKind.game, room: 'AbCdEf1234'));
      expect(requestsOf(channel).single.$2, {'type': 'game', 'room': 'AbCdEf1234', 'page': 1});
    });
  });
}
