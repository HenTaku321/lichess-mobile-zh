// Tests for the hand-written xiangqi.com socket client.
//
// Two things are being pinned here. First, the frame parser: every shape the Rust `parse_frame`
// in `xiangqi-tg/src/socketio.rs` has a test for is ported one for one, plus the frames that
// parser deliberately ignores and this one has to classify anyway (open, connect, ack, binary).
// Second, the client's own conversation: handshake, heartbeat, ack correlation, backoff — and the
// one thing that must never happen, which is a xiangqi socket disturbing the lichess one.
//
// The transport is a fake `WebSocketChannel` written out below rather than the repo's
// `test/network/fake_websocket_channel.dart`: that one runs `jsonDecode` on every outgoing frame
// with no try/catch (`fake_websocket_channel.dart:186`), so the first `40/xiangqi,{...}` the client
// writes throws a `FormatException` out of the sink. It is built for lichess's JSON protocol and
// this is not that.

import 'dart:async';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../test_container.dart';

/// A `WebSocketChannel` that carries raw text frames and records what was written to it.
class FakeXiangqiChannel() implements WebSocketChannel {
  /// Every frame the client wrote, in order.
  final List<Object?> sent = [];

  final StreamController<dynamic> _incoming = StreamController<dynamic>.broadcast();

  late final WebSocketSink _sink = _FakeXiangqiSink(this);

  /// Whether the client asked for the channel to be closed.
  bool closed = false;

  /// Pushes one raw frame from the server.
  void fromServer(dynamic data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  /// Drops the connection the way a peer hanging up does.
  void closeFromServer([Object? error]) {
    if (_incoming.isClosed) return;
    if (error != null) _incoming.addError(error);
    _incoming.close();
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => closed ? 1000 : null;

  @override
  String? get closeReason => closed ? 'OK' : null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  // The StreamChannel surface the socket client never touches.
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

class _FakeXiangqiSink(final FakeXiangqiChannel _channel) implements WebSocketSink {
  @override
  void add(dynamic data) => _channel.sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closed = true;
  }

  @override
  Future<dynamic> get done => Future<void>.value();
}

/// Hands out [FakeXiangqiChannel]s and keeps them, so a test can drive the server's side.
class FakeXiangqiChannelFactory() implements WebSocketChannelFactory {
  final List<FakeXiangqiChannel> channels = [];
  final List<String> urls = [];

  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 1),
  }) async {
    urls.add(url);
    final channel = FakeXiangqiChannel();
    channels.add(channel);
    return channel;
  }
}

/// A factory whose `create` always fails, for the redaction test.
class const ThrowingXiangqiChannelFactory(final Object error) implements WebSocketChannelFactory {
  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 1),
  }) => Future.error(error);
}

/// The server's open frame, announcing the heartbeat the client should use.
const openFrame =
    '0{"sid":"s1","upgrades":[],"pingInterval":8000,"pingTimeout":20000,"maxPayload":1000000}';

/// The connect ack for the `/xiangqi` namespace.
const connectAckFrame = '40/xiangqi,{"sid":"s1"}';

/// Drives [client] through a handshake inside a [fakeAsync] zone, without awaiting anything.
///
/// Inside `fakeAsync` a test cannot `await`, so every step is a `flushMicrotasks` — which is all
/// this needs, since the whole handshake is microtasks: the token read, the channel creation and
/// the two server frames.
FakeXiangqiChannel handshakeNow(
  FakeAsync async,
  XiangqiSocketClient client,
  FakeXiangqiChannelFactory factory,
) {
  client.connect().ignore();
  async.flushMicrotasks();
  final channel = factory.channels.last;
  channel.fromServer(openFrame);
  channel.fromServer(connectAckFrame);
  async.flushMicrotasks();
  return channel;
}

void main() {
  group('frame parsing, ported from the Rust parser', () {
    test('v4 event with data', () {
      final event = parseXiangqiSocketEvent(
        '42["chat.message",{"message":"hi","sender_name":"A"}]',
      );
      expect(event?.name, 'chat.message');
      expect((event!.data! as Map)['message'], 'hi');
    });

    test('v4 event with no data', () {
      final event = parseXiangqiSocketEvent('42["user.notification"]');
      expect(event?.name, 'user.notification');
      expect(event?.data, isNull);
    });

    test('v2 namespace frame', () {
      final event = parseXiangqiSocketEvent('42/xiangqi,["game.chat",{"message":"x"}]');
      expect(event?.name, 'game.chat');
    });

    test('v3 raw event, with no engine.io prefix', () {
      final event = parseXiangqiSocketEvent('2["club.chat.new.message",{"message":"y"}]');
      expect(event?.name, 'club.chat.new.message');
    });

    test('nested and escaped json', () {
      final event = parseXiangqiSocketEvent(
        r'42["chat.message",{"message":"a]b\"c","x":{"y":[1,2]}}]',
      );
      expect((event!.data! as Map)['message'], 'a]b"c');
      expect((event.data! as Map)['x'], {
        'y': [1, 2],
      });
    });

    test('non-event frames are refused', () {
      expect(parseXiangqiSocketEvent('0{"sid":"x"}'), isNull);
      expect(parseXiangqiSocketEvent('2'), isNull);
      expect(parseXiangqiSocketEvent('3'), isNull);
      expect(parseXiangqiSocketEvent(''), isNull);
      expect(parseXiangqiSocketEvent('hello'), isNull);
    });

    test('polling concatenated frames', () {
      // An engine.io polling body can carry several frames at once; the Rust side scans for `42[`
      // starts and parses each. Trailing content is ignored by the array matcher, so the same
      // scan works here.
      const raw =
          '0{"sid":"s"}42["chat.message",{"message":"m1"}]42["inbox.message",{"message":"m2"}]';
      final names = <String>[];
      var i = 0;
      while (true) {
        final at = raw.indexOf('42[', i);
        if (at == -1) break;
        final event = parseXiangqiSocketEvent(raw.substring(at));
        if (event != null) names.add(event.name);
        i = at + 2;
      }
      expect(names, ['chat.message', 'inbox.message']);
    });

    test('namespace event with no engine.io prefix', () {
      final event = parseXiangqiSocketEvent(
        '2/xiangqi,["lobby.game.end",{"black_id":"a","red_id":"b","id":"g1"}]',
      );
      expect(event?.name, 'lobby.game.end');
      expect((event!.data! as Map)['id'], 'g1');
    });
  });

  group('frame parsing, the shapes the Rust parser ignores', () {
    test('the engine.io open frame, heartbeat and all', () {
      final frame = parseXiangqiFrame(openFrame);
      expect(frame, isA<XiangqiOpenFrame>());
      final open = frame! as XiangqiOpenFrame;
      expect(open.pingInterval, const Duration(seconds: 8));
      expect(open.pingTimeout, const Duration(seconds: 20));
      expect(open.maxPayload, 1000000);
    });

    test('an engine.io ping is told apart from a bare socket.io event', () {
      expect(parseXiangqiFrame('2'), isA<XiangqiPingFrame>());
      expect((parseXiangqiFrame('2probe')! as XiangqiPingFrame).payload, 'probe');
      expect(parseXiangqiFrame('2["event"]'), isA<XiangqiEventFrame>());
      expect(parseXiangqiFrame('2/xiangqi,["event"]'), isA<XiangqiEventFrame>());
    });

    test('pong, close and an empty message are frames but not ones we act on', () {
      expect(parseXiangqiFrame('3'), isA<XiangqiPongFrame>());
      expect(parseXiangqiFrame('3probe'), isA<XiangqiPongFrame>());
      expect(parseXiangqiFrame('4'), isNull, reason: 'a message with no body');
      expect(parseXiangqiFrame('1'), isNull, reason: 'close carries nothing');
      expect(parseXiangqiFrame('99'), isNull);
    });

    test('connect and connect-error', () {
      final connect = parseXiangqiFrame(connectAckFrame);
      expect(connect, isA<XiangqiConnectFrame>());
      expect((connect! as XiangqiConnectFrame).namespace, '/xiangqi');

      final failure = parseXiangqiFrame('44/xiangqi,{"message":"bad token"}');
      expect(failure, isA<XiangqiConnectErrorFrame>());
      expect((failure! as XiangqiConnectErrorFrame).data, {'message': 'bad token'});
    });

    test('disconnect', () {
      final frame = parseXiangqiFrame('41/xiangqi,');
      expect(frame, isA<XiangqiDisconnectFrame>());
      expect((frame! as XiangqiDisconnectFrame).namespace, '/xiangqi');
    });

    test('an ack keeps its arguments', () {
      final frame = parseXiangqiFrame('43/xiangqi,7[{"status":"OK"}]');
      expect(frame, isA<XiangqiAckFrame>());
      final ack = frame! as XiangqiAckFrame;
      expect(ack.ackId, 7);
      expect(ack.args, [
        {'status': 'OK'},
      ]);
    });

    test('an event that asks to be acked carries the id it asked on', () {
      final frame = parseXiangqiFrame('42/xiangqi,5["game.move.opponent",{"move":"h3e3"}]');
      expect(frame, isA<XiangqiEventFrame>());
      final event = frame! as XiangqiEventFrame;
      expect(event.name, 'game.move.opponent');
      expect(event.ackId, 5);
      expect(event.data, {'move': 'h3e3'});
    });

    test('a binary event takes its name from the array after the attachments count', () {
      final frame = parseXiangqiFrame('45/xiangqi,1-["chat.message",{"b64":true}]');
      expect(frame, isA<XiangqiEventFrame>());
      final event = frame! as XiangqiEventFrame;
      expect(event.name, 'chat.message');
      expect(event.binary, isTrue);
      expect(event.data, {'b64': true});
    });

    test('a truncated array is not a frame', () {
      expect(parseXiangqiFrame('42/xiangqi,["game.chat"'), isNull);
      expect(parseXiangqiFrame('43/xiangqi,'), isNull, reason: 'an ack with no id');
      expect(parseXiangqiFrame('42/xiangqi,[1,2]'), isNull, reason: 'the name must be a string');
    });
  });

  group('XiangqiSocketClient', () {
    late FakeXiangqiChannelFactory factory;
    late XiangqiSocketClient client;
    late FakeXiangqiChannel channel;

    setUp(() {
      factory = FakeXiangqiChannelFactory();
      client = XiangqiSocketClient(channelFactory: factory, getToken: () async => 'jwt-abc');
      addTearDown(client.dispose);
    });

    /// Connects, serves the handshake, and returns once the client is up.
    Future<void> connect() async {
      final connecting = client.connect();
      await pumpEventQueue();
      channel = factory.channels.single;
      channel.fromServer(openFrame);
      channel.fromServer(connectAckFrame);
      await connecting;
    }

    test('the handshake carries the token and completes on the connect ack', () async {
      final connecting = client.connect();
      await pumpEventQueue();

      expect(factory.channels, hasLength(1));
      expect(factory.urls.single, startsWith('wss://api.xiangqi.com/socket.io/'));
      expect(factory.urls.single, contains('EIO=4'));
      expect(factory.urls.single, contains('transport=websocket'));
      expect(factory.urls.single, contains('jwt=jwt-abc'));
      // The token goes out in the connect packet too, which is where the server reads it.
      expect(factory.channels.single.sent, ['40/xiangqi,{"token":"jwt-abc"}']);
      expect(client.isConnected, isFalse);

      factory.channels.single.fromServer(openFrame);
      factory.channels.single.fromServer(connectAckFrame);
      await connecting;

      expect(client.isConnected, isTrue);
      await expectLater(client.firstConnection, completes);
    });

    test('answers the server heartbeat with a pong', () async {
      await connect();

      channel.fromServer('2');
      await pumpEventQueue();
      expect(channel.sent.last, '3');

      channel.fromServer('2probe');
      await pumpEventQueue();
      expect(channel.sent.last, '3probe');
    });

    test('refuses to connect with no stored session', () async {
      final bare = XiangqiSocketClient(
        channelFactory: FakeXiangqiChannelFactory(),
        getToken: () async => null,
      );
      addTearDown(bare.dispose);
      await expectLater(bare.connect(), throwsA(isA<XiangqiSocketException>()));
    });

    test('refuses to connect once disposed', () async {
      final gone = XiangqiSocketClient(
        channelFactory: FakeXiangqiChannelFactory(),
        getToken: () async => 'jwt-abc',
      );
      await gone.dispose();
      await expectLater(gone.connect(), throwsA(isA<XiangqiSocketException>()));
    });

    test('refuses to emit while there is no connection', () async {
      await expectLater(client.emit('g_v2.get'), throwsA(isA<XiangqiSocketException>()));
      expect(() => client.emitNoAck('chat.message'), throwsA(isA<XiangqiSocketException>()));
    });

    test('delivers server events on the stream', () async {
      await connect();
      final received = <XiangqiSocketEvent>[];
      client.stream.listen(received.add);

      channel.fromServer('42/xiangqi,["game.move.opponent",{"move":"h3e3"}]');
      await pumpEventQueue();

      expect(received.single.name, 'game.move.opponent');
      expect(received.single.data, {'move': 'h3e3'});
    });

    test('announces each successful handshake on connectedStream', () async {
      var connections = 0;
      client.connectedStream.listen((_) => connections++);
      await connect();
      await pumpEventQueue();
      expect(connections, 1);
    });

    test('emits with an ack id and resolves with the ack argument, not the list', () async {
      await connect();

      final ack = client.emit('g_v2.get', data: {'game_id': 'g1'});
      await pumpEventQueue();
      expect(channel.sent.last, '42/xiangqi,1["g_v2.get",{"game_id":"g1"}]');

      channel.fromServer('43/xiangqi,1[{"status":"OK"}]');
      expect(await ack, {'status': 'OK'});
    });

    test('the ack id, not the order, pairs a reply with its emit', () async {
      await connect();

      final first = client.emit('g_v2.get', data: {'game_id': 'g1'});
      final second = client.emit('chat.join', data: {'id': 'c1'});
      await pumpEventQueue();
      expect(channel.sent[channel.sent.length - 2], '42/xiangqi,1["g_v2.get",{"game_id":"g1"}]');
      expect(channel.sent.last, '42/xiangqi,2["chat.join",{"id":"c1"}]');

      channel.fromServer('43/xiangqi,2[{"status":"OK","which":"second"}]');
      expect(await second, {'status': 'OK', 'which': 'second'});

      channel.fromServer('43/xiangqi,1[{"status":"OK","which":"first"}]');
      expect(await first, {'status': 'OK', 'which': 'first'});
    });

    test('an emit with no data sends a one-element array', () async {
      await connect();

      final ack = client.emit('game.leave');
      await pumpEventQueue();
      expect(channel.sent.last, '42/xiangqi,1["game.leave"]');

      // An empty ack array is a legitimate answer: no argument at all.
      channel.fromServer('43/xiangqi,1[]');
      expect(await ack, isNull);
    });

    test('hands the REDIRECT ack back untouched, for the caller to follow', () async {
      await connect();

      // A `g_v2.get` on a finished game answers with a redirect rather than a game. The client
      // does not interpret it: reading the `event` field and re-sending under that name is the
      // caller's job, so what is pinned here is the payload, not a decision.
      final ack = client.emit('g_v2.get', data: {'id': 'g1'});
      await pumpEventQueue();
      channel.fromServer('43/xiangqi,1[{"event":"game.archived.get","status":"REDIRECT"}]');

      expect(await ack, {'event': 'game.archived.get', 'status': 'REDIRECT'});
    });

    test('emitNoAck sends without asking for an answer', () async {
      await connect();

      // Private chat is never acked, so this is the only honest way to send one.
      client.emitNoAck('chat.message', data: {'text': 'hi'});
      await pumpEventQueue();

      expect(channel.sent.last, '42/xiangqi,["chat.message",{"text":"hi"}]');
    });

    test('an emit that is never acked times out', () {
      fakeAsync((async) {
        final timedFactory = FakeXiangqiChannelFactory();
        final timed = XiangqiSocketClient(
          channelFactory: timedFactory,
          getToken: () async => 'jwt-abc',
        );
        handshakeNow(async, timed, timedFactory);

        Object? error;
        timed
            .emit('g_v2.get', data: {'game_id': 'g1'}, timeout: const Duration(seconds: 5))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        expect(error, isNull);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(error, isA<TimeoutException>());
        timed.dispose();
      });
    });

    test('a dropped connection fails the emits that were waiting', () async {
      await connect();

      // The expectation is attached *before* the drop, not after it. `emit` hands back the very
      // future the teardown error lands on, and an error delivered to a future with no listener is
      // reported to the test zone as unhandled — which fails the test no matter what a later
      // assertion says. The assertion itself is the same one, in the same order.
      final acked = expectLater(
        client.emit('g_v2.get', data: {'game_id': 'g1'}),
        throwsA(isA<XiangqiSocketException>()),
      );
      await pumpEventQueue();
      channel.closeFromServer();
      await pumpEventQueue();

      await acked;
      expect(client.isConnected, isFalse);
    });
  });

  group('reconnection', () {
    test('gives up when the server stops pinging, then reconnects', () {
      fakeAsync((async) {
        final factory = FakeXiangqiChannelFactory();
        final client = XiangqiSocketClient(
          channelFactory: factory,
          getToken: () async => 'jwt-abc',
          pingInterval: const Duration(seconds: 8),
          pingTimeout: const Duration(seconds: 20),
          reconnectDelay: const Duration(seconds: 1),
        );
        final channel = handshakeNow(async, client, factory);
        expect(client.isConnected, isTrue);

        // A ping at t+27 s pushes the 28 s watchdog back.
        async.elapse(const Duration(seconds: 27));
        channel.fromServer('2');
        async.flushMicrotasks();
        expect(client.isConnected, isTrue);
        expect(channel.sent.last, '3');

        async.elapse(const Duration(seconds: 27));
        expect(client.isConnected, isTrue, reason: 'the watchdog was pushed back by the ping');

        // t+55 s: nothing heard for 28 s, so the connection is dropped.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(client.isConnected, isFalse);
        expect(channel.closed, isTrue);

        // One backoff step later, a fresh channel, still on the same URL.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(factory.channels, hasLength(2));
        expect(factory.urls.last, contains('jwt=jwt-abc'));

        client.dispose();
      });
    });

    test('doubles the wait on each failed attempt', () {
      fakeAsync((async) {
        final factory = FakeXiangqiChannelFactory();
        final client = XiangqiSocketClient(
          channelFactory: factory,
          getToken: () async => 'jwt-abc',
          reconnectDelay: const Duration(seconds: 1),
          maxReconnectDelay: const Duration(seconds: 8),
        );
        // The backoff only resets on a handshake, so a connection that never completes one
        // escalates.
        final channel = handshakeNow(async, client, factory);
        channel.closeFromServer();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(factory.channels, hasLength(2));

        factory.channels[1].closeFromServer();
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 1999));
        async.flushMicrotasks();
        expect(factory.channels, hasLength(2), reason: 'the second wait is twice the first');

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(factory.channels, hasLength(3));

        client.dispose();
      });
    });

    test('does not reconnect after close()', () {
      fakeAsync((async) {
        final factory = FakeXiangqiChannelFactory();
        final client = XiangqiSocketClient(
          channelFactory: factory,
          getToken: () async => 'jwt-abc',
          reconnectDelay: const Duration(seconds: 1),
        );
        final channel = handshakeNow(async, client, factory);

        client.close();
        async.flushMicrotasks();
        expect(channel.closed, isTrue);

        // Long enough for several backoff steps, had any been scheduled.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(factory.channels, hasLength(1), reason: 'a closed client stays closed');

        client.dispose();
      });
    });

    test('a connect failure never carries the token', () {
      const secret = 'eyJhbGciOiJIUzI1NiJ9.SUPERSECRETPAYLOAD.sig';
      fakeAsync((async) {
        final client = XiangqiSocketClient(
          channelFactory: const ThrowingXiangqiChannelFactory(
            'could not reach wss://api.xiangqi.com/socket.io/?EIO=4&transport=websocket&jwt=$secret',
          ),
          getToken: () async => secret,
        );

        Object? error;
        client.connect().then(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        async.flushMicrotasks();

        expect(error, isA<XiangqiSocketException>());
        expect('$error', contains('<redacted-jwt>'));
        expect('$error', isNot(contains(secret)));
        expect('$error', isNot(contains('SUPERSECRETPAYLOAD')));

        client.dispose();
      });
    });
  });

  group('coexistence with the lichess socket', () {
    test('opening a xiangqi socket leaves the lichess socket exactly where it was', () async {
      final container = await makeContainer();
      final pool = container.read(socketPoolProvider);

      final lichess = pool.open(Uri(path: '/lobby/socket/v5'));
      // `SocketPool.open` connects synchronously as far as its first await, so the client is
      // already active by the time it is returned.
      expect(lichess.isActive, isTrue);
      expect(identical(pool.currentClient, lichess), isTrue);

      final factory = FakeXiangqiChannelFactory();
      final xiangqi = XiangqiSocketClient(channelFactory: factory, getToken: () async => 'jwt-abc');
      addTearDown(xiangqi.dispose);

      final connecting = xiangqi.connect();
      await pumpEventQueue();
      factory.channels.single.fromServer(openFrame);
      factory.channels.single.fromServer(connectAckFrame);
      await connecting;
      expect(xiangqi.isConnected, isTrue);

      // The pool closes every other connection it holds whenever it opens one, which is what makes
      // it unusable for a second service. Had the xiangqi socket gone through the pool, this
      // client would have been closed -- the same object, with `isActive` reset to false.
      expect(lichess.isActive, isTrue);
      expect(identical(pool.currentClient, lichess), isTrue);
      expect(pool.currentClient.route.path, '/lobby/socket/v5');
      expect(lichess.isFailing.value, isFalse);
    });
  });
}
