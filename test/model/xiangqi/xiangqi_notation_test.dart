import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';

/// The position the moves [iccs] lead to, played from the initial position so that every position
/// here is one the rules reach and not one written by hand.
XiangqiPosition after(List<String> iccs) {
  var position = XiangqiPosition.initial();
  for (final move in iccs) {
    position = play(position, XiangqiMove.parseIccs(move)!);
  }
  return position;
}

/// [iccs] played in [position], written the way a move list writes it.
String notation(XiangqiPosition position, String iccs) =>
    xiangqiMoveNotation(position, XiangqiMove.parseIccs(iccs)!);

void main() {
  group('the file numbering', () {
    test("runs from each side's own right, and the two sides start at opposite ends", () {
      // The board's files are a to i left to right as red sees it, so red's own right — where its
      // counting starts — is the i file, 8, and its 一 is there. Black sits opposite and counts
      // from its own right, which is the a file, 0.
      expect(xiangqiFileDigit(.red, 8), '一');
      expect(xiangqiFileDigit(.red, 4), '五');
      expect(xiangqiFileDigit(.red, 0), '九');
      expect(xiangqiFileDigit(.black, 0), '1');
      expect(xiangqiFileDigit(.black, 4), '5');
      expect(xiangqiFileDigit(.black, 8), '9');
    });

    test('is not what a count of ranks is: a count is a number and is read in plain order', () {
      expect(xiangqiNumberDigit(.red, 1), '一');
      expect(xiangqiNumberDigit(.red, 6), '六');
      expect(xiangqiNumberDigit(.black, 1), '1');
      expect(xiangqiNumberDigit(.black, 7), '7');
    });
  });

  group('the moves a game opens with', () {
    test('names each piece the way the board draws it, red and black apart', () {
      // 炮二平五: the cannon on red's second file, across to the middle file. The initial position
      // has red to move, so the position before the move is the initial one itself.
      expect(notation(XiangqiPosition.initial(), 'h2e2'), '炮二平五');
      // 马8进7: black's answer, so the position before it is the one after red's move.
      expect(notation(after(['h2e2']), 'h9g7'), '马8进7');
      // 车九平八: the left chariot one file across, once the horse in front of it has gone.
      expect(notation(after(['b0c2', 'h9g7']), 'a0b0'), '车九平八');
      // 卒7进1: a black soldier, counted from black's own right.
      expect(notation(after(['h2e2']), 'g6g5'), '卒7进1');
      // 兵七进一: the soldier on red's seventh file, and the two other ways the back rank opens.
      expect(notation(XiangqiPosition.initial(), 'c3c4'), '兵七进一');
      expect(notation(XiangqiPosition.initial(), 'h0g2'), '马二进三');
      expect(notation(XiangqiPosition.initial(), 'g0e2'), '相三进五');
      expect(notation(XiangqiPosition.initial(), 'f0e1'), '仕四进五');
    });

    test('writes a piece that keeps to its file by how far it went, not where it landed', () {
      // A chariot and a cannon each alone on the h file with a clear run, so the move is a plain
      // advance: 车二进六 is six ranks, 炮二进七 seven. The count is the side's own number, so red
      // writes 六 and 七.
      const rookFile = '4k4/9/9/9/9/9/9/9/9/4K2R1 w - - 0 1';
      expect(notation(XiangqiPosition.fromFen(rookFile), 'h0h6'), '车二进六');

      const cannonFile = '4k4/9/9/9/9/9/9/7C1/9/4K4 w - - 0 1';
      expect(notation(XiangqiPosition.fromFen(cannonFile), 'h2h9'), '炮二进七');
    });

    test('says 退 when the piece comes back towards its own side', () {
      // The same chariot on the h file, stepping down two ranks instead of up: 退 and the number.
      const rookFile = '4k4/9/9/9/9/9/7R1/9/9/4K4 w - - 0 1';
      expect(notation(XiangqiPosition.fromFen(rookFile), 'h3h1'), '车二退二');
    });
  });

  group('two or more of a piece on one file', () {
    test('drops the file and names the piece by where it stands, 前 and 后', () {
      // Two red cannons on the c file, one above the other. 前 is the one nearer black, so the c6
      // cannon is 前炮 and the c2 one 后炮, and neither says "c" — it would not tell them apart.
      const twoCannons = '4k4/9/9/2C6/9/9/9/2C6/9/4K4 w - - 0 1';
      expect(notation(XiangqiPosition.fromFen(twoCannons), 'c6e6'), '前炮平五');
      expect(notation(XiangqiPosition.fromFen(twoCannons), 'c2e2'), '后炮平五');
    });

    test("a third on the file is 中, the soldier's own way of writing three", () {
      // Three red soldiers stacked on the e file: 前兵 is the one furthest up, 后兵 the one at home
      // and 中兵 the one between.
      const threeSoldiers = '4k4/9/9/9/4P4/4P4/4P4/9/9/4K4 w - - 0 1';
      expect(notation(XiangqiPosition.fromFen(threeSoldiers), 'e5e6'), '前兵进一');
      expect(notation(XiangqiPosition.fromFen(threeSoldiers), 'e4e5'), '中兵进一');
      expect(notation(XiangqiPosition.fromFen(threeSoldiers), 'e3e4'), '后兵进一');
    });

    test('four or more number the ones between 前 and 后, which only soldiers can be', () {
      // A side has five soldiers and may bring them all to one file; a file never holds more than
      // ten pieces. Four are 前, 二, 三, 后 here, and the middle two are counted from 前.
      const fourSoldiers = '4k4/9/9/9/4P4/4P4/4P4/4P4/9/4K4 w - - 0 1';
      expect(notation(XiangqiPosition.fromFen(fourSoldiers), 'e5e6'), '前兵进一');
      expect(notation(XiangqiPosition.fromFen(fourSoldiers), 'e4e5'), '二兵进一');
      expect(notation(XiangqiPosition.fromFen(fourSoldiers), 'e3e4'), '三兵进一');
      expect(notation(XiangqiPosition.fromFen(fourSoldiers), 'e2e3'), '后兵进一');
    });
  });

  group('xiangqiGameNotation', () {
    test('writes every move of a game against the position it was played in', () {
      const iccs = ['b0c2', 'h9g7', 'a0b0', 'g6g5', 'h2e2'];
      final moves = [for (final move in iccs) XiangqiMove.parseIccs(move)!];
      final positions = <XiangqiPosition>[XiangqiPosition.initial()];
      for (final move in moves) {
        positions.add(play(positions.last, move));
      }

      final game = xiangqiGameNotation(positions.lock, moves.lock);
      expect(game.toList(), ['马八进七', '马8进7', '车九平八', '卒7进1', '炮二平五']);
    });

    test('an opening with no moves is an empty list, and nothing else is one', () {
      expect(xiangqiGameNotation([XiangqiPosition.initial()].lock, const IListConst([])), isEmpty);

      final position = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('h2e2')!;
      // A move with no position to read it against, and a position with no move to write.
      expect(() => xiangqiGameNotation(const IListConst([]), [move].lock), throwsArgumentError);
      expect(() => xiangqiGameNotation([position].lock, const IListConst([])), returnsNormally);
      expect(() => xiangqiGameNotation([position, position].lock, [move].lock), returnsNormally);
      expect(() => xiangqiGameNotation([position].lock, [move].lock), throwsArgumentError);
    });
  });

  group('a move that is not a move', () {
    test('comes back empty rather than throwing', () {
      final position = XiangqiPosition.initial();
      // From and to the same square.
      expect(
        xiangqiMoveNotation(
          position,
          XiangqiMove(XiangqiSquare.parse('e0')!, XiangqiSquare.parse('e0')!),
        ),
        '',
      );
      // Nothing on the square the move starts from.
      expect(
        xiangqiMoveNotation(
          position,
          XiangqiMove(XiangqiSquare.parse('e4')!, XiangqiSquare.parse('e5')!),
        ),
        '',
      );
      // A piece that belongs to the side that is not moving: the black general, with red to move.
      expect(
        xiangqiMoveNotation(
          position,
          XiangqiMove(XiangqiSquare.parse('e9')!, XiangqiSquare.parse('e8')!),
        ),
        '',
      );
    });
  });
}
