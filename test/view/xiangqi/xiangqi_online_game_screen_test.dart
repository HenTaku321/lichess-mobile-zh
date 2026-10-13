// Tests for the one screen an online xiangqi game is played on.
//
// One screen for both ways of looking at a game, so what is under test here is the difference
// between the two: a watcher gets the board and no way to touch it and no way to resign, a player
// gets both. The game itself comes off the fixture, which pushes the same frames the controller's
// own tests read — see that file's first comment for what was measured and what was constructed.
//
// Nothing here is a live socket. The transport is the fixture's fake channel, wired in under the
// socket client's own provider, and the token the controller reads is an in-memory storage holding
// one session.

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart' show XiangqiGameEnd;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../test_provider_scope.dart';

/// The board the screen has drawn.
XiangqiBoard board(WidgetTester tester) => tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));

/// The bottom bar button drawn with [icon].
///
/// By icon and not by label, which is the same way the offline screens' tests find them: a bar
/// button's label is a tooltip and a semantics node rather than text on the screen.
Finder barButton(IconData icon) =>
    find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton));

/// The row of the seat [side].
///
/// Found by the seat it was given rather than by where it sits, so that a test says which row it
/// means whatever order the layout happens to build the two in.
XiangqiOnlinePlayerRow playerRow(WidgetTester tester, XiangqiSide side) => tester
    .widgetList<XiangqiOnlinePlayerRow>(find.byType(XiangqiOnlinePlayerRow))
    .singleWhere((row) => row.side == side);

/// Opens [fx.xiangqiTestGameId] as the account behind [token], over a socket whose other end is the
/// fixture's, and hands the factory back so that a test can push frames from the server.
Future<fx.FakeXiangqiChannelFactory> pumpGame(WidgetTester tester, {required String token}) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final client = XiangqiSocketClient(channelFactory: factory, getToken: () async => token);
  addTearDown(client.dispose);

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const XiangqiOnlineGameScreen(gameId: fx.xiangqiTestGameId),
      overrides: {
        // A real client over a fake transport, and not `overrideWithValue`: the client holds a
        // heartbeat timer, and the provider's teardown — which is what disposes it at the end of a
        // test — is the only thing that cancels the timer before the harness looks for pending ones.
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((Ref ref) {
          ref.onDispose(client.dispose);
          return client;
        }),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          fx.FakeXiangqiAuthStorage(fx.xiangqiTestSession(token)),
        ),
      },
    ),
  );

  // The client opens its channel from a chain of microtasks — the token read, the factory call, the
  // connect frame — and a pump is what lets one of them run. Nothing in the chain is a timer, so a
  // few pumps see the whole of it; the loop is here so that a test does not depend on how many.
  for (var pump = 0; pump < 5 && factory.channels.isEmpty; pump++) {
    await tester.pump();
  }
  expect(factory.channels, isNotEmpty, reason: 'the screen is expected to open a socket');

  // The handshake, which is what makes the controller ask for the game.
  factory.channel.fromServer(fx.openFrame);
  factory.channel.fromServer(fx.connectAckFrame);
  await tester.pump();
  await tester.pump();

  return factory;
}

/// Pushes [frame] from the server and draws what it changed.
///
/// Two pumps, because they do two things: the first delivers the frame and flushes the microtasks it
/// sets off, the second draws the state they left behind.
///
/// Never `pumpAndSettle` on this screen: it counts its clocks with a periodic timer, so there is
/// always another frame coming and settling would never finish.
Future<void> receive(
  WidgetTester tester,
  fx.FakeXiangqiChannelFactory factory,
  String frame,
) async {
  factory.channel.fromServer(frame);
  await tester.pump();
  await tester.pump();
}

/// Plays the whole fixture home, one frame at a time.
Future<void> playTheGame(WidgetTester tester, fx.FakeXiangqiChannelFactory factory) async {
  await receive(tester, factory, fx.xiangqiSnapshotFrame());
  for (var ply = 1; ply <= fx.xiangqiTestMoveUcis.length; ply++) {
    await receive(tester, factory, fx.xiangqiMoveFrame(ply));
  }
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiOnlineGameScreen', () {
    testWidgets('a watcher is given the board, and no way to touch it or to resign', (
      tester,
    ) async {
      final factory = await pumpGame(tester, token: fx.xiangqiTestToken(fx.xiangqiTestSpectatorId));

      // Nothing has been read yet, so there is nothing to draw but the loader.
      expect(find.byType(XiangqiBoard), findsNothing);

      await receive(tester, factory, fx.xiangqiSnapshotFrame());

      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(board(tester).position.toFen(), fx.xiangqiTestPositions.first.toFen());
      expect(find.byType(XiangqiOnlinePlayerRow), findsNWidgets(2));

      // The two buttons anybody gets, and not the third: a spectator has no seat to resign.
      expect(barButton(CupertinoIcons.arrow_2_squarepath), findsOneWidget);
      expect(barButton(CupertinoIcons.xmark), findsOneWidget);
      expect(barButton(CupertinoIcons.flag), findsNothing);

      // And the board is theirs to look at rather than to play on: neither a tap nor a drag is
      // wired to anything at all.
      expect(board(tester).onTapSquare, isNull);
      expect(board(tester).onDragMove, isNull);
    });

    testWidgets('a player is given the same board, both seats, and a resign button', (
      tester,
    ) async {
      final factory = await pumpGame(tester, token: fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await receive(tester, factory, fx.xiangqiSnapshotFrame());

      // The snapshot names both seats, and the token's subject is the red one.
      expect(find.text(fx.xiangqiTestRedName), findsOneWidget);
      expect(find.text(fx.xiangqiTestBlackName), findsOneWidget);
      expect(playerRow(tester, XiangqiSide.red).isMe, isTrue);
      expect(playerRow(tester, XiangqiSide.black).isMe, isFalse);

      // Red moves first, so red is the seat that is to move.
      expect(playerRow(tester, XiangqiSide.red).isTurn, isTrue);
      expect(playerRow(tester, XiangqiSide.black).isTurn, isFalse);

      expect(barButton(CupertinoIcons.flag), findsOneWidget);
      expect(board(tester).onTapSquare, isNotNull);
      expect(board(tester).onDragMove, isNotNull);
    });

    testWidgets('the move list fills in as the server sends the moves', (tester) async {
      final factory = await pumpGame(tester, token: fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await receive(tester, factory, fx.xiangqiSnapshotFrame());

      // A snapshot with an empty `move_history` is a game that has not started: no line to show.
      expect(find.byType(InlineMoveItem), findsNothing);

      final notation = xiangqiGameNotation(fx.xiangqiTestPositions, fx.xiangqiTestMoves);
      for (var ply = 1; ply <= fx.xiangqiTestMoveUcis.length; ply++) {
        await receive(tester, factory, fx.xiangqiMoveFrame(ply));

        expect(find.byType(InlineMoveItem), findsNWidgets(ply));
        expect(find.text(notation[ply - 1]), findsOneWidget);
        expect(
          board(tester).position.toFen(),
          fx.xiangqiTestPositions[ply].toFen(),
          reason: 'the board after ply $ply',
        );
      }
    });

    testWidgets('the clocks come off the frames, and only the side to move counts', (tester) async {
      final factory = await pumpGame(tester, token: fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await playTheGame(tester, factory);

      final plies = fx.xiangqiTestMoveUcis.length;
      final redSeconds = fx.xiangqiTestSecondsLeft(XiangqiSide.red, plies);
      final blackSeconds = fx.xiangqiTestSecondsLeft(XiangqiSide.black, plies);

      // Five plies in it is black to move, and black is the seat that counts: red's reading is
      // exactly what the last frame said, because a clock that is not running is not counted down.
      expect(playerRow(tester, XiangqiSide.black).isTurn, isTrue);
      expect(playerRow(tester, XiangqiSide.red).secondsLeft, redSeconds);
      // Black's is the frame's reading less the seconds since the stamp the fixture put on it, which
      // is the seconds this test has taken: bounded rather than pinned, because that is the number
      // the screen is really showing.
      expect(playerRow(tester, XiangqiSide.black).secondsLeft, lessThanOrEqualTo(blackSeconds));
      expect(playerRow(tester, XiangqiSide.black).secondsLeft, greaterThan(blackSeconds - 30));
    });

    testWidgets('the end of the game is announced in a dialog', (tester) async {
      final factory = await pumpGame(tester, token: fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await playTheGame(tester, factory);

      expect(find.byType(XiangqiOnlineResultDialog), findsNothing);

      await receive(tester, factory, fx.xiangqiEndFrame());
      // A dialog is pushed as a route, so it takes one more frame to be built than the state change
      // that asks for it.
      await tester.pump();

      final dialog = tester.widget<XiangqiOnlineResultDialog>(
        find.byType(XiangqiOnlineResultDialog),
      );
      expect(dialog.state.end, XiangqiGameEnd.resign);
      expect(dialog.state.resignedBy, XiangqiSide.black);
      expect(dialog.state.winner, XiangqiSide.red);

      // The board keeps the final position, and the resign button goes inert rather than away: there
      // is still a game on the screen, it is just not one that can be resigned any more.
      expect(board(tester).position.toFen(), fx.xiangqiTestPositions.last.toFen());
      expect(barButton(CupertinoIcons.flag), findsOneWidget);
      expect(tester.widget<BottomBarButton>(barButton(CupertinoIcons.flag)).onTap, isNull);
    });
  });
}
