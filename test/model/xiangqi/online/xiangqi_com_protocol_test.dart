import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

XiangqiMove iccsMove(String iccs) {
  final parsed = XiangqiMove.parseIccs(iccs);
  if (parsed == null) throw ArgumentError.value(iccs, 'iccs', 'not an ICCS move');
  return parsed;
}

void main() {
  group('xiangqiMoveFromComUci', () {
    // The two moves the live server was actually seen to carry, both from the opening position.
    // `h3e3` is the red cannon on h1 (xiangqi.com counts) going to e1; the same cannon in this
    // repo's counting sits on h2 and goes to e2. `h10g8` is black's left horse off the back rank.
    test('translates the rank the server writes to the one this repo counts from', () {
      expect(xiangqiMoveFromComUci('h3e3'), iccsMove('h2e2'));
      expect(xiangqiMoveFromComUci('h10g8'), iccsMove('h9g7'));
    });

    test('reads the ten-rank file, where a file letter is followed by two digits', () {
      // Every move that starts or ends on black's back rank is five characters long, not four.
      // A `length == 4` parse would reject all of these.
      expect(xiangqiMoveFromComUci('a10a9'), iccsMove('a9a8'));
      expect(xiangqiMoveFromComUci('e10e9'), iccsMove('e9e8'));
      expect(xiangqiMoveFromComUci('i10i9'), iccsMove('i9i8'));
      expect(xiangqiMoveFromComUci('a1a10'), iccsMove('a0a9'));
      expect(xiangqiMoveFromComUci('i1i10'), iccsMove('i0i9'));
      expect(xiangqiMoveFromComUci('e2e10'), iccsMove('e1e9'));
    });

    test('covers every square of the board, in both directions', () {
      // The rank offset is the whole of this file, so it is tested over the whole board rather
      // than over the handful of moves anybody happened to observe.
      for (var from = 0; from < kXiangqiSquares; from++) {
        for (var to = 0; to < kXiangqiSquares; to++) {
          final repoMove = XiangqiMove(XiangqiSquare(from), XiangqiSquare(to));
          final comUci = xiangqiMoveToComUci(repoMove);
          expect(xiangqiMoveFromComUci(comUci), repoMove, reason: 'round trip through "$comUci"');
        }
      }
    });

    test('is not the same notation as ICCS, and says so', () {
      // The trap this file exists to catch: fed a repo ICCS string, the parser does not fail, it
      // returns a *different* move one rank too low. `h2e2` reads as file h, rank 2 (xiangqi.com's
      // rank 2, which is this repo's rank 1) — so it comes back as `h1e1`, quietly wrong.
      expect(xiangqiMoveFromComUci('h2e2'), iccsMove('h1e1'));
      expect(xiangqiMoveFromComUci('h2e2'), isNot(iccsMove('h2e2')));
    });

    test('refuses anything that is not two squares', () {
      for (final uci in [
        '',
        ' ',
        'h',
        'h3',
        'h3e',
        'h33',
        'hh3e3',
        'j3e3', // no file after i
        'H3E3', // the server writes lower case
        'h0e3', // rank 0 is not a xiangqi.com rank
        'h11e3', // and neither is 11
        'a99a98', // three digits are never a rank
        'h3e3x', // trailing junk
        'h3e3 h9g7', // one move, not two
      ]) {
        expect(xiangqiMoveFromComUci(uci), isNull, reason: '"$uci"');
      }
    });

    test('tolerates the whitespace a split token may carry', () {
      // Callers take the first whitespace-separated token of a `move_history` entry, and a
      // `split` on a string with leading space leaves an empty first token; trimming keeps that
      // from turning into a null move.
      expect(xiangqiMoveFromComUci(' h3e3 '), iccsMove('h2e2'));
      expect(xiangqiMoveFromComUci('\th3e3\n'), iccsMove('h2e2'));
    });
  });

  group('xiangqiMoveToComUci', () {
    test('writes the rank one above the one this repo counts', () {
      expect(xiangqiMoveToComUci(iccsMove('h2e2')), 'h3e3');
      expect(xiangqiMoveToComUci(iccsMove('h9g7')), 'h10g8');
    });

    test('writes exactly four characters, except on the tenth rank', () {
      // The length is what makes this worth asserting: `XiangqiSquare.name` spells file and rank
      // together, so the obvious `"${square.name}$comRank"` writes `h23` for the square this repo
      // calls h2. It is five characters either way, and only one of them is a move.
      expect(xiangqiMoveToComUci(iccsMove('a0a1')), hasLength(4));
      expect(xiangqiMoveToComUci(iccsMove('a0a1')), 'a1a2');
      expect(xiangqiMoveToComUci(iccsMove('a9a8')), hasLength(5));
      expect(xiangqiMoveToComUci(iccsMove('a9a8')), 'a10a9');
    });

    test('never writes a rank zero, which xiangqi.com does not have', () {
      final rankPattern = RegExp(r'[a-i](\d+)');
      for (var index = 0; index < kXiangqiSquares; index++) {
        final square = XiangqiSquare(index);
        final written = xiangqiMoveToComUci(XiangqiMove(square, square));
        final ranks = rankPattern
            .allMatches(written)
            .map((match) => int.parse(match.group(1)!))
            .toList();
        expect(ranks, hasLength(2), reason: written);
        for (final rank in ranks) {
          expect(rank, inInclusiveRange(1, 10), reason: '${square.name} written as $written');
        }
      }
    });

    test('writes every square the parser can read back', () {
      for (var index = 0; index < kXiangqiSquares; index++) {
        final square = XiangqiSquare(index);
        final written = xiangqiMoveToComUci(XiangqiMove(square, square));
        expect(xiangqiMoveFromComUci(written), XiangqiMove(square, square), reason: written);
      }
    });
  });
}
