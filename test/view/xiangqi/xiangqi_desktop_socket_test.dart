import 'dart:async';
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart' show Icons;

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../test_provider_scope.dart';
import 'xiangqi_chat_screen_test.dart' as chat;
import 'xiangqi_desktop_regression_test.dart' show RecordingSound;
import 'xiangqi_online_game_screen_test.dart' as online;

const roomKey = (kind: XiangqiChatKind.lobby, room: '中文');

List<Map<String, dynamic>> requests(fx.FakeXiangqiChannel channel, String event) => [
  for (final frame in channel.sent.whereType<String>())
    if (frame.startsWith('42/xiangqi,') && frame.contains('["$event",'))
      (jsonDecode(frame.substring(frame.indexOf('['))) as List<dynamic>)[1] as Map<String, dynamic>,
];

DesktopRefreshButton refreshButton(WidgetTester tester) =>
    tester.widget<DesktopRefreshButton>(find.byType(DesktopRefreshButton));

Future<({ProviderContainer container, fx.FakeXiangqiChannelFactory factory})> pumpRoom(
  WidgetTester tester,
) async {
  final factory = fx.FakeXiangqiChannelFactory();
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const XiangqiChatRoomScreen(roomKey: roomKey, title: '中文'),
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          fx.FakeXiangqiAuthStorage(
            fx.xiangqiTestSession(
              fx.xiangqiTestToken('account-A'),
              userId: 'account-A',
              isGuest: false,
            ),
          ),
        ),
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((ref) {
          final sessions = ref.read(xiangqiSessionStoreProvider);
          final socket = XiangqiSocketClient(
            channelFactory: factory,
            getToken: () async => (await sessions.read())?.accessToken,
            sessionChanges: sessions.changes
                .map((s) => s == null ? null : (s.userId, s.accessToken))
                .distinct(),
          );
          ref.onDispose(socket.dispose);
          return socket;
        }),
      },
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
  expect(factory.channel.sentConnect, isTrue);
  await online.receive(tester, factory, fx.openFrame);
  await online.receive(tester, factory, fx.connectAckFrame);
  return (
    container: ProviderScope.containerOf(tester.element(find.byType(XiangqiChatRoomScreen))),
    factory: factory,
  );
}

Future<void> history(
  WidgetTester tester,
  fx.FakeXiangqiChannelFactory factory,
  List<Map<String, Object?>> items, {
  bool hasNext = false,
}) => online.receive(
  tester,
  factory,
  fx.xiangqiEventFrame('chat.lobby.messages.success', {
    'data': {'items': items, 'has_next_page': hasNext},
  }),
);

void main() {
  TestLichessBinding.ensureInitialized();
  void testDesktop(String name, WidgetTesterCallback callback) =>
      testWidgets(name, callback, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testDesktop('restoring a saved room account opens only one transport', (tester) async {
    final (:factory, :container) = await pumpRoom(tester);
    expect(factory.channels, hasLength(1));
    await history(tester, factory, [chat.message(id: 1, text: 'restored room')]);
    expect(container.read(xiangqiChatControllerProvider(roomKey)).isConnected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testDesktop('online mouse refresh waits for the matching snapshot and keeps replay and flip', (
    tester,
  ) async {
    final sound = RecordingSound();
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
      sound: sound,
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 4));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(XiangqiOnlineGameScreen)),
    );
    final provider = xiangqiOnlineGameControllerProvider(fx.xiangqiTestGameId);
    container.read(provider.notifier).goTo(2);
    await tester.tap(online.barButton(Icons.menu));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Flip board'));
    await tester.pump(const Duration(milliseconds: 300));
    final position = online.board(tester).position;
    final orientation = online.board(tester).orientation;
    final before = requests(factory.channel, 'g_v2.get').length;

    expect(find.byType(DesktopRefreshButton), findsOneWidget);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    await tester.pump(); // The separate request acknowledgement has already arrived.
    expect(refreshButton(tester).busy, isTrue);
    expect(online.board(tester).position, position);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    expect(requests(factory.channel, 'g_v2.get'), hasLength(before + 1));

    final foreign = fx.xiangqiSnapshotPayload(plies: 4)..['id'] = 'another-game';
    await online.receive(tester, factory, fx.xiangqiEventFrame('game.get.success', foreign));
    expect(refreshButton(tester).busy, isTrue);
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 5));
    expect(refreshButton(tester).busy, isFalse);
    expect(online.board(tester).position, position);
    expect(online.board(tester).orientation, orientation);
    expect(container.read(provider).requireValue.moves, hasLength(5));
    expect(sound.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testDesktop('online resync does not send another request while a snapshot is outstanding', (
    tester,
  ) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(XiangqiOnlineGameScreen)),
    );
    final controller = container.read(
      xiangqiOnlineGameControllerProvider(fx.xiangqiTestGameId).notifier,
    );
    final before = requests(factory.channel, 'g_v2.get').length;
    unawaited(controller.resync());
    await tester.pump();
    await tester.pump();
    unawaited(controller.resync());
    await tester.pump();
    await tester.pump();
    expect(requests(factory.channel, 'g_v2.get'), hasLength(before + 1));
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
  });

  testDesktop('online mouse refresh joins an initial snapshot request instead of duplicating it', (
    tester,
  ) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
    );
    final before = requests(factory.channel, 'g_v2.get').length;
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    await tester.pump();
    expect(refreshButton(tester).busy, isTrue);
    expect(requests(factory.channel, 'g_v2.get'), hasLength(before));
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
    expect(refreshButton(tester).busy, isFalse);
    expect(tester.takeException(), isNull);
  });

  testDesktop('a late old acknowledgement cannot settle or fail the next online refresh', (
    tester,
  ) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(XiangqiOnlineGameScreen)),
    );
    final provider = xiangqiOnlineGameControllerProvider(fx.xiangqiTestGameId);
    factory.channel.autoAck = false;
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 2));
    expect(refreshButton(tester).busy, isFalse);
    factory.channel.autoAck = true;
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(refreshButton(tester).busy, isTrue);
    expect(container.read(provider).requireValue.error, isNull);
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 4));
    expect(refreshButton(tester).busy, isFalse);
    expect(container.read(provider).requireValue.isConnected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testDesktop('a valid online snapshot survives its missing acknowledgement timeout', (
    tester,
  ) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(XiangqiOnlineGameScreen)),
    );
    final provider = xiangqiOnlineGameControllerProvider(fx.xiangqiTestGameId);
    factory.channel.autoAck = false;
    unawaited(container.read(provider.notifier).resync());
    await tester.pump();
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 2));
    expect(container.read(provider).requireValue.isConnected, isTrue);
    await tester.pump(const Duration(seconds: 11));
    expect(container.read(provider).requireValue.error, isNull);
    expect(container.read(provider).requireValue.isConnected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testDesktop('online mouse retry reconnects without throwing away the loaded board', (
    tester,
  ) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 4));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(XiangqiOnlineGameScreen)),
    );
    container.read(xiangqiOnlineGameControllerProvider(fx.xiangqiTestGameId).notifier).goTo(2);
    await tester.pump();
    final position = online.board(tester).position;
    factory.channel.closeFromServer();
    await tester.pump();
    await tester.pump();
    expect(find.byType(DesktopRefreshButton), findsOneWidget);
    await tester.tap(find.byType(DesktopRefreshButton));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(factory.channels, hasLength(2));
    expect(online.board(tester).position, position);
    await online.receive(tester, factory, fx.openFrame);
    await online.receive(tester, factory, fx.connectAckFrame);
    expect(requests(factory.channel, 'g_v2.get'), hasLength(1));
    expect(refreshButton(tester).busy, isTrue);
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 5));
    expect(refreshButton(tester).busy, isFalse);
    expect(online.board(tester).position, position);
    expect(tester.takeException(), isNull);
  });

  testDesktop('online snapshot timeout releases mouse refresh for another attempt', (tester) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 2));
    expect(find.byType(DesktopRefreshButton), findsOneWidget);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    expect(refreshButton(tester).busy, isFalse);
    expect(online.board(tester).position, fx.xiangqiTestPositions[2]);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 4));
    expect(refreshButton(tester).busy, isFalse);
    expect(online.board(tester).position, fx.xiangqiTestPositions[4]);
    expect(tester.takeException(), isNull);
  });

  testDesktop('room refresh merges latest messages and preserves the older pagination cursor', (
    tester,
  ) async {
    final (:container, :factory) = await pumpRoom(tester);
    final provider = xiangqiChatControllerProvider(roomKey);
    final controller = container.read(provider.notifier);
    await history(tester, factory, [chat.message(id: 3, text: 'third')], hasNext: true);
    unawaited(controller.loadMore());
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    await history(tester, factory, [chat.message(id: 2, text: 'second')], hasNext: true);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    await history(tester, factory, [
      chat.message(id: 4, text: 'fourth'),
      chat.message(id: 3, text: 'third updated'),
    ], hasNext: true);
    expect(container.read(provider).messages.map((m) => m.id), [2, 3, 4]);
    expect(container.read(provider).messages.map((m) => m.message), [
      'second',
      'third updated',
      'fourth',
    ]);
    unawaited(controller.loadMore());
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    expect(requests(factory.channel, 'chat_v2.messages').last['page'], 3);
    await history(tester, factory, [chat.message(id: 1, text: 'first')]);
    expect(container.read(provider).messages.map((m) => m.id), [1, 2, 3, 4]);
    expect(tester.takeException(), isNull);
  });

  testDesktop('overlapping room history is deduplicated without reopening exhausted older pages', (
    tester,
  ) async {
    final (:container, :factory) = await pumpRoom(tester);
    final provider = xiangqiChatControllerProvider(roomKey);
    final controller = container.read(provider.notifier);
    await history(tester, factory, [chat.message(id: 3, text: 'third')], hasNext: true);
    unawaited(controller.loadMore());
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    await history(tester, factory, [
      chat.message(id: 3, text: 'third'),
      chat.message(id: 2, text: 'second'),
    ]);
    expect(container.read(provider).messages.map((m) => m.id), [2, 3]);
    expect(container.read(provider).hasMore, isFalse);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    await history(tester, factory, [
      chat.message(id: 4, text: 'fourth'),
      chat.message(id: 3, text: 'third'),
    ], hasNext: true);
    expect(container.read(provider).messages.map((m) => m.id), [2, 3, 4]);
    expect(container.read(provider).hasMore, isFalse);
    expect(tester.takeException(), isNull);
  });

  testDesktop('changing room account clears retained history and restarts at page one', (
    tester,
  ) async {
    final (:container, :factory) = await pumpRoom(tester);
    final provider = xiangqiChatControllerProvider(roomKey);
    await history(tester, factory, [chat.message(id: 3, text: 'account A history')], hasNext: true);
    final oldChannel = factory.channel;
    final session = fx
        .xiangqiTestSession(fx.xiangqiTestToken('account-B'))
        .copyWith(userId: 'account-B', isGuest: false);
    await container.read(xiangqiSessionStoreProvider).write(session);
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(container.read(provider).messages, isEmpty);
    expect(oldChannel.closed, isTrue);
    await online.receive(tester, factory, fx.openFrame);
    await online.receive(tester, factory, fx.connectAckFrame);
    expect(requests(factory.channel, 'chat_v2.messages').single['page'], 1);
    oldChannel.fromServer(
      fx.xiangqiEventFrame(
        'chat.lobby.messages.success',
        chat.page([chat.message(id: 1, text: 'late A history')]),
      ),
    );
    await history(tester, factory, [chat.message(id: 4, text: 'account B history')]);
    expect(container.read(provider).messages.map((m) => m.message), ['account B history']);
    expect(tester.takeException(), isNull);
  });

  testDesktop('room refresh keeps broadcasts arriving after the requested history page', (
    tester,
  ) async {
    final (:container, :factory) = await pumpRoom(tester);
    final provider = xiangqiChatControllerProvider(roomKey);
    await history(tester, factory, [chat.message(id: 3, text: 'third')]);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    await online.receive(
      tester,
      factory,
      fx.xiangqiEventFrame('chat.new.lobby.message.success', chat.message(id: 5, text: 'fifth')),
    );
    await online.receive(
      tester,
      factory,
      fx.xiangqiEventFrame('chat.new.lobby.message.success', {
        ...chat.message(id: 6, text: 'unnumbered live message'),
        'id': null,
      }),
    );
    await history(tester, factory, [
      chat.message(id: 4, text: 'fourth'),
      chat.message(id: 3, text: 'third'),
    ]);
    expect(container.read(provider).messages.map((m) => m.id), [3, 4, 5, null]);
    expect(container.read(provider).messages.last.message, 'unnumbered live message');
    expect(tester.takeException(), isNull);
  });

  testDesktop('a refreshed room page without overlap fills the gap before the retained history', (
    tester,
  ) async {
    final (:container, :factory) = await pumpRoom(tester);
    final provider = xiangqiChatControllerProvider(roomKey);
    final controller = container.read(provider.notifier);
    await history(tester, factory, [
      chat.message(id: 4, text: 'fourth'),
      chat.message(id: 3, text: 'third'),
    ], hasNext: true);
    unawaited(controller.loadMore());
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    await history(tester, factory, [
      chat.message(id: 2, text: 'second'),
      chat.message(id: 1, text: 'first'),
    ]);
    expect(container.read(provider).hasMore, isFalse);

    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    await history(tester, factory, [
      chat.message(id: 8, text: 'eighth'),
      chat.message(id: 7, text: 'seventh'),
    ], hasNext: true);
    expect(container.read(provider).messages.map((m) => m.id), [1, 2, 3, 4, 7, 8]);
    expect(
      container.read(provider).hasMore,
      isTrue,
      reason: 'the new page has not reached the old history yet',
    );
    unawaited(controller.loadMore());
    await tester.pump(kXiangqiChatRequestSpacing);
    await tester.pump();
    expect(requests(factory.channel, 'chat_v2.messages').last['page'], 2);
    await history(tester, factory, [
      chat.message(id: 6, text: 'sixth'),
      chat.message(id: 5, text: 'fifth'),
    ], hasNext: true);
    expect(container.read(provider).messages.map((m) => m.id), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(tester.takeException(), isNull);
  });
}
