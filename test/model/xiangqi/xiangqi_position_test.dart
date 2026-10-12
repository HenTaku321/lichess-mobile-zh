import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

void main() {
  group('XiangqiSquare', () {
    test('names itself the way FEN and ICCS do', () {
      expect(const XiangqiSquare(0).name, 'a0');
      expect(const XiangqiSquare.at(8, 9).name, 'i9');
      expect(const XiangqiSquare.at(4, 2).name, 'e2');
    });

    test('parses every name it writes, and names every square it parses', () {
      for (var index = 0; index < kXiangqiSquares; index++) {
        final square = XiangqiSquare(index);
        expect(XiangqiSquare.parse(square.name), square, reason: square.name);
      }
    });

    test('refuses anything that is not a square', () {
      // `i9` is the last square and `a0` the first, so every one of these is off the end of a file,
      // of a rank, or of the board.
      for (final name in ['', 'a', 'A0', 'a10', '0a', 'z9', 'a:', 'i:', 'a-1']) {
        expect(XiangqiSquare.parse(name), isNull, reason: '"$name"');
      }
    });

    test('knows the palace and the river', () {
      // The palace is the three centre files of the side's own three back ranks.
      for (final name in ['d0', 'e0', 'f0', 'd2', 'e1']) {
        expect(XiangqiSquare.parse(name)!.inPalaceOf(.red), isTrue, reason: name);
        expect(XiangqiSquare.parse(name)!.inPalaceOf(.black), isFalse, reason: name);
      }
      for (final name in ['c0', 'g0', 'e3', 'd9']) {
        expect(XiangqiSquare.parse(name)!.inPalaceOf(.red), isFalse, reason: name);
      }
      for (final name in ['d9', 'e9', 'f9', 'd7']) {
        expect(XiangqiSquare.parse(name)!.inPalaceOf(.black), isTrue, reason: name);
      }

      // Red's half is ranks 0 to 4, black's 5 to 9: the river is the gap between 4 and 5, not a
      // square, which is why a soldier has crossed it exactly when it is not on its own half.
      expect(XiangqiSquare.parse('e4')!.onOwnHalf(.red), isTrue);
      expect(XiangqiSquare.parse('e5')!.onOwnHalf(.red), isFalse);
      expect(XiangqiSquare.parse('e5')!.onOwnHalf(.black), isTrue);
      expect(XiangqiSquare.parse('e4')!.onOwnHalf(.black), isFalse);
      expect(XiangqiSquare.parse('a0')!.onOwnHalf(.red), isTrue);
      expect(XiangqiSquare.parse('a9')!.onOwnHalf(.black), isTrue);
    });
  });

  group('XiangqiPiece', () {
    test('writes the FEN letter of its own side', () {
      expect(const XiangqiPiece(.red, .king).fenChar, 'K');
      expect(const XiangqiPiece(.black, .king).fenChar, 'k');
      expect(const XiangqiPiece(.red, .knight).fenChar, 'N');
      expect(const XiangqiPiece(.black, .pawn).fenChar, 'p');
    });

    test('reads back every letter it writes', () {
      for (final type in XiangqiPieceType.values) {
        for (final side in XiangqiSide.values) {
          final piece = XiangqiPiece(side, type);
          expect(XiangqiPiece.fromFenChar(piece.fenChar), piece);
        }
      }
    });

    test('is null for anything that is not a piece', () {
      for (final char in ['', 'x', '1', '/', 'KK']) {
        expect(XiangqiPiece.fromFenChar(char), isNull, reason: '"$char"');
      }
    });

    test('writes the two sides of each kind the way the board does', () {
      // Four of the seven kinds are written differently by the two sides, which is why the glyph
      // belongs to the piece and not to its kind.
      expect(const XiangqiPiece(.red, .king).glyph, '帅');
      expect(const XiangqiPiece(.black, .king).glyph, '将');
      expect(const XiangqiPiece(.red, .advisor).glyph, '仕');
      expect(const XiangqiPiece(.black, .advisor).glyph, '士');
      expect(const XiangqiPiece(.red, .bishop).glyph, '相');
      expect(const XiangqiPiece(.black, .bishop).glyph, '象');
      expect(const XiangqiPiece(.red, .pawn).glyph, '兵');
      expect(const XiangqiPiece(.black, .pawn).glyph, '卒');
      // The other three are written the same way by both.
      expect(const XiangqiPiece(.red, .knight).glyph, '马');
      expect(const XiangqiPiece(.black, .knight).glyph, '马');
      expect(const XiangqiPiece(.red, .rook).glyph, '车');
      expect(const XiangqiPiece(.black, .cannon).glyph, '炮');
    });
  });

  group('XiangqiPosition', () {
    test('the position it starts from parses, prints and reads back unchanged', () {
      final position = XiangqiPosition.initial();
      expect(position.toFen(), kXiangqiInitialFen);
      expect(XiangqiPosition.fromFen(kXiangqiInitialFen), position);
      expect(position.turn, XiangqiSide.red);
      expect(position.halfmoveClock, 0);
      expect(position.fullmoveNumber, 1);
    });

    test('the initial position holds the pieces each side starts with', () {
      final position = XiangqiPosition.initial();
      // Rooks in the corners, generals facing each other down the middle file.
      expect(position.pieceAt(XiangqiSquare.parse('a0')!), const XiangqiPiece(.red, .rook));
      expect(position.pieceAt(XiangqiSquare.parse('e0')!), const XiangqiPiece(.red, .king));
      expect(position.pieceAt(XiangqiSquare.parse('e9')!), const XiangqiPiece(.black, .king));
      expect(position.pieceAt(XiangqiSquare.parse('i9')!), const XiangqiPiece(.black, .rook));
      // The two cannons, each behind a rank of five soldiers.
      expect(position.pieceAt(XiangqiSquare.parse('b2')!), const XiangqiPiece(.red, .cannon));
      expect(position.pieceAt(XiangqiSquare.parse('h7')!), const XiangqiPiece(.black, .cannon));
      expect(position.pieceAt(XiangqiSquare.parse('a3')!), const XiangqiPiece(.red, .pawn));
      // And what is not there: the river's two empty ranks, and the middle of the back ranks.
      expect(position.pieceAt(XiangqiSquare.parse('e4')!), isNull);
      expect(position.pieceAt(XiangqiSquare.parse('e5')!), isNull);
      expect(position.pieceAt(XiangqiSquare.parse('a1')!), isNull);

      final pieces = position.board.whereType<XiangqiPiece>();
      expect(pieces.length, 32);
      expect(pieces.where((piece) => piece.side == .red).length, 16);
    });

    test('carries the move counters', () {
      final position = XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/9/4K4 b - - 7 42');
      expect(position.turn, XiangqiSide.black);
      expect(position.halfmoveClock, 7);
      expect(position.fullmoveNumber, 42);
      expect(position.toFen(), '4k4/9/9/9/9/9/9/9/9/4K4 b - - 7 42');
    });

    test('accepts a position that leaves the counters out', () {
      // The two chess-only fields are written as `-` by every xiangqi engine, and some of them stop
      // after the side to move.
      final position = XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/9/4K4 w');
      expect(position.halfmoveClock, 0);
      expect(position.fullmoveNumber, 1);
      expect(position.toFen(), '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1');
    });

    test('refuses anything that is not a board and a side', () {
      for (final fen in [
        '',
        '4k4 w',
        '9/9/9/9/9/9/9/9/9/9 x',
        '4k4/9/9/9/9/9/9/9/9/4x4 w',
        '4k4/9/9/9/9/9/9/9/9/5K2 w',
        '4k4/9/9/9/9/9/9/9/9/999 w',
      ]) {
        expect(() => XiangqiPosition.fromFen(fen), throwsFormatException, reason: '"$fen"');
      }
    });

    test('two positions are the same position whatever move they were reached on', () {
      // The counters are not part of the position: the repetition rule counts how often a position
      // has been *seen*, and a position does not become a different one by being reached later.
      final earlier = XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1');
      final later = XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/9/4K4 w - - 40 61');
      expect(later, earlier);
      expect(later.hashCode, earlier.hashCode);
      // Whose turn it is, on the other hand, is the position.
      expect(XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/9/4K4 b - - 0 1'), isNot(earlier));
    });
  });
}
