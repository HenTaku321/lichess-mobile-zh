import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_export.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

/// The move written [iccs].
XiangqiMove move(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// The moves written [iccs], as a list.
IList<XiangqiMove> moves(List<String> iccs) => [for (final iccs in iccs) move(iccs)].lock;

/// The position the game starts from with black to move: a line that begins with the second player.
const _blackToMoveFen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1';

/// A position that is not the start of a game: an advisor gone, a cannon off the file it starts on,
/// and the counters wound on — so that an export that quietly reset any of it would be caught.
const _midgameFen = '1nbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C4/9/RNB1KABNR w - - 7 33';

void main() {
  group('xiangqiFenExport', () {
    test('writes the position as a FEN the parser reads back unchanged', () {
      for (final fen in [kXiangqiInitialFen, _blackToMoveFen, _midgameFen]) {
        expect(
          xiangqiFenExport(XiangqiPosition.fromFen(fen)),
          fen,
          reason: 'a FEN export that cannot be read back is not an export',
        );
      }
    });

    test('it is the position through the whole round trip, counters and all', () {
      final position = XiangqiPosition.fromFen(_midgameFen);
      final readBack = XiangqiPosition.fromFen(xiangqiFenExport(position));

      expect(xiangqiFenExport(readBack), _midgameFen);
      expect(readBack.turn, XiangqiSide.red);
      expect(readBack.fullmoveNumber, position.fullmoveNumber);
      expect(readBack.halfmoveClock, position.halfmoveClock);
      expect(readBack, position, reason: 'the board and the side to move are the same board');
    });

    test('it says the position, and not the line that led to it', () {
      // The one place a position and a line can be told apart: both are at the same point of the
      // same game, and the FEN is the same for both because a FEN does not remember how it got
      // here.
      final played = [
        XiangqiPosition.initial(),
        rules.play(XiangqiPosition.initial(), move('h2e2')),
      ];

      expect(xiangqiFenExport(played[1]), xiangqiFenExport(rules.play(played[0], move('h2e2'))));
      expect(xiangqiFenExport(played[0]), kXiangqiInitialFen);
      expect(xiangqiFenExport(played[1]), isNot(kXiangqiInitialFen));
    });
  });

  group('xiangqiIccsExport', () {
    test('writes a move list as space-separated ICCS', () {
      expect(xiangqiIccsExport(moves(['h2e2', 'h9g7', 'b0c2'])), 'h2e2 h9g7 b0c2');
    });

    test('an empty list is the empty string, and one move has no separator', () {
      expect(xiangqiIccsExport(const IListConst([])), '');
      expect(xiangqiIccsExport(moves(['h2e2'])), 'h2e2');
    });

    test('the list reads back as the same moves', () {
      final written = moves(['h2e2', 'h9g7', 'b0c2', 'g6g5']);

      expect(xiangqiIccsImport(xiangqiIccsExport(written)), written);
      expect(xiangqiIccsExport(const IListConst([])), '');
      expect(xiangqiIccsImport(''), isEmpty);
    });

    test('the parser takes any spacing, and the writer only ever makes one', () {
      final expected = moves(['h2e2', 'h9g7']);

      expect(xiangqiIccsImport('h2e2 h9g7'), expected);
      expect(xiangqiIccsImport('  h2e2   h9g7  '), expected);
      expect(xiangqiIccsImport('h2e2\nh9g7'), expected);
      expect(xiangqiIccsExport(expected), 'h2e2 h9g7');
    });

    test('a list that cannot be read back is refused rather than shortened', () {
      // Dropping what does not parse would turn a corrupt line into a shorter, wrong one, which is
      // the failure mode an export exists to prevent.
      expect(() => xiangqiIccsImport('h2e2 nope'), throwsFormatException);
      expect(() => xiangqiIccsImport('h2e2 z9z9'), throwsFormatException);
      expect(() => xiangqiIccsImport('e2'), throwsFormatException);
      expect(() => xiangqiIccsImport('H2E2'), throwsFormatException);
    });
  });

  group('xiangqiMovesExport', () {
    test('numbers a line the way a scoresheet does, one number to a whole move', () {
      final position = XiangqiPosition.initial();

      // 炮二平五 and 马8进7 are the two moves of the first turn: red's is written under the number
      // and black's is written beside it, with only the next number to separate the next turn.
      expect(xiangqiMovesExport(position, moves(['h2e2', 'h9g7', 'b0c2'])), '1. 炮二平五 马8进7 2. 马八进七');
      expect(xiangqiMovesExport(position, moves(['h2e2'])), '1. 炮二平五');
      expect(xiangqiMovesExport(position, moves(['h2e2', 'h9g7'])), '1. 炮二平五 马8进7');
    });

    test('it plays the moves through, so the notation knows what each one moved', () {
      final position = XiangqiPosition.initial();

      // 车九平八 can only be written by a notation that has already played 马八进七: the chariot it
      // names is on the file the horse left, and the horse was on it because of the move before.
      expect(
        xiangqiMovesExport(position, moves(['b0c2', 'h9g7', 'a0b0', 'g6g5'])),
        '1. 马八进七 马8进7 2. 车九平八 卒7进1',
      );
    });

    test('a line numbered from a position that is not the start of a game', () {
      final position = XiangqiPosition.fromFen(_midgameFen);

      // The number comes off the position rather than off a count kept here, so a line picked up in
      // the middle of a game is numbered the way the game it came from numbers it.
      expect(position.fullmoveNumber, 33);
      expect(xiangqiMovesExport(position, moves(['b0c2'])), '33. 马八进七');
    });

    test('a line that begins with black is written as a continuation', () {
      final position = XiangqiPosition.fromFen(_blackToMoveFen);

      // `1...` is a line that begins on the second player's turn: it cannot happen in a game, but an
      // engine's principal variation has no game behind it.
      expect(xiangqiMovesExport(position, moves(['h9g7'])), '1... 马8进7');
      expect(xiangqiMovesExport(position, moves(['h9g7', 'h2e2'])), '1... 马8进7 2. 炮二平五');
    });

    test('a tail the position cannot play is dropped, not thrown', () {
      final position = XiangqiPosition.initial();

      // An engine's variation is a guess at the future and its tail can be nonsense in a way the
      // engine never notices — 炮二平五 twice is the same cannon moving twice with no move between.
      // What is readable of the line is worth more than the whole of it or none of it.
      expect(xiangqiMovesExport(position, moves(['h2e2', 'h9g7', 'h2e2'])), '1. 炮二平五 马8进7');
      expect(xiangqiMovesExport(position, moves(['h2e2', 'h9g7', 'h2e2', 'g6g5'])), '1. 炮二平五 马8进7');
    });

    test('a line whose first move is unplayable is the empty string', () {
      final position = XiangqiPosition.initial();

      expect(xiangqiMovesExport(position, moves(['a0a9'])), '');
      expect(xiangqiMovesExport(position, const IListConst([])), '');
    });
  });

  group('xiangqiLineExport', () {
    test('writes the position first, then one whole move to a line', () {
      final position = XiangqiPosition.initial();
      final written = xiangqiLineExport(position, moves(['h2e2', 'h9g7', 'b0c2']));

      expect(written.split('\n'), [kXiangqiInitialFen, '1. 炮二平五 马8进7', '2. 马八进七']);
    });

    test('the first line is the position the rest of it is played from', () {
      final position = XiangqiPosition.fromFen(_midgameFen);
      final lines = xiangqiLineExport(position, moves(['b0c2', 'h9g7'])).split('\n');

      expect(XiangqiPosition.fromFen(lines.first), position);
      expect(lines.sublist(1), ['33. 马八进七 马8进7']);
    });

    test('a line with no moves in it is the position and nothing else', () {
      expect(
        xiangqiLineExport(XiangqiPosition.initial(), const IListConst([])),
        kXiangqiInitialFen,
      );
      expect(
        xiangqiLineExport(XiangqiPosition.initial(), const IListConst([])).split('\n'),
        hasLength(1),
      );
    });

    test('a black-to-move line says whose move its first move is', () {
      final position = XiangqiPosition.fromFen(_blackToMoveFen);
      final lines = xiangqiLineExport(position, moves(['h9g7'])).split('\n');

      expect(lines, [_blackToMoveFen, '1... 马8进7']);
      // The rendering is self-describing: the side to move is in the first line, so nothing reading
      // it has to be told separately whose move the first move is.
      expect(XiangqiPosition.fromFen(lines.first).turn, XiangqiSide.black);
    });
  });
}
