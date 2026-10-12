import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';

/// The moves a side may play, as the ICCS strings a move prints as.
///
/// What comes out of the rules is a list of [XiangqiMove]s in no particular order, so every
/// expectation here is written against the set.
///
/// Every position in this file was also fed to Pikafish — `position fen <fen>`, then `go perft 1` —
/// so the answers below are a reference engine's and not the author's. The one exception is the
/// facing-generals position of the first group: Pikafish refuses to load that one at all
/// ("Unsupported position. King can be captured."), which is itself the reason the rule it tests
/// exists. The positions Pikafish does load are the ones it accepts as reachable, so a few of the
/// pieces below stand where the rules alone would not have put them.
Set<String> movesOf(XiangqiPosition position) =>
    legalMoves(position).map((move) => move.iccs).toSet();

Set<String> movesFrom(String fen, String square) => legalMovesFrom(
  XiangqiPosition.fromFen(fen),
  XiangqiSquare.parse(square)!,
).map((move) => move.iccs).toSet();

void main() {
  group('the opening position', () {
    test('offers each side the 44 moves xiangqi is counted from', () {
      // The number every xiangqi perft table starts with, and one the rules reach on their own:
      // `perft(XiangqiPosition.initial(), 1)`. The deeper counts are in `xiangqi_perft_test.dart`,
      // which is where the generator is measured against Pikafish.
      expect(movesOf(XiangqiPosition.initial()).length, 44);
    });

    test('offers the moves it should, piece by piece', () {
      final moves = movesOf(XiangqiPosition.initial());
      // A chariot walks up its file until the soldier in front of it, and no further.
      expect(moves, containsAll(['a0a1', 'a0a2', 'i0i1', 'i0i2']));
      expect(moves, isNot(contains('a0a3')));
      // A horse jumps to the two squares its legs leave open — not the third, whose leg the
      // elephant stands on.
      expect(moves, containsAll(['b0c2', 'b0a2', 'h0g2', 'h0i2']));
      expect(moves, isNot(contains('b0d1')));
      // An elephant moves two steps diagonally, over a clear eye: two moves from each of its two
      // squares, and no crossing of the river.
      expect(moves, containsAll(['c0e2', 'c0a2', 'g0e2', 'g0i2']));
      expect(moves.where((move) => move.startsWith('c0')).length, 2);
      // An advisor is confined to the palace's own diagonals, which from the palace's corner is
      // one square, not two.
      expect(moves, containsAll(['d0e1', 'f0e1']));
      expect(moves.where((move) => move.startsWith('d0')).length, 1);
      // The general has one square to go to.
      expect(moves, containsAll(['e0e1']));
      expect(moves.where((move) => move.startsWith('e0')).length, 1);
      // A cannon slides like a chariot until the first piece, which is its screen: over the enemy
      // cannon and the empty square behind it, it takes the horse on the back rank. Downwards it
      // is the horse in front of it that stops it, so b0 is no move.
      expect(moves, contains('b2b9'));
      expect(moves, contains('h2h9'));
      expect(moves, containsAll(['b2b1', 'b2b3', 'b2b6', 'b2a2', 'b2g2']));
      expect(moves, isNot(contains('b2b7')));
      expect(moves.where((move) => move.startsWith('b2')).length, 12);
      // Soldiers step forward, one square, and that is all before the river.
      expect(moves, containsAll(['a3a4', 'c3c4', 'e3e4', 'g3g4', 'i3i4']));
      expect(moves.where((move) => move.startsWith('a3')).length, 1);
    });

    test('a move is legal exactly when it is in the list', () {
      final position = XiangqiPosition.initial();
      expect(isLegal(position, XiangqiMove.parseIccs('h2e2')!), isTrue);
      expect(isLegal(position, XiangqiMove.parseIccs('e3e6')!), isFalse);
      expect(isLegal(position, XiangqiMove.parseIccs('e0e1')!), isTrue);
    });
  });

  group('the generals', () {
    test('may not be left facing each other down an open file', () {
      // Nothing at all between the two generals. Red has to break the line, and stepping up the
      // file leaves them facing, so that is not a move.
      const facing = '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1';
      expect(movesOf(XiangqiPosition.fromFen(facing)), {'e0d0', 'e0f0'});
    });

    test('may not step onto the file of the other one, however far apart they are', () {
      // The same position with the black general one file across the board: d0 is no longer the
      // escape it was, because standing on d0 is what would face the two of them.
      expect(movesFrom('3k5/9/9/9/9/9/9/9/9/4K4 w - - 0 1', 'e0'), {'e0e1', 'e0f0'});
    });
  });

  group('a general in check', () {
    test('has only the moves that answer the check', () {
      // A black chariot on the general's file checks it, with the black general on that same file
      // behind its own chariot: the general can step aside but cannot take, because taking would
      // leave the two generals facing each other.
      final position = XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/4r4/4K4 w - - 0 1');
      expect(isCheck(position), isTrue);
      expect(isCheckmate(position), isFalse);
      expect(movesOf(position), {'e0d0', 'e0f0'});
    });
  });

  group('checkmate', () {
    // The chariot on the file checks the general; the chariot on the back rank covers d0, the
    // horse on g2 covers f0, and the black general behind its own chariot stops the general
    // taking it.
    const mate = '3rk4/9/9/9/9/9/9/6n2/4r4/4K4 w - - 0 1';

    test('is a check with no move left to answer it', () {
      final position = XiangqiPosition.fromFen(mate);
      expect(isCheck(position), isTrue);
      expect(legalMoves(position), isEmpty);
      expect(isCheckmate(position), isTrue);
      expect(isGameOver(position), isTrue);
    });

    test('takes the one piece that covers the escape away and it is no longer mate', () {
      // The horse on g2 is what covers f0, so without it the general simply steps aside.
      final position = XiangqiPosition.fromFen('3rk4/9/9/9/9/9/9/9/4r4/4K4 w - - 0 1');
      expect(isCheck(position), isTrue);
      expect(movesOf(position), {'e0f0'});
      expect(isCheckmate(position), isFalse);
    });
  });

  group('困毙: a side that cannot move', () {
    // Red is not in check: the chariot on f8 covers f0, the horse on c2 covers d0 and e1, but
    // nothing attacks the square the general is standing on.
    const stuck = '3k5/5r3/9/9/9/9/9/2n6/9/4K4 w - - 0 1';

    test('is not a draw, it is a loss', () {
      final position = XiangqiPosition.fromFen(stuck);
      expect(isCheck(position), isFalse);
      expect(legalMoves(position), isEmpty);
      expect(isStalemate(position), isTrue);
      expect(isCheckmate(position), isFalse);
      // Chess makes a draw of this; xiangqi ends the game, and the side that cannot move has lost.
      expect(isGameOver(position), isTrue);
    });
  });

  group('the pieces that move differently in xiangqi', () {
    test('a horse is blocked by the leg it jumps over', () {
      // From a0 a horse can reach c1 over b0 and b2 over a1. The chariot on a1 is the leg of that
      // second jump, so only the jump across the rank is left.
      expect(movesFrom('3k5/9/9/9/9/9/9/9/R8/N3K4 w - - 0 1', 'a0'), {'a0c1'});
      expect(movesFrom('3k5/9/9/9/9/9/9/9/9/N3K4 w - - 0 1', 'a0'), {'a0c1', 'a0b2'});
    });

    test('an elephant is blocked by the eye it steps over, and never crosses the river', () {
      // The horse on d1 is the eye of the elephant's move from c0 to e2, which leaves the other
      // one. A second elephant stands on the river bank at c4, where the two squares it could
      // reach over the river are not squares it may go to.
      expect(movesFrom('3k5/9/9/9/9/9/9/9/3N5/2B1K4 w - - 0 1', 'c0'), {'c0a2'});
      expect(movesFrom('3k5/9/9/9/9/9/9/9/9/2B1K4 w - - 0 1', 'c0'), {'c0a2', 'c0e2'});
      expect(movesFrom('3k5/9/9/9/9/2B6/9/9/9/4K4 w - - 0 1', 'c4'), {'c4a2', 'c4e2'});
    });

    test('a cannon captures over exactly one screen, and slides on the squares before it', () {
      // A black cannon on the file is the screen, a black horse behind it the first piece past
      // the screen, and that is the piece that can be taken. The cannon cannot take its own
      // screen, cannot land on the empty square between screen and target, and does not slide
      // through either.
      const oneScreen = '1n1k5/9/1c7/9/9/9/9/1C7/9/4K4 w - - 0 1';
      expect(movesFrom(oneScreen, 'b2'), {
        'b2a2',
        'b2b0',
        'b2b1',
        'b2b3',
        'b2b4',
        'b2b5',
        'b2b6',
        'b2b9',
        'b2c2',
        'b2d2',
        'b2e2',
        'b2f2',
        'b2g2',
        'b2h2',
        'b2i2',
      });

      // Put a black chariot in front of the screen: now the cannon takes the chariot's square
      // over the screen, and the horse two squares further away is out of reach.
      const twoScreens = '1n1k5/9/1c7/9/1r7/9/9/1C7/9/4K4 w - - 0 1';
      expect(movesFrom(twoScreens, 'b2'), {
        'b2a2',
        'b2b0',
        'b2b1',
        'b2b3',
        'b2b4',
        'b2b7',
        'b2c2',
        'b2d2',
        'b2e2',
        'b2f2',
        'b2g2',
        'b2h2',
        'b2i2',
      });
    });

    test('a soldier gains the sideways step when it crosses the river, and never loses it', () {
      // On its own half: forward only, and one square.
      expect(movesFrom('3k5/9/9/9/9/4P4/9/9/9/4K4 w - - 0 1', 'e4'), {'e4e5'});
      // Across it: forward and to either side, and never back.
      expect(movesFrom('3k5/9/9/9/4P4/9/9/9/9/4K4 w - - 0 1', 'e5'), {'e5d5', 'e5e6', 'e5f5'});
      expect(movesFrom('3k5/9/9/9/4P4/9/9/9/9/4K4 w - - 0 1', 'e5'), isNot(contains('e5e4')));
    });
  });

  group('play', () {
    test('moves the piece and hands the turn over', () {
      final position = XiangqiPosition.initial();
      final after = play(position, XiangqiMove.parseIccs('h2e2')!);
      expect(after.pieceAt(XiangqiSquare.parse('e2')!), const XiangqiPiece(.red, .cannon));
      expect(after.pieceAt(XiangqiSquare.parse('h2')!), isNull);
      expect(after.turn, XiangqiSide.black);
    });

    test('counts the half-moves up, and resets them on a capture', () {
      final position = XiangqiPosition.initial();
      final quiet = play(position, XiangqiMove.parseIccs('h2e2')!);
      expect(quiet.halfmoveClock, 1);
      expect(quiet.fullmoveNumber, 1);

      final reply = play(quiet, XiangqiMove.parseIccs('h9g7')!);
      expect(reply.halfmoveClock, 2);
      // Black's move is the one that ends a move: the number goes up after it, not after red's.
      expect(reply.fullmoveNumber, 2);

      // A cannon taking a horse over a cannon: the clock starts again.
      final capture = play(position, XiangqiMove.parseIccs('b2b9')!);
      expect(capture.pieceAt(XiangqiSquare.parse('b9')!), const XiangqiPiece(.red, .cannon));
      expect(capture.halfmoveClock, 0);
    });

    test('refuses a move that is not in the list, rather than quietly playing it', () {
      final position = XiangqiPosition.initial();
      expect(
        () => play(position, XiangqiMove.parseIccs('e3e6')!),
        throwsA(isA<XiangqiIllegalMoveException>()),
      );
      // A move that would leave the generals facing is refused the same way: the general on e0
      // may not step up to e1 while the other one is on e9 with nothing in between.
      expect(
        () => play(
          XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1'),
          XiangqiMove.parseIccs('e0e1')!,
        ),
        throwsA(isA<XiangqiIllegalMoveException>()),
      );
    });

    test('a move is in the list exactly when playing it is allowed', () {
      // The one property that makes the generator and the filter one thing rather than two: every
      // move the rules offer is a move the rules accept.
      var position = XiangqiPosition.initial();
      for (final iccs in ['h2e2', 'h9g7', 'b0c2', 'b9c7', 'a0a1', 'a9a8']) {
        final move = XiangqiMove.parseIccs(iccs)!;
        expect(isLegal(position, move), isTrue, reason: iccs);
        position = play(position, move);
      }
    });
  });
}
