import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_database_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_friends_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_leaderboard_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lessons_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_notifications_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_saved_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_tournaments_screen.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/database/xiangqi_master_game_test.dart' as master;
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' as auth;
import '../../test_provider_scope.dart';
import 'xiangqi_chat_screen_test.dart' as chat;
import 'xiangqi_desktop_regression_test.dart' show RecordingSound;
import 'xiangqi_notifications_screen_test.dart' as notifications;
import 'xiangqi_online_game_screen_test.dart' as online;
import 'xiangqi_review_screen_test.dart' as review;

Future<void> settleDesktop(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 1600));
  }
}

Future<void> pumpDesktopPage(
  WidgetTester tester,
  Widget screen,
  MockClient client, {
  SoundService? sound,
}) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final socket = XiangqiSocketClient(
    channelFactory: factory,
    getToken: () async => fx.xiangqiTestToken(fx.xiangqiTestViewerId),
  );
  addTearDown(socket.dispose);
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      surfaceSize: const Size(1280, 720),
      home: screen,
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          auth.FakeXiangqiAuthStorage(auth.signedInSession),
        ),
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((ref) {
          ref.onDispose(socket.dispose);
          return socket;
        }),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => client),
        ),
        if (sound != null) soundServiceProvider: soundServiceProvider.overrideWithValue(sound),
      },
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
  if (factory.channels.isNotEmpty && factory.channel.sentConnect) {
    factory.channel.fromServer(fx.openFrame);
    factory.channel.fromServer(fx.connectAckFrame);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    factory.channel.fromServer(notifications.notificationsFrame([]));
  }
  await settleDesktop(tester);
}

Finder toolbarRefresh() =>
    find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.refresh));

void main() {
  TestLichessBinding.ensureInitialized();

  void testDesktop(String name, WidgetTesterCallback callback) =>
      testWidgets(name, callback, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  const pages = <(String, Widget)>[
    ('lessons', XiangqiLessonsScreen()),
    ('topic', XiangqiTopicScreen(topicId: 'TopicA')),
    ('chapters', XiangqiLessonScreen(lessonId: 'LessonA', lessonTitle: 'A lesson')),
    ('database', XiangqiDatabaseScreen()),
    ('master player', XiangqiMasterPlayerScreen(playerId: 1, playerName: 'A Player')),
    ('master game', XiangqiMasterGameScreen(slug: 'a-vs-b')),
    ('tournaments', XiangqiTournamentsScreen()),
    ('tournament', XiangqiTournamentScreen(id: 'TournamentA', name: 'A tournament')),
    ('leaderboard', XiangqiLeaderboardScreen()),
    ('profile', XiangqiProfileScreen(username: 'Alice')),
    ('friends', XiangqiFriendsScreen()),
    ('saved', XiangqiSavedScreen()),
    ('notifications', XiangqiNotificationsScreen()),
    ('chat rooms', XiangqiChatScreen()),
  ];
  for (final (name, screen) in pages) {
    testDesktop('$name has an explicit desktop toolbar refresh even when loading fails', (
      tester,
    ) async {
      await pumpDesktopPage(tester, screen, MockClient((_) async => http.Response('', 503)));
      expect(toolbarRefresh(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testDesktop('database refresh retains its search, page and loaded data after a 503', (
    tester,
  ) async {
    final requests = <Uri>[];
    var fail = false;
    await pumpDesktopPage(
      tester,
      const XiangqiDatabaseScreen(),
      MockClient((request) async {
        requests.add(request.url);
        if (fail) return http.Response('unavailable', 503);
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        return http.Response(jsonEncode(master.page([master.player()], nextPage: page + 1)), 200);
      }),
    );
    await tester.enterText(find.byType(TextField), 'Opening');
    await settleDesktop(tester);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await settleDesktop(tester);
    expect(requests.last.queryParameters['q'], 'Opening');
    expect(requests.last.queryParameters['page'], '2');
    final before = requests.length;
    fail = true;
    await tester.tap(toolbarRefresh());
    await settleDesktop(tester);
    expect(requests, hasLength(before + 1));
    expect(requests.last.queryParameters['q'], 'Opening');
    expect(requests.last.queryParameters['page'], '2');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Opening');
    expect(find.text('A Player'), findsOneWidget);
    expect(toolbarRefresh(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testDesktop('online backward navigation sounds the target move, not the undone capture', (
    tester,
  ) async {
    final sound = RecordingSound();
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestSpectatorId),
      sound: sound,
    );
    await online.receive(
      tester,
      factory,
      fx.xiangqiEventFrame('game.get.success', {
        ...fx.xiangqiSnapshotPayload(),
        'move_history': [
          'h3e3 600/120 600/120 1',
          'h10g8 600/120 600/120 1',
          'e3e7 600/120 600/120 1',
        ],
      }),
    );
    sound.calls.clear();
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pump();
    expect(sound.calls, [Sound.move]);
  });

  testDesktop('a resync snapshot cancels delayed feedback from the previous incremental frame', (
    tester,
  ) async {
    final sound = RecordingSound();
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestSpectatorId),
      sound: sound,
      pieceAnimation: true,
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
    sound.calls.clear();
    await online.receive(tester, factory, fx.xiangqiMoveFrame(1));
    expect(sound.calls, isEmpty, reason: 'this case must actually have delayed feedback pending');
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(sound.calls, isEmpty);
  });

  testDesktop('back-to-back move and snapshot frames cannot queue feedback after the snapshot', (
    tester,
  ) async {
    final sound = RecordingSound();
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestSpectatorId),
      sound: sound,
      pieceAnimation: true,
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
    sound.calls.clear();
    factory.channel.fromServer(fx.xiangqiMoveFrame(1));
    factory.channel.fromServer(fx.xiangqiSnapshotFrame(plies: 1));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sound.calls, isEmpty);
  });

  testDesktop('database flip rotates its board without changing the reviewed position', (
    tester,
  ) async {
    await pumpDesktopPage(
      tester,
      const XiangqiMasterGameScreen(slug: 'a-vs-b'),
      MockClient((_) async => http.Response(jsonEncode(master.game()), 200)),
    );
    final before = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position;
    expect(find.byIcon(CupertinoIcons.arrow_2_squarepath), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.arrow_2_squarepath));
    await tester.pump();
    final after = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    expect(after.position, before);
    expect(after.orientation, XiangqiSide.black);
  });

  testDesktop('review has a desktop refresh action without dropping the current board', (
    tester,
  ) async {
    final factory = await review.pumpReview(tester);
    await review.loadReview(tester, factory);
    expect(toolbarRefresh(), findsOneWidget);
  });

  testDesktop('room refresh keeps the composer draft while waiting for fresh history', (
    tester,
  ) async {
    final channel = await chat.pumpRoom(tester);
    channel.event('chat.lobby.messages.success', {
      'data': {'items': <Object?>[], 'has_next_page': false},
    });
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    expect(toolbarRefresh(), findsOneWidget);
    await tester.tap(toolbarRefresh());
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Keep this draft');
  });

  testDesktop('signing out of a public room drops the previous account composer draft', (
    tester,
  ) async {
    await chat.pumpRoom(tester);
    await tester.enterText(find.byType(TextField), 'Account A draft');
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiChatRoomScreen)));
    await container.read(xiangqiSessionStoreProvider).write(null);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testDesktop('review navigation does not play a move sound when returning to the root', (
    tester,
  ) async {
    final sound = RecordingSound();
    final factory = await review.pumpReview(tester, sound: sound);
    await review.loadReview(tester, factory);
    final list = tester.widget<MoveList>(find.byType(MoveList));
    list.onSelectMove!(1);
    await tester.pump();
    sound.calls.clear();
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pump();
    expect(sound.calls, isEmpty);
  });

  testDesktop('database history uses the same held controls and sounds the target move', (
    tester,
  ) async {
    final sound = RecordingSound();
    await pumpDesktopPage(
      tester,
      const XiangqiMasterGameScreen(slug: 'a-vs-b'),
      MockClient(
        (_) async => http.Response(jsonEncode(master.game(moves: ['h2e2', 'h9g7', 'e2e6'])), 200),
      ),
      sound: sound,
    );
    tester.widget<MoveList>(find.byType(MoveList)).onSelectMove!(3);
    await tester.pump();
    sound.calls.clear();
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pump();
    expect(sound.calls, [Sound.move]);
    expect(find.byType(HistoryNavigationButton), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
