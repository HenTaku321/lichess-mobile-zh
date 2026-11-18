import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/view/home/home_tab_screen.dart';
import 'package:lichess_mobile/src/view/play/play_menu.dart';
import 'package:lichess_mobile/src/view/watch/watch_tab_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_ongoing_game_preview.dart';
import 'package:lichess_mobile/src/widgets/server_outage_display.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/account/ongoing_games_notifier_test.dart' as fixtures;
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  for (final width in [390.0, 1280.0]) {
    testWidgets('home at $width keeps the xiangqi account and game during a lichess outage', (
      tester,
    ) async {
      var requests = 0;
      final client = MockClient((request) {
        if (request.url.path == '/api/v2/games/my-games') {
          requests++;
          return mockResponse(jsonEncode([fixtures.xiangqiListEntry()]), 200);
        }
        return mockResponse('', request.url.host == lichessUri('/').host ? 503 : 200);
      });
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const HomeTabScreen(),
          surfaceSize: Size(width, 1400),
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (ref) => FakeHttpClientFactory(() => client),
            ),
            xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
              (ref) => fixtures.FakeXiangqiAuthStorage(fixtures.xiangqiSession),
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, greaterThan(0));
      expect(find.byType(ServerOutageDisplay), findsOneWidget);
      expect(find.text('About Lichess...'), findsNothing);
      final row = width < 600
          ? find.byType(XiangqiOngoingGameCarouselItem)
          : find.byType(XiangqiOngoingGamePreview);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.textContaining('jackson65', findRichText: true)),
        findsOneWidget,
      );
    });
  }

  testWidgets('Watch opens a live xiangqi board during lichess maintenance', (tester) async {
    final token = fx.xiangqiTestToken(fx.xiangqiTestSpectatorId);
    final channels = fx.FakeXiangqiChannelFactory();
    final client = MockClient((request) {
      if (request.url.path == '/api/v2/games/active') {
        return mockResponse(jsonEncode([fixtures.xiangqiListEntry(id: fx.xiangqiTestGameId)]), 200);
      }
      return mockResponse('', request.url.host == lichessUri('/').host ? 503 : 200);
    });
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const WatchTabScreen(),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(() => client),
          ),
          xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
            fx.FakeXiangqiAuthStorage(fx.xiangqiTestSession(token)),
          ),
          xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((ref) {
            final socket = XiangqiSocketClient(
              channelFactory: channels,
              getToken: () async => token,
            );
            ref.onDispose(socket.dispose);
            return socket;
          }),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ServerOutageDisplay), findsOneWidget);
    final liveGames = find.text('Live games');
    expect(liveGames, findsOneWidget);
    await tester.tap(liveGames);
    final game = find.textContaining('jackson65');
    await pumpUntil(tester, () => game.evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(game);
    await tester.tap(game);
    await pumpUntil(tester, () => channels.channels.isNotEmpty);
    channels.channel.fromServer(fx.openFrame);
    channels.channel.fromServer(fx.connectAckFrame);
    await tester.pump();
    await tester.pump();
    channels.channel.fromServer(fx.xiangqiSnapshotFrame());
    final board = find.byType(XiangqiBoard);
    await pumpUntil(tester, () => board.evaluate().isNotEmpty);
    expect(tester.widget<XiangqiBoard>(board).onTapSquare, isNull);
    channels.channel.fromServer(fx.xiangqiMoveFrame(1));
    await pumpUntil(
      tester,
      () => tester.widget<XiangqiBoard>(board).position == fx.xiangqiTestPositions[1],
    );
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    expect(game, findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(liveGames, findsOneWidget);
  });

  testWidgets('the shared tournament entry stays available while only lichess is down', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: SingleChildScrollView(child: PlayMenu())),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(
              () => MockClient(
                (request) => mockResponse('', request.url.host == lichessUri('/').host ? 503 : 200),
              ),
            ),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    ListTile tile(IconData icon) => tester.widget<ListTile>(
      find.ancestor(of: find.byIcon(icon), matching: find.byType(ListTile)),
    );
    expect(tile(Icons.person).enabled, isFalse);
    expect(tile(LichessIcons.tournament_cup).enabled, isTrue);
  });
}
