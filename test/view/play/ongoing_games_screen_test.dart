// Tests for the merged ongoing-games list.
//
// The list is the one screen where the two backends meet, so what is under test is that they meet in
// one list rather than two: that a chess row and a xiangqi row are both drawn, from one provider,
// in the merge's own order, and that each row goes to its own game when tapped. The chess side
// comes off the HTTP mock like every other server-backed test; the xiangqi side is a plain
// [FutureProvider] with no network under it, so it is overridden directly — see AGENTS.md on when a
// direct override is the right thing.
//
// The xiangqi source is empty in this wave, so the game overridden in here is a made-up one: there
// is nothing real to fetch yet.

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_open_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/view/play/ongoing_games_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_ongoing_game_preview.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';

import '../../binding.dart';
import '../../mock_server_responses.dart';
import '../../model/auth/fake_auth_storage.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The xiangqi game the merged list is given, and the id its row opens.
const xiangqiOngoingGameId = 'Zq3nB7wR';

/// A game on xiangqi.com, sitting in the merged list beside the lichess one.
///
/// The position is the starting one, because this test is about the list and not the game: what a
/// row has to draw is a board, a name and a clock, and the initial position is the only FEN here
/// that does not have to be read to be believed.
const xiangqiOngoingGame = XiangqiOpenGame(
  id: xiangqiOngoingGameId,
  isRated: true,
  mySide: XiangqiSide.red,
  gameTimeSeconds: 300,
  incrementSeconds: 3,
  opponent: LightUser(id: UserId('zq-opponent'), name: 'XiangqiOpponent'),
  opponentRating: 1500,
  isMyTurn: true,
  movesCount: 0,
  fen: kXiangqiInitialFen,
  redSecondsLeft: 300,
  blackSecondsLeft: 300,
);

/// [OngoingGamesScreen] over a lichess game from the HTTP mock and [xiangqiOngoingGame].
///
/// The xiangqi socket and its storage are wired to the fixture's fakes as well, so that the game
/// screen a row opens has something to talk to rather than a real connection.
Future<void> pumpScreen(WidgetTester tester) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final client = XiangqiSocketClient(
    channelFactory: factory,
    getToken: () async => fx.xiangqiTestToken(fx.xiangqiTestViewerId),
  );
  addTearDown(client.dispose);

  final mockClient = MockClient((request) {
    if (request.url.path == '/api/account/playing') {
      return mockResponse(mockAccountOngoingGamesResponse(), 200);
    }
    return mockResponse('', 200);
  });

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const OngoingGamesScreen(),
      authUser: fakeAuthUser,
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => mockClient),
        ),
        xiangqiOngoingGamesSourceProvider: xiangqiOngoingGamesSourceProvider.overrideWith(
          (ref) => const IListConst([xiangqiOngoingGame]),
        ),
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((Ref ref) {
          ref.onDispose(client.dispose);
          return client;
        }),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          fx.FakeXiangqiAuthStorage(
            fx.xiangqiTestSession(fx.xiangqiTestToken(fx.xiangqiTestViewerId)),
          ),
        ),
      },
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('OngoingGamesScreen merged list', () {
    testWidgets('draws both backends rows from one list, chess first as the merge orders them', (
      tester,
    ) async {
      await pumpScreen(tester);

      // Both rows exist: neither backend's games are dropped any more.
      expect(find.byType(OngoingGamePreview), findsOneWidget);
      expect(find.byType(XiangqiOngoingGamePreview), findsOneWidget);

      // And the chess row is the upper one, because the merge appends the xiangqi source's rows
      // after the lichess ones and the list renders its own order rather than re-sorting it.
      final chessRow = tester.getTopLeft(find.byType(OngoingGamePreview)).dy;
      final xiangqiRow = tester.getTopLeft(find.byType(XiangqiOngoingGamePreview)).dy;
      expect(chessRow, lessThan(xiangqiRow));

      // The title counts the merged list, both backends' games in one number.
      expect(find.text('2 games in play'), findsOneWidget);
    });

    testWidgets('tapping the xiangqi row opens the game on xiangqi.com', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(XiangqiOnlineGameScreen), findsNothing);

      await tester.tap(find.byType(XiangqiOngoingGamePreview));
      // The push is one frame, and the screen it pushes builds on the next: never `pumpAndSettle`
      // here, because the game screen counts its clocks with a periodic timer.
      await tester.pump();
      await tester.pump();

      expect(find.byType(XiangqiOnlineGameScreen), findsOneWidget);
      expect(
        tester.widget<XiangqiOnlineGameScreen>(find.byType(XiangqiOnlineGameScreen)).gameId,
        xiangqiOngoingGameId,
      );
    });
  });
}
