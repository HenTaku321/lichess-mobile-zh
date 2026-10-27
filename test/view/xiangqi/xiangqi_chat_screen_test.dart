// Tests for the two screens xiangqi.com's chat is read on: the hub of rooms, and one room.
//
// The hub is driven over a stubbed HTTP client and the room over a fake socket, because those are
// the two transports the two halves of the feature use — the rooms are a REST read and the messages
// are a conversation. The values are invented; the shapes come from `xiangqi-com-re/docs/chat.md`.

import 'dart:async';
import 'dart:convert';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

const _openFrame =
    '0{"sid":"s1","upgrades":[],"pingInterval":8000,"pingTimeout":20000,"maxPayload":1000000}';
const _connectAckFrame = '40/xiangqi,{"sid":"s1"}';

/// A `WebSocketChannel` that carries raw text frames.
class FakeChatChannel() implements WebSocketChannel {
  final List<Object?> sent = [];
  final StreamController<dynamic> _incoming = StreamController<dynamic>.broadcast();
  late final WebSocketSink _sink = _FakeChatSink(this);

  void fromServer(dynamic data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  void event(String name, [Object? data]) => fromServer('42/xiangqi,${jsonEncode([name, ?data])}');

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

class FakeChatStorage(final XiangqiSession? session) implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession session) async {}

  @override
  Future<void> delete() async {}
}

Map<String, Object?> message({required int id, required String text, String sender = 'a-player'}) =>
    {
      'id': id,
      'message': text,
      'message_type': 1,
      'sender_id': 42,
      'sender_name': sender,
      'sender_type': 10,
      'timestamp': 'Mon, 19 Oct 2026 08:37:29 GMT',
    };

Map<String, Object?> page(List<Map<String, Object?>> items) => {
  'data': {'has_next_page': false, 'items': items},
};

/// Opens the hub over a client that answers the room list, and a socket a room can be opened on.
///
/// The socket is faked even though the hub itself never opens one: a room opened from it does, and
/// a room that minted a guest session over the real client would leave the test with a request in
/// flight and a timer behind it.
Future<FakeChatChannelFactory> pumpHub(WidgetTester tester) async {
  final factory = FakeChatChannelFactory();
  final client = MockClient(
    (request) async => http.Response.bytes(
      utf8.encode(
        jsonEncode(const [
          {'name': 'English', 'description': 'This is global channel.', 'code': 'US'},
          {'name': '中文', 'description': 'This is Chinese Channel. ', 'code': 'CN'},
        ]),
      ),
      200,
      headers: const {'content-type': 'application/json'},
    ),
  );

  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        home: XiangqiChatScreen(),
      ),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
        webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(factory),
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
      },
    ),
  );
  await tester.pumpAndSettle();
  return factory;
}

/// Opens one room, and hands back the socket the server's side is driven on.
Future<FakeChatChannel> pumpRoom(
  WidgetTester tester, {
  XiangqiChatRoomKey roomKey = (kind: XiangqiChatKind.lobby, room: '中文'),
}) async {
  final factory = FakeChatChannelFactory();
  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        home: XiangqiChatRoomScreen(roomKey: roomKey, title: '中文'),
      ),
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
      },
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final channel = factory.channels.single;
  channel.fromServer(_openFrame);
  channel.fromServer(_connectAckFrame);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return channel;
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiChatScreen', () {
    testWidgets('lists the public rooms, and says what a club takes', (tester) async {
      await pumpHub(tester);

      expect(find.text('English'), findsOneWidget);
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('Tiếng Việt'), findsNothing);
      // The club section is an empty state that explains itself: this account is in no club, and a
      // list that was simply missing would read as a fault.
      expect(find.text('You are not in a club yet.'), findsOneWidget);
    });

    testWidgets('opens a room when one is tapped', (tester) async {
      final factory = await pumpHub(tester);
      await tester.tap(find.text('English'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(XiangqiChatRoomScreen), findsOneWidget);

      // And the room it opened is English's, which is the name the socket is given — not the room
      // the hub happens to list first.
      final channel = factory.channels.single;
      channel.fromServer(_openFrame);
      channel.fromServer(_connectAckFrame);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        channel.sent.whereType<String>().any((frame) => frame.contains('"room":"English"')),
        isTrue,
      );
    });
  });

  group('XiangqiChatRoomScreen', () {
    testWidgets("shows the room's history, oldest at the bottom", (tester) async {
      final channel = await pumpRoom(tester);
      channel.event(
        'chat.lobby.messages.success',
        page([message(id: 2, text: 'second'), message(id: 1, text: 'first')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(find.text('a-player'), findsNWidgets(2));
      // The composer is live once the room is: a room that cannot be written in is a room that has
      // not connected yet.
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    });

    testWidgets('adds a message that arrives, and sends what is typed', (tester) async {
      final channel = await pumpRoom(tester);
      channel.event('chat.lobby.messages.success', page([message(id: 1, text: 'first')]));
      await tester.pumpAndSettle();

      channel.event('chat.new.lobby.message.success', message(id: 2, text: 'second'));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hello');
      // Rebuild the ValueListenableBuilder before tapping its formerly disabled button.
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      // The composer clears as soon as the send is accepted; a failure puts the draft back.
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);

      // The frame is queued behind the spacing the server needs between two requests.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
      final frames = channel.sent.whereType<String>().where((f) => f.contains('new.message'));
      expect(frames.length, 1);
      expect(frames.single, contains('"message":"hello"'));
      expect(frames.single, contains('"room":"中文"'));
    });

    testWidgets('says so when the room has nothing in it', (tester) async {
      final channel = await pumpRoom(tester);
      channel.event('chat.lobby.messages.success', page([]));
      await tester.pumpAndSettle();
      expect(find.text('No messages yet.'), findsOneWidget);
    });
  });
}
