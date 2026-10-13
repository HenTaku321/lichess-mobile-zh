import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';

import '../../binding.dart';
import '../../service/fake_sound_service.dart';
import '../engine/fake_transport.dart';

/// The square named [name], which the tests below write the way a player would.
XiangqiSquare square(String name) {
  final square = XiangqiSquare.parse(name);
  if (square == null) throw ArgumentError('Not a square: $name');
  return square;
}

/// The move written [iccs], which is also how Pikafish writes one.
XiangqiMove move(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// The standard arrangement, black to move — a well formed position that is not the opening.
const String kBlackToMoveFen =
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1';

/// A game being played: the container it lives in, the engine it is playing, and what the game has
/// asked the view to say.
class XiangqiHarness(final ProviderContainer container, final FakeTransport transport) {
  /// Every event the game has put on the UI event bus, in order.
  final List<UiEvent> events = [];

  XiangqiGameController get controller => container.read(xiangqiGameControllerProvider.notifier);

  XiangqiGameState get state => container.read(xiangqiGameControllerProvider);
}

/// A game on a real [Engine] whose transport is fake, with the engine already up.
///
/// Overriding the game's own engine provider and not the factory behind it is deliberate: what is
/// under test is the game, and an [Engine] over a [FakeTransport] is the smallest thing that answers
/// the way Pikafish does — the handshake, the option hygiene, the commands and the `bestmove`
/// parsing are all the real ones, and only the bytes in and out are not.
Future<XiangqiHarness> makeHarness({SoundService? soundService}) async {
  final binding = TestLichessBinding.ensureInitialized();
  addTearDown(binding.reset);

  final transport = FakeTransport(
    spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
    startupLines: kPikafishHandshake,
  );
  final engine = Engine(transport);
  addTearDown(engine.dispose);

  final container = ProviderContainer(
    overrides: [
      xiangqiEngineProvider.overrideWith((Ref ref) => engine),
      // A move now plays a sound and a haptic as it lands — see [MoveFeedbackService] — and a test
      // surface has neither an audio device nor a preference store behind it: the haptics go
      // nowhere, and the sound service is faked so that nothing tries to open a player.
      soundServiceProvider.overrideWithValue(soundService ?? FakeSoundService()),
    ],
  );
  addTearDown(container.dispose);

  final harness = XiangqiHarness(container, transport);
  final events = container.read(uiEventBusProvider).stream.listen(harness.events.add);
  addTearDown(events.cancel);

  // The controller is autoDispose and a bare `read` is not a watcher, so without something holding
  // it the game would be thrown away between two lines of a test.
  final watched = container.listen(xiangqiGameControllerProvider, (_, _) {});
  addTearDown(watched.close);

  // The engine is started by the controller's own build, so this is also what lets its handshake be
  // read before the first move is made.
  await pumpEventQueue();
  return harness;
}

/// Lets the engine reach its `bestmove`, as a real one does once it is asked to search.
Future<void> answer(FakeTransport transport, String iccs) async {
  await pumpEventQueue();
  transport.emit('readyok');
  await pumpEventQueue();
  transport.emit('bestmove $iccs');
  await pumpEventQueue();
}

/// A sound service that writes down what it was asked to play, so that a test can tell one kind of
/// move from another.
///
/// A capture is asked for as `playCaptureSound` and a quiet move as `play`, and both are written
/// down as the sound they mean: the point of the test is which of the two the game asked for, not
/// which method it went through.
class RecordingSoundService() implements SoundService {
  final List<Sound> sounds = [];

  @override
  Future<void> play(Sound sound, {double? volume}) async {
    sounds.add(sound);
  }

  @override
  Future<void> playCaptureSound(Variant variant, {double? volume}) async {
    sounds.add(Sound.capture);
  }

  @override
  Future<void> changeTheme(SoundTheme theme, {bool playSound = false}) async {}

  @override
  Future<void> release() async {}
}

void main() {
  group('XiangqiGameController', () {
    test('the player moves, and the computer is asked to answer', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4);
      expect(harness.state.isPlayerTurn, isTrue);

      harness.controller.tapSquare(square('h2'));
      expect(harness.state.selected, square('h2'));
      expect(harness.state.selectedMoves, contains(move('h2e2')));

      harness.controller.tapSquare(square('e2'));
      expect(harness.state.moves, IList([move('h2e2')]));
      expect(harness.state.isEngineThinking, isTrue);
      expect(harness.state.isPlayerTurn, isFalse);

      await pumpEventQueue();
      expect(harness.transport.takeCommands(), ['ucinewgame', 'isready']);

      harness.transport.emit('readyok');
      await pumpEventQueue();

      // A xiangqi position on an engine layer that speaks dartchess: there is no move list to send
      // and no variant to name, so the FEN reaching the engine is the whole of what it is told. It is
      // the position after the player's move — the one the computer has to answer — with the side to
      // move in it saying whose turn it is. Nothing is set on the engine either: Pikafish declares no
      // option the app would set for this.
      expect(harness.transport.takeCommands(), [
        'position fen ${play(XiangqiPosition.initial(), move('h2e2')).toFen()}',
        // The default level, which is both a deadline and a cap: Pikafish has no strength to set,
        // so how hard it plays is the whole of how it is asked to search. See [XiangqiDifficulty].
        'go movetime 50 depth 6',
      ]);

      harness.transport.emit('bestmove h9g7 ponder b0c2');
      await pumpEventQueue();

      expect(harness.state.moves, IList([move('h2e2'), move('h9g7')]));
      expect(harness.state.isEngineThinking, isFalse);
      expect(harness.state.isPlayerTurn, isTrue);
      expect(harness.state.isInCheck, isFalse);
    });

    test('a move is heard as it is played, and a piece picked up is not', () async {
      final sound = RecordingSoundService();
      final harness = await makeHarness(soundService: sound);
      harness.controller.startNewGame(side: .red, difficulty: .level4);
      // A player on red is not asked for anything of the engine's, so whatever is heard from here
      // is the player's own doing.
      expect(sound.sounds, isEmpty);

      harness.controller.tapSquare(square('h2'));
      expect(sound.sounds, isEmpty, reason: 'picking a piece up is not a move');

      harness.controller.tapSquare(square('e2'));
      expect(sound.sounds, [Sound.move]);
    });

    test('the ladder is six levels, and both of its columns rise from end to end', () {
      const levels = XiangqiDifficulty.values;

      // Six rather than the chess game's twelve, because there is no strength setting behind the
      // dial here — see [XiangqiDifficulty] — and on a budget-only axis six is as far as it goes.
      expect(levels.length, 6);
      expect(levels.map((level) => level.level), [1, 2, 3, 4, 5, 6]);
      // The two ends are pinned; the spacing between them is a starting point and may be re-tuned,
      // but nothing may move an end or turn two rungs the same way round.
      expect(levels.first.depth, 1);
      expect(levels.first.moveTime, const Duration(milliseconds: 1));
      expect(levels.last.depth, 15);
      expect(levels.last.moveTime, const Duration(milliseconds: 500));
      for (var i = 1; i < levels.length; i++) {
        expect(
          levels[i].depth,
          greaterThan(levels[i - 1].depth),
          reason: 'the depth of ${levels[i]} against ${levels[i - 1]}',
        );
        expect(
          levels[i].moveTime,
          greaterThan(levels[i - 1].moveTime),
          reason: 'the move time of ${levels[i]} against ${levels[i - 1]}',
        );
      }

      expect(XiangqiDifficulty.defaultLevel, XiangqiDifficulty.level4);
    });

    test('a level is asked for as the search budget it is', () async {
      for (final difficulty in XiangqiDifficulty.values) {
        // A player who took black: red moves first, so the computer opens and the search happens
        // without a move of the player's to trigger it.
        final harness = await makeHarness();
        harness.controller.startNewGame(side: .black, difficulty: difficulty);
        expect(harness.state.isEngineThinking, isTrue, reason: 'for $difficulty');

        await pumpEventQueue();
        harness.transport.takeCommands();
        harness.transport.emit('readyok');
        await pumpEventQueue();
        // Both halves of the rung reach the engine: a level is a deadline and a cap at once, since
        // on its own neither says what the level is.
        expect(harness.transport.takeCommands(), [
          'position fen $kXiangqiInitialFen',
          'go movetime ${difficulty.moveTime.inMilliseconds} depth ${difficulty.depth}',
        ], reason: 'for $difficulty');

        harness.transport.emit('bestmove h2e2');
        await pumpEventQueue();
        expect(harness.state.moves, IList([move('h2e2')]), reason: 'for $difficulty');
        expect(harness.state.isPlayerTurn, isTrue, reason: 'for $difficulty');
      }
    });

    test('the board takes nothing while the computer is thinking', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .black, difficulty: .level4);
      await pumpEventQueue();

      // A red chariot, and it is the computer's to move.
      harness.controller.tapSquare(square('a0'));
      expect(harness.state.selected, isNull);

      // And there is nothing of the player's to take back yet: the only move played is the
      // computer's opening.
      harness.controller.undo();
      expect(harness.state.moves, isEmpty);
      expect(harness.state.isEngineThinking, isTrue);
      expect(harness.state.canUndo, isFalse);
    });

    test('a move taken back while the computer is thinking stops it answering', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4);
      harness.controller.tapSquare(square('h2'));
      harness.controller.tapSquare(square('e2'));
      await pumpEventQueue();
      expect(harness.transport.takeCommands(), ['ucinewgame', 'isready']);

      harness.controller.undo();

      expect(harness.state.moves, isEmpty);
      expect(harness.state.position, XiangqiPosition.initial());
      expect(harness.state.isEngineThinking, isFalse);
      expect(harness.state.isPlayerTurn, isTrue);

      // The answer to a question the game has moved on from still arrives — a search cannot be
      // un-asked — and playing it would put a move on the board that the player took back.
      harness.transport.emit('readyok');
      await pumpEventQueue();
      harness.transport.emit('bestmove h9g7');
      await pumpEventQueue();

      expect(harness.state.moves, isEmpty);
      expect(harness.state.isPlayerTurn, isTrue);
      expect(
        harness.transport.takeCommands(),
        isEmpty,
        reason: 'the search had not started, so there was nothing to stop',
      );
    });

    test('a move taken back after the computer has replied takes them both back', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4);
      harness.controller.tapSquare(square('h2'));
      harness.controller.tapSquare(square('e2'));
      await answer(harness.transport, 'h9g7');
      expect(harness.state.moves, IList([move('h2e2'), move('h9g7')]));

      harness.controller.undo();

      expect(harness.state.moves, isEmpty);
      expect(harness.state.position, XiangqiPosition.initial());
      expect(harness.state.canUndo, isFalse);
    });

    test("a player who took black takes their own move back, not the computer's", () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .black, difficulty: .level4);
      await answer(harness.transport, 'h2e2');
      expect(harness.state.isPlayerTurn, isTrue);

      harness.controller.tapSquare(square('b9'));
      harness.controller.tapSquare(square('c7'));
      expect(harness.state.moves.length, 2);

      harness.controller.undo();

      expect(
        harness.state.moves,
        IList([move('h2e2')]),
        reason: "the computer's move is not the player's to take back",
      );
      expect(harness.state.turn, XiangqiSide.black);
      expect(harness.state.isPlayerTurn, isTrue);
    });

    test('resigning ends the game, and a late answer cannot un-end it', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4);
      harness.controller.tapSquare(square('h2'));
      harness.controller.tapSquare(square('e2'));
      await pumpEventQueue();

      harness.controller.resign();

      expect(harness.state.end, XiangqiGameEnd.resign);
      expect(harness.state.winner, XiangqiSide.black);
      expect(harness.state.isFinished, isTrue);
      expect(harness.state.isEngineThinking, isFalse);
      expect(
        harness.state.canUndo,
        isFalse,
        reason: 'a game that is over has nothing to take back',
      );

      harness.transport.emit('readyok');
      await pumpEventQueue();
      harness.transport.emit('bestmove h9g7');
      await pumpEventQueue();

      expect(harness.state.moves, IList([move('h2e2')]));
      expect(harness.state.end, XiangqiGameEnd.resign);
    });

    test('an answer the board cannot play is reported, and no result is invented', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4);
      harness.controller.tapSquare(square('h2'));
      harness.controller.tapSquare(square('e2'));
      await pumpEventQueue();

      // A chariot through its own soldier: the sort of thing an engine answers with when it is
      // broken, or when it has been sent a position that is not the one on the board.
      await answer(harness.transport, 'a0a5');

      expect(harness.events, [isA<ShowErrorEvent>()]);
      expect(harness.state.moves, IList([move('h2e2')]));
      expect(harness.state.isEngineThinking, isFalse);
      expect(harness.state.end, isNull, reason: 'a computer that cannot answer has not lost');
    });

    test('the same position three times is a draw', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level1);

      // Both chariots shuffle out and back. Four plies is the shortest that brings a position round:
      // one chariot moving out and in again is not the same position, because the other has moved in
      // the meantime, so it takes a whole cycle of both before the opening position is on the board
      // again — twice, and the third time the game is drawn. This is not the real xiangqi rule (长将
      // and 长捉 are judged, not counted); it is the count the app makes do with.
      harness.controller.tapSquare(square('a0'));
      harness.controller.tapSquare(square('a1'));
      await answer(harness.transport, 'i9i8');
      harness.controller.tapSquare(square('a1'));
      harness.controller.tapSquare(square('a0'));
      await answer(harness.transport, 'i8i9');
      harness.controller.tapSquare(square('a0'));
      harness.controller.tapSquare(square('a1'));
      await answer(harness.transport, 'i9i8');
      harness.controller.tapSquare(square('a1'));
      harness.controller.tapSquare(square('a0'));
      await answer(harness.transport, 'i8i9');

      expect(harness.state.moves.length, 8);
      expect(harness.state.end, XiangqiGameEnd.threefoldRepetition);
      expect(harness.state.winner, isNull, reason: 'a repetition is nobody’s win');
      expect(harness.state.isFinished, isTrue);
      // The game ended on the computer's move, so it is not asked to answer itself.
      expect(harness.state.isEngineThinking, isFalse);
      expect(harness.state.canUndo, isFalse);
    });

    test('over the board both sides move, and the engine is never asked', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4, opponent: .human);
      await pumpEventQueue();

      // Red, and then black: the side to move is the side a person is sitting behind, whichever it
      // is, so both of the board's ends are the board's to take.
      expect(harness.state.isPlayerTurn, isTrue);
      harness.controller.tapSquare(square('h2'));
      harness.controller.tapSquare(square('e2'));
      expect(harness.state.moves, IList([move('h2e2')]));
      expect(harness.state.turn, XiangqiSide.black);
      expect(harness.state.isPlayerTurn, isTrue);
      expect(harness.state.isEngineThinking, isFalse);

      harness.controller.tapSquare(square('h9'));
      harness.controller.tapSquare(square('g7'));
      expect(harness.state.moves, IList([move('h2e2'), move('h9g7')]));
      expect(harness.state.turn, XiangqiSide.red);
      expect(harness.state.isPlayerTurn, isTrue);

      // Nothing was ever searched for: there is no other side for a search to belong to, and the
      // engine that is up behind the controller was never given a turn.
      await pumpEventQueue();
      expect(
        harness.transport.takeCommands().where((command) => command.startsWith('go ')),
        isEmpty,
      );
    });

    test('over the board a takeback is one ply, the engine move not being left out', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4, opponent: .human);
      harness.controller.tapSquare(square('h2'));
      harness.controller.tapSquare(square('e2'));
      harness.controller.tapSquare(square('h9'));
      harness.controller.tapSquare(square('g7'));
      expect(harness.state.moves.length, 2);

      harness.controller.undo();

      // Both plies were played at this board, so the position to come back to is the one before the
      // last of them and no search has to be taken into account.
      expect(harness.state.moves, IList([move('h2e2')]));
      expect(harness.state.turn, XiangqiSide.black);
      expect(harness.state.canUndo, isTrue);
    });

    test('a flag ends the game, and the side that ran out has lost', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4, opponent: .human);

      harness.controller.onFlag(XiangqiSide.black);

      expect(harness.state.end, XiangqiGameEnd.timeout);
      expect(harness.state.flaggedSide, XiangqiSide.black);
      expect(harness.state.winner, XiangqiSide.red);
      expect(harness.state.isFinished, isTrue);
      expect(harness.state.canUndo, isFalse);

      // A game that is over is not one the board takes anything more for.
      harness.controller.tapSquare(square('h2'));
      expect(harness.state.selected, isNull);
    });

    test('a new game without a position is the standard opening', () async {
      final harness = await makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4);

      // The case every no-argument caller takes, and the position no board editor had a hand in:
      // leaving the position out has to be the opening and not the empty board.
      expect(harness.state.position, XiangqiPosition.initial());
      expect(harness.state.moves, isEmpty);
      expect(harness.state.turn, XiangqiSide.red);
    });

    test('a new game can start from a given position', () async {
      final harness = await makeHarness();
      final start = XiangqiPosition.fromFen(kBlackToMoveFen);
      harness.controller.startNewGame(side: .red, difficulty: .level4, initialPosition: start);

      // The board is the position given, whole: no move has been played to get there and none is
      // invented to lead in — a game from a position is a game that begins on it.
      expect(harness.state.position, start);
      expect(harness.state.moves, isEmpty);
      expect(harness.state.turn, XiangqiSide.black);
    });

    test('a given position the player is not to move in is opened by the computer', () async {
      final harness = await makeHarness();
      final start = XiangqiPosition.fromFen(kBlackToMoveFen);
      // The player has red, but the position says black is to move, so the opening is the
      // computer's — the same path `side: black` takes through `isPlayerTurn`, with no case of its
      // own in the controller. This is what a FEN out of a board editor can do that a side choice
      // cannot, and the reason the position has to carry whose move it is.
      harness.controller.startNewGame(side: .red, difficulty: .level4, initialPosition: start);

      expect(harness.state.isPlayerTurn, isFalse);
      expect(harness.state.isEngineThinking, isTrue);

      await pumpEventQueue();
      harness.transport.takeCommands();
      harness.transport.emit('readyok');
      await pumpEventQueue();
      // The engine is asked about the position on the board and not the opening: a custom start is
      // searched like any other position, so the move search runs off the given FEN.
      const level = XiangqiDifficulty.level4;
      expect(harness.transport.takeCommands(), [
        'position fen ${start.toFen()}',
        'go movetime ${level.moveTime.inMilliseconds} depth ${level.depth}',
      ]);

      harness.transport.emit('bestmove h9g7');
      await pumpEventQueue();
      expect(harness.state.moves, IList([move('h9g7')]));
      expect(harness.state.isPlayerTurn, isTrue);
    });

    test('over the board a given position is just where the two players start', () async {
      final harness = await makeHarness();
      final start = XiangqiPosition.fromFen(kBlackToMoveFen);
      harness.controller.startNewGame(
        side: .red,
        difficulty: .level4,
        opponent: .human,
        initialPosition: start,
      );
      await pumpEventQueue();

      expect(harness.state.position, start);
      // Both sides are a person's over the board, so the side the position says is to move may
      // move — and nothing is searched for, as it never is there.
      expect(harness.state.isPlayerTurn, isTrue);
      expect(harness.state.isEngineThinking, isFalse);
      expect(
        harness.transport.takeCommands().where((command) => command.startsWith('go ')),
        isEmpty,
      );
    });
  });

  group('the verdict on a position', () {
    // One position and no moves behind it, which is all a verdict is a question about: how the game
    // got here is not part of the answer, and neither is anything the game is asked afterwards.
    XiangqiGameState stateOf(String fen) => XiangqiGameState(
      playerSide: .red,
      difficulty: .level4,
      positions: IList([XiangqiPosition.fromFen(fen)]),
      moves: const IListConst([]),
    );

    test('a general that cannot be saved is mate, and the side to move has lost', () {
      final state = stateOf('3rk4/9/9/9/9/9/9/6n2/4r4/4K4 w - - 0 1');

      expect(state.end, XiangqiGameEnd.checkmate);
      expect(state.winner, XiangqiSide.black);
      expect(state.isFinished, isTrue);
    });

    test('a side with no move at all has lost too — 困毙 is not a draw', () {
      final state = stateOf('3k5/5r3/9/9/9/9/9/2n6/9/4K4 w - - 0 1');

      expect(state.isInCheck, isFalse);
      expect(state.end, XiangqiGameEnd.stalemate);
      // Where chess would call this a draw, xiangqi calls it a loss: the player who cannot move has
      // lost, whether or not they were in check.
      expect(state.winner, XiangqiSide.black);
    });

    test('a position that is neither is still being played', () {
      final state = stateOf(kXiangqiInitialFen);

      expect(state.end, isNull);
      expect(state.winner, isNull);
      expect(state.isFinished, isFalse);
    });
  });
}
