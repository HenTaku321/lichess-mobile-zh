// Tests for the controller of a game being played on xiangqi.com.
//
// What is under test is the reading of the wire and nothing else: the frames of
// `xiangqi_online_game_fixture.dart` are pushed through a fake socket, and where the game ends up is
// checked against the repo's own rules engine rather than against a string written here — the
// fixture plays the moves itself and the tests compare the two.
//
// The frames' shapes are the measured ones (2026-10-13 probe), the sequence is not; see the
// fixture's first comment.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart' show XiangqiGameEnd;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';

import 'xiangqi_online_game_fixture.dart' as fx;

/// A game under test: the container the controller lives in, and the server side of its socket.
class XiangqiOnlineHarness({
  required final ProviderContainer container,
  required final fx.FakeXiangqiChannelFactory factory,

  /// The id of the game the controller was opened on.
  final String gameId = fx.xiangqiTestGameId,
}) {
  XiangqiOnlineGameController get controller =>
      container.read(xiangqiOnlineGameControllerProvider(gameId).notifier);

  /// The game as it stands.
  ///
  /// `requireValue` and not `value`: a controller whose snapshot has not been read yet is still
  /// `AsyncData` — [XiangqiOnlineGameState.isLoaded] is what says whether it holds a game — and a
  /// test that read a loading or failed provider as though it had a game would be reading a lie.
  XiangqiOnlineGameState get state =>
      container.read(xiangqiOnlineGameControllerProvider(gameId)).requireValue;

  /// The channel the client is talking on.
  fx.FakeXiangqiChannel get channel => factory.channels.last;

  /// Pushes the frame [event] carries and lets the controller read it.
  Future<void> send(String frame) async {
    channel.fromServer(frame);
    await pumpEventQueue();
  }
}

/// Opens the game a token plays or watches, over a socket whose other end is fake.
///
/// The two overrides are the whole of the network: the socket's own provider is replaced by a real
/// [XiangqiSocketClient] whose channel factory and token are the test's, and the storage the
/// controller reads the token from is an in-memory fake. Nothing here is a lichess provider, so no
/// HTTP client, no database and no plugin is involved.
Future<XiangqiOnlineHarness> makeHarness(String token) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final client = XiangqiSocketClient(channelFactory: factory, getToken: () async => token);
  addTearDown(client.dispose);

  final container = ProviderContainer(
    overrides: [
      xiangqiSocketProvider.overrideWith((Ref ref) {
        ref.onDispose(client.dispose);
        return client;
      }),
      xiangqiAuthStorageProvider.overrideWithValue(
        fx.FakeXiangqiAuthStorage(fx.xiangqiTestSession(token)),
      ),
    ],
  );
  addTearDown(container.dispose);

  final harness = XiangqiOnlineHarness(container: container, factory: factory);
  // The controller is autoDispose and a bare `read` is not a watcher, so without something holding
  // it the game would be thrown away between two lines of a test.
  final watched = container.listen(xiangqiOnlineGameControllerProvider(harness.gameId), (_, _) {});
  addTearDown(watched.close);

  // The controller opens the socket from its own build, so the handshake is served here: the first
  // frame of the conversation is already on the channel by the time this returns.
  await container.read(xiangqiOnlineGameControllerProvider(harness.gameId).future);
  await pumpEventQueue();
  harness.channel.fromServer(fx.openFrame);
  harness.channel.fromServer(fx.connectAckFrame);
  await pumpEventQueue();
  return harness;
}

void main() {
  group('XiangqiOnlineGameController', () {
    test('the snapshot names both seats, and the one this device is in', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));

      // The conversation starts by itself: the handshake frame, then the subscribe the controller
      // sends the moment the connection is up. The snapshot is what that subscribe is waiting for.
      expect(game.channel.sent.first, startsWith('40/xiangqi,'));
      expect(game.channel.sent.last, contains('"g_v2.get"'));
      expect(game.state.isLoaded, isFalse, reason: 'nothing has been read yet');

      await game.send(fx.xiangqiSnapshotFrame());

      expect(game.state.isLoaded, isTrue);
      expect(game.state.isSpectator, isFalse);
      expect(game.state.mySide, XiangqiSide.red);
      expect(game.state.red.name, fx.xiangqiTestRedName);
      expect(game.state.black.name, fx.xiangqiTestBlackName);
      expect(game.state.black.rating, fx.xiangqiTestBlackRating);
      expect(game.state.red.rating, isNull, reason: 'a guest seat has no rating');
      expect(game.state.isRated, isTrue);
      expect(game.state.moves, isEmpty);
      expect(game.state.position.toFen(), fx.xiangqiTestPositions.first.toFen());
      expect(game.state.isMyTurn, isTrue, reason: 'red moves first, and red is mine');
      expect(game.state.end, isNull);
    });

    test('a snapshot nested under data is read the same as a top-level one', () async {
      // The shape the server really sends: the whole snapshot one level down, under `data`. Every
      // other frame is nested that way, and this one is too — measured on 2026-10-15 against a
      // signed-in account. The top-level form the rest of this file sends is the controller's other
      // branch, and both have to work.
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));

      await game.send(fx.xiangqiNestedSnapshotFrame());

      expect(game.state.isLoaded, isTrue);
      expect(game.state.mySide, XiangqiSide.red);
      expect(game.state.red.name, fx.xiangqiTestRedName);
      expect(game.state.black.name, fx.xiangqiTestBlackName);
      expect(game.state.black.rating, fx.xiangqiTestBlackRating);
      expect(game.state.isRated, isTrue);
      expect(game.state.isMyTurn, isTrue);
    });

    test('a nested snapshot carrying moves replays them', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));

      await game.send(fx.xiangqiNestedSnapshotFrame(plies: fx.xiangqiTestMoveUcis.length));

      expect(game.state.isLoaded, isTrue);
      expect(game.state.moves, hasLength(fx.xiangqiTestMoveUcis.length));
      expect(
        game.state.position.toFen(),
        fx.xiangqiTestPositions.last.toFen(),
        reason: 'the position is the one the moves make, not the one the payload claims',
      );
    });

    test('a device in neither seat is watching, not playing', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestSpectatorId));

      await game.send(fx.xiangqiSnapshotFrame());

      expect(game.state.isLoaded, isTrue);
      expect(game.state.isSpectator, isTrue);
      expect(game.state.mySide, isNull);
      expect(game.state.isMyTurn, isFalse);
    });

    test("every move replays onto the rules engine's own position", () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame());

      for (var ply = 1; ply <= fx.xiangqiTestMoveUcis.length; ply++) {
        await game.send(fx.xiangqiMoveFrame(ply));

        expect(
          game.state.position.toFen(),
          fx.xiangqiTestPositions[ply].toFen(),
          reason: 'the position after ply $ply',
        );
        expect(game.state.moves, hasLength(ply));
      }

      expect(game.state.moves.toList(), orderedEquals(fx.xiangqiTestMoves.toList()));
      expect(
        game.state.positions.map((position) => position.toFen()),
        orderedEquals(fx.xiangqiTestPositions.map((position) => position.toFen())),
      );
      expect(game.state.lastMove, fx.xiangqiTestMoves.last);
      expect(game.state.selected, isNull, reason: 'a move arriving clears the pick-up');
    });

    test('the rank-ten move lands on the square it names, not nine ranks away', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame());

      // `h10g8` is xiangqi.com's rank-1 spelling of the black horse's `h9g7`, and it is the one
      // square in this protocol whose rank has two digits: read as rank 1 it would be a move no
      // position in this game has, and the replay would have refused the game outright.
      final horse = fx.xiangqiTestMoves[1];
      final before = game.state.position.pieceAt(horse.from);
      expect(before, const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.knight));

      await game.send(fx.xiangqiMoveFrame(1));
      await game.send(fx.xiangqiMoveFrame(2));

      expect(horse.to.name, 'g7');
      expect(
        game.state.position.pieceAt(horse.to),
        const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.knight),
      );
      expect(game.state.position.pieceAt(horse.from), isNull);
    });

    test('the clocks come off the frame and are counted from its stamp', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame());

      for (var ply = 1; ply <= fx.xiangqiTestMoveUcis.length; ply++) {
        await game.send(fx.xiangqiMoveFrame(ply));
      }

      final plies = fx.xiangqiTestMoveUcis.length;
      final redSeconds = fx.xiangqiTestSecondsLeft(XiangqiSide.red, plies);
      final blackSeconds = fx.xiangqiTestSecondsLeft(XiangqiSide.black, plies);
      expect(game.state.redSeconds, redSeconds);
      expect(game.state.blackSeconds, blackSeconds);

      // Five plies in, red has moved three times and black twice, so it is black to move: black's
      // clock is the one running — it reads what the frame said at the stamp, less the time since —
      // and red's stands where the frame left it.
      expect(game.state.turn, XiangqiSide.black);
      expect(
        game.state.secondsLeftFor(XiangqiSide.black, fx.xiangqiTestClockAfter(0)),
        blackSeconds,
      );
      expect(
        game.state.secondsLeftFor(XiangqiSide.black, fx.xiangqiTestClockAfter(4)),
        blackSeconds - 4,
      );
      expect(
        game.state.secondsLeftFor(XiangqiSide.red, fx.xiangqiTestClockAfter(30)),
        redSeconds,
        reason: 'the side that is not to move is not counting',
      );
      // A clock is never drawn below zero, however long the screen has been open.
      expect(
        game.state.secondsLeftFor(XiangqiSide.black, fx.xiangqiTestClockAfter(blackSeconds + 60)),
        0,
      );
    });

    test('a move is sent, and does not move the board until the server echoes it', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame());

      final move = fx.xiangqiTestMoves.first;
      expect(await game.controller.playMove(move), isTrue);

      final sent = game.channel.sent.last! as String;
      expect(sent, startsWith('42/xiangqi,2["g_v2.move",{"game_id":"${fx.xiangqiTestGameId}",'));
      expect(sent, contains('"move":"${fx.xiangqiTestMoveUcis.first}"'));
      // Seconds, not milliseconds: the probe sent milliseconds and the server dropped the move.
      expect(sent, contains('"thinking_time":'));
      expect(
        game.state.moves,
        isEmpty,
        reason: 'the board only moves when the server says the move landed',
      );
      expect(game.state.position.toFen(), fx.xiangqiTestPositions.first.toFen());
    });

    test('picking a piece up offers its own legal moves, and nothing else is moved', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame());

      final move = fx.xiangqiTestMoves.first;
      final theirs = XiangqiSquare.parse('a9')!; // black's chariot, on black's own back rank

      // With nothing picked up, the other side's piece is not a piece: the tap is dropped.
      game.controller.tapSquare(theirs);
      expect(game.state.selected, isNull);

      game.controller.tapSquare(move.from);
      expect(game.state.selected, move.from);
      expect(game.state.selectedMoves, isNotEmpty);
      expect(game.state.selectedMoves, contains(move));
      expect(game.state.moves, isEmpty, reason: 'picking a piece up plays nothing');

      // Tapping their piece with one of mine already up is not a move, and it lets mine back down.
      game.controller.tapSquare(theirs);
      expect(game.state.selected, isNull);
      expect(game.state.moves, isEmpty);
    });

    test('game.server.end names the side that resigned', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame());
      for (var ply = 1; ply <= fx.xiangqiTestMoveUcis.length; ply++) {
        await game.send(fx.xiangqiMoveFrame(ply));
      }

      await game.send(fx.xiangqiEndFrame());

      expect(game.state.end, XiangqiGameEnd.resign);
      expect(game.state.resignedBy, XiangqiSide.black, reason: 'black is the side that lost');
      expect(game.state.flaggedSide, isNull);
      expect(game.state.winner, XiangqiSide.red);
      expect(game.state.isFinished, isTrue);
      expect(game.state.isMyTurn, isFalse);
      expect(game.state.moves, hasLength(fx.xiangqiTestMoveUcis.length));
    });

    test('a watcher is told how a game ended by asking for the archived one', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestSpectatorId));
      await game.send(fx.xiangqiSnapshotFrame(plies: fx.xiangqiTestMoveUcis.length));
      expect(game.state.mySide, isNull);
      expect(game.state.moves, hasLength(fx.xiangqiTestMoveUcis.length));

      // A game that has finished answers `g_v2.get` with a redirect rather than a snapshot: the
      // client is told to say the same thing under the name the ack carries, which is the server's
      // to choose. This is also the whole of what a spectator has to go on — nothing ends a game for
      // a watcher, so the asking is what finds out.
      game.channel.ackOverrides['g_v2.get'] = fx.xiangqiRedirectAck;

      await game.controller.resync();
      await pumpEventQueue();

      expect(
        game.channel.sent.map((frame) => frame! as String),
        contains(contains('"game.archived.get"')),
        reason: 'the redirect is followed under the name it names',
      );

      await game.send(fx.xiangqiArchivedSnapshotFrame());

      expect(game.state.end, XiangqiGameEnd.resign);
      expect(game.state.resignedBy, XiangqiSide.black);
      expect(game.state.winner, XiangqiSide.red);
      expect(game.state.position.toFen(), fx.xiangqiTestPositions.last.toFen());
      expect(game.state.moves, hasLength(fx.xiangqiTestMoveUcis.length));
    });

    test('game.error is an error with a message and the game itself without one', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame());

      await game.send(
        fx.xiangqiEventFrame('game.error', {
          'data': {'message': 'The move was refused.'},
        }),
      );
      expect(game.state.error, 'The move was refused.');
      expect(game.state.isLoaded, isTrue, reason: 'an error is not a lost game');

      // With no message the frame *is* the state — the server telling a client that has drifted where
      // it really is — and it is read as the snapshot it is.
      await game.send(fx.xiangqiEventFrame('game.error', fx.xiangqiSnapshotPayload(plies: 2)));

      expect(game.state.error, isNull);
      expect(game.state.moves, hasLength(2));
      expect(game.state.position.toFen(), fx.xiangqiTestPositions[2].toFen());
      expect(game.state.mySide, XiangqiSide.red);
    });

    test('a game that has been read does not come back to life', () async {
      final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
      await game.send(fx.xiangqiSnapshotFrame(plies: fx.xiangqiTestMoveUcis.length, ended: true));
      expect(game.state.end, XiangqiGameEnd.resign);

      // A later snapshot that says nothing about how the game ended is silent, not a resurrection:
      // the end is only ever added to.
      await game.send(fx.xiangqiSnapshotFrame(plies: fx.xiangqiTestMoveUcis.length));

      expect(game.state.end, XiangqiGameEnd.resign);
      expect(game.state.resignedBy, XiangqiSide.black);
    });
  });
}
