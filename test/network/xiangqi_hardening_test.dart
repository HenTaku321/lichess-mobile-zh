import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/socket.dart' show webSocketChannelFactoryProvider;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

import '../model/xiangqi/online/xiangqi_online_game_controller_test.dart' as harness;
import '../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../test_container.dart';
import 'xiangqi_http_test.dart' as ht;

void main() {
  test('an active consumer reconnects after logout followed by a new login', () async {
    final identities = StreamController<Object?>.broadcast(sync: true);
    addTearDown(identities.close);
    final factory = fx.FakeXiangqiChannelFactory();
    final socket = XiangqiSocketClient(
      channelFactory: factory,
      getToken: () async => 'token',
      sessionChanges: identities.stream,
    );
    addTearDown(socket.dispose);
    final first = socket.connect();
    await pumpEventQueue();
    factory.channels.last.fromServer(fx.openFrame);
    factory.channels.last.fromServer(fx.connectAckFrame);
    await first;
    identities.add(null);
    await pumpEventQueue();
    expect(socket.isConnected, isFalse);
    expect(factory.channels, hasLength(1), reason: 'logout must not create a guest connection');
    identities.add('account-B');
    await pumpEventQueue();
    expect(factory.channels, hasLength(2));
    factory.channels.last.fromServer(fx.openFrame);
    factory.channels.last.fromServer(fx.connectAckFrame);
    await pumpEventQueue();
    expect(socket.isConnected, isTrue);
    socket.close();
    identities.add('account-C');
    await pumpEventQueue();
    expect(factory.channels, hasLength(2), reason: 'manual close ends the consumer lifetime');
  });

  test('closing during a handshake completes the pending attempt', () async {
    final factory = fx.FakeXiangqiChannelFactory();
    final socket = XiangqiSocketClient(channelFactory: factory, getToken: () async => 'token');
    addTearDown(socket.dispose);
    final pending = socket.connect();
    final expectation = expectLater(pending, throwsA(isA<XiangqiSocketException>()));
    await pumpEventQueue();
    socket.close();
    await expectation;
    expect(socket.status, XiangqiConnectionStatus.closed);
  });

  test('a refresh completed after logout cannot write the old identity back', () {
    fakeAsync((async) {
      final storage = ht.FakeXiangqiAuthStorage(ht.signedInSession);
      final sessions = XiangqiSessionStore(storage);
      final refresh = Completer<http.Response>();
      final client = XiangqiClient(
        inner: MockClient(
          (request) async => request.url.path.endsWith('/jwt/refresh')
              ? await refresh.future
              : http.Response('', 401),
        ),
        storage: storage,
        sessionStore: sessions,
        uiEventBus: UiEventBus(),
      );
      unawaited(client.get(xiangqiUri('private')));
      async.elapse(const Duration(seconds: 2));
      unawaited(sessions.write(null));
      async.flushMicrotasks();
      refresh.complete(http.Response('{"access_token":"late-token"}', 200));
      async.elapse(const Duration(seconds: 2));
      expect(storage.session, isNull);
      expect(sessions.current, isNull);
      client.close();
      sessions.dispose();
    });
  });

  test('business 401 with explicit authorization does not refresh or erase the account', () {
    fakeAsync((async) {
      final storage = ht.FakeXiangqiAuthStorage(ht.signedInSession);
      var calls = 0;
      final client = XiangqiClient(
        inner: MockClient((_) async {
          calls++;
          return http.Response('wrong password', 401);
        }),
        storage: storage,
        uiEventBus: UiEventBus(),
      );
      unawaited(
        client.post(
          xiangqiUri('users/account/delete/'),
          headers: {'Authorization': 'Bearer access-old'},
        ),
      );
      async.elapse(const Duration(seconds: 2));
      expect(calls, 1);
      expect(storage.session, ht.signedInSession);
      client.close();
    });
  });

  test('replay cursor does not change where live moves are applied', () async {
    final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    final feedback = <Object>[];
    final subscription = game.controller.confirmedMoves.listen(feedback.add);
    addTearDown(subscription.cancel);
    await game.send(fx.xiangqiSnapshotFrame(plies: 2));
    expect(feedback, isEmpty);
    game.controller.goTo(0);
    await game.send(fx.xiangqiMoveFrame(3));
    expect(game.state.moves.length, 3);
    expect(game.state.gamePosition.toFen(), fx.xiangqiTestPositions[3].toFen());
    expect(feedback, hasLength(1));
    await game.send(fx.xiangqiMoveFrame(3));
    expect(feedback, hasLength(1));
  });
  test('late refresh cannot resurrect a signed-out account', () async {
    final storage = ht.FakeXiangqiAuthStorage(ht.signedInSession);
    final store = XiangqiSessionStore(storage);
    addTearDown(store.dispose);
    await store.ready;
    final oldGeneration = store.generation;
    await store.write(null);
    expect(await store.write(ht.signedInSession, expectedGeneration: oldGeneration), isFalse);
    expect(await store.read(), isNull);
  });

  test('refreshing tokens for the same account does not change the account generation', () async {
    final storage = ht.FakeXiangqiAuthStorage(ht.signedInSession);
    final store = XiangqiSessionStore(storage);
    addTearDown(store.dispose);
    await store.ready;
    final before = store.accountGeneration;
    await store.write(ht.signedInSession.copyWith(accessToken: 'rotated-token'));
    expect(store.accountGeneration, before);
    await store.write(null);
    expect(store.accountGeneration, before + 1);
  });

  test('rotating a restored account token preserves the inbox repository', () async {
    final storage = ht.FakeXiangqiAuthStorage(ht.signedInSession);
    final container = await makeContainer(
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(storage),
        webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
          fx.FakeXiangqiChannelFactory(),
        ),
      },
    );
    final listener = container.listen(xiangqiInboxRepositoryProvider, (_, _) {});
    addTearDown(listener.close);
    final store = container.read(xiangqiSessionStoreProvider);
    await store.ready;
    await pumpEventQueue();
    final before = container.read(xiangqiInboxRepositoryProvider);
    await store.write(
      ht.signedInSession.copyWith(accessToken: 'refreshed', refreshToken: 'rotated'),
    );
    await pumpEventQueue();
    expect(container.read(xiangqiInboxRepositoryProvider), same(before));
  });

  test('different game scopes own distinct socket transports', () async {
    final factory = fx.FakeXiangqiChannelFactory();
    final base = XiangqiSocketClient(channelFactory: factory, getToken: () async => 'token');
    final a = base.fork();
    final b = base.fork();
    addTearDown(base.dispose);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final pending = [a.connect(), b.connect()];
    await pumpEventQueue();
    expect(factory.channels, hasLength(2));
    for (final c in factory.channels) {
      c.fromServer(fx.openFrame);
      c.fromServer(fx.connectAckFrame);
    }
    await Future.wait(pending);
    a.close();
    expect(b.isConnected, isTrue);
  });

  test('refresh 503 preserves the session', () {
    fakeAsync((async) {
      final storage = ht.FakeXiangqiAuthStorage(ht.signedInSession);
      final requests = <String>[];
      final client = XiangqiClient(
        inner: MockClient((r) async {
          requests.add(r.url.path);
          return http.Response('', r.url.path.endsWith('/jwt/refresh') ? 503 : 401);
        }),
        storage: storage,
        uiEventBus: UiEventBus(),
      );
      var done = false;
      client.get(xiangqiUri('private')).then((_) => done = true);
      async.elapse(const Duration(seconds: 10));
      expect(done, isTrue, reason: 'requests=$requests session=${storage.session?.accessToken}');
      expect(storage.session, isNotNull);
      client.close();
    });
  });

  test('snapshot for another game is ignored', () async {
    final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    final other = fx.xiangqiSnapshotPayload(plies: 2)..['id'] = 'game-B';
    await game.send(fx.xiangqiEventFrame('game.get.success', {'data': other}));
    expect(game.state.isLoaded, isFalse);
  });

  test('each resync follows its own archived redirect', () async {
    final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    game.channel.ackOverrides['g_v2.get'] = fx.xiangqiRedirectAck;
    await game.controller.resync();
    await game.controller.resync();
    expect(
      game.channel.sent
          .whereType<String>()
          .where((s) => s.contains('["game.archived.get",'))
          .length,
      2,
    );
  });

  test('snapshot resync keeps a replay cursor while refreshing the live position', () async {
    final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame(plies: 2));
    game.controller.goTo(1);
    final displayed = game.state.position;
    await game.controller.resync();
    expect(game.state.isConnected, isFalse);
    await game.send(fx.xiangqiSnapshotFrame(plies: 4));

    expect(game.state.isConnected, isTrue);
    expect(game.state.viewCursor, 1);
    expect(game.state.position, displayed);
    expect(game.state.gamePosition, fx.xiangqiTestPositions[4]);
    expect(game.state.moves, hasLength(4));
    expect(game.state.isMyTurn, isFalse, reason: 'replaying must not grant move permission');
    expect(game.channel.hasSentEvent('g_v2.move'), isFalse);
  });

  test('online snapshots replay from their explicit black-first initial FEN', () async {
    final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    final initialFen = kXiangqiInitialFen.replaceFirst(' w ', ' b ');
    final snapshot = fx.xiangqiSnapshotPayload()
      ..['initial_fen'] = initialFen
      ..['move_history'] = ['h10g8 600/120 600/120 1'];
    await game.send(fx.xiangqiEventFrame('game.get.success', snapshot));
    expect(game.state.error, isNull);
    expect(game.state.isLoaded, isTrue);
    expect(game.state.positions.first.toFen(), initialFen);
    expect(game.state.moves, hasLength(1));
    expect(game.state.turn, XiangqiSide.red);
  });

  test('an explicitly malformed initial FEN is not silently replaced by the opening', () async {
    final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    final snapshot = fx.xiangqiSnapshotPayload()..['initial_fen'] = 'not a FEN';
    await game.send(fx.xiangqiEventFrame('game.get.success', snapshot));
    expect(game.state.isLoaded, isFalse);
    expect(game.state.error, isNotNull);
  });

  test(
    'a shortened resync follows the authoritative live end when the old cursor is gone',
    () async {
      final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame(plies: 4));
      game.controller.goTo(3);
      await game.controller.resync();
      await game.send(fx.xiangqiSnapshotFrame(plies: 2));
      expect(game.state.viewCursor, 2);
      expect(game.state.isAtLivePosition, isTrue);
      expect(game.state.position, fx.xiangqiTestPositions[2]);
    },
  );

  test('resync advances the live board when the user was not replaying', () async {
    final game = await harness.makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame(plies: 2));
    await game.controller.resync();
    await game.send(fx.xiangqiSnapshotFrame(plies: 4));
    expect(game.state.viewCursor, 4);
    expect(game.state.isAtLivePosition, isTrue);
    expect(game.state.position, fx.xiangqiTestPositions[4]);
  });

  test('signout closes the account socket', () async {
    final storage = ht.FakeXiangqiAuthStorage(ht.signedInSession);
    final factory = fx.FakeXiangqiChannelFactory();
    final container = ProviderContainer(
      overrides: [
        xiangqiAuthStorageProvider.overrideWithValue(storage),
        webSocketChannelFactoryProvider.overrideWithValue(factory),
      ],
    );
    addTearDown(container.dispose);
    final socket = container.read(xiangqiSocketProvider);
    final connecting = socket.connect();
    await pumpEventQueue();
    factory.channels.last.fromServer(fx.openFrame);
    factory.channels.last.fromServer(fx.connectAckFrame);
    await connecting;
    await container.read(xiangqiAuthControllerProvider.notifier).signOut();
    await pumpEventQueue();
    expect(socket.isConnected, isFalse);
  });

  test('a stalled response body has a deadline', () {
    fakeAsync((async) {
      final body = StreamController<List<int>>();
      final client = XiangqiClient(
        inner: MockClient.streaming((r, _) async => http.StreamedResponse(body.stream, 200)),
        storage: ht.FakeXiangqiAuthStorage(),
        uiEventBus: UiEventBus(),
      );
      var done = false;
      client.get(xiangqiUri('body')).then((_) => done = true, onError: (Object _) => done = true);
      async.elapse(const Duration(minutes: 2));
      expect(done, isTrue);
      unawaited(body.close());
      client.close();
    });
  });
}
