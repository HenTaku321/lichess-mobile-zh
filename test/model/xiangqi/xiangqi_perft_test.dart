import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';

/// perft — walking the move tree to a fixed depth and counting its leaves — with Pikafish as the
/// reference.
///
/// The reference binary is Pikafish `dev-20261012-nogit`, built from the snapshot vendored into the
/// fork's `multistockfish_pikafish` package, run next to the `pikafish.nnue` it was built against.
/// Every number asserted here is what these commands printed, and not one of them is remembered
/// from a perft table:
///
/// ```text
/// printf 'position startpos\ngo perft <n>\nquit\n' | ./pikafish
/// printf 'position startpos moves h2e2 h9g7 h0g2 i9h9 i0h0\ngo perft 3\nquit\n' | ./pikafish
/// printf 'position startpos moves b2b9 a9b9\ngo perft 3\nquit\n' | ./pikafish
/// printf 'position fen 4k4/9/9/9/9/9/9/9/4r4/R3K4 w - - 0 1\ngo perft 3\nquit\n' | ./pikafish
/// ```
///
/// Pikafish needs its network file to run a perft at all — it verifies the network before it
/// enters the counter and exits with an error block if it is missing — so the file has to be in the
/// directory the binary runs from.
///
/// The opening position's five depths are split over two tests because the fifth one is a different
/// order of cost: 133,312,995 nodes take Pikafish 1.7 s and this rules engine about 9 s, where the
/// four below it together are under a second. Everything the two agree on is in the one file, and
/// the expensive assert stands alone so that it can be found and skipped if it ever has to be.
void main() {
  group('the opening position', () {
    test('counts the nodes Pikafish counts, to depth 4', () {
      final position = XiangqiPosition.initial();
      expect(perft(position, 1), 44);
      expect(perft(position, 2), 1920);
      expect(perft(position, 3), 79666);
      expect(perft(position, 4), 3290240);
    });

    test('counts 133312995 nodes at depth 5, the number xiangqi perft tables quote', () {
      expect(perft(XiangqiPosition.initial(), 5), 133312995);
    });
  });

  group('a quiet developing line', () {
    test('counts 38, 1417 and 53611 nodes after five plies', () {
      // Cannons to the middle, horses out, chariots to their general's file: the position is still
      // balanced, but the counting is not, because the horses and the chariots have opened files
      // the cannons had closed.
      var position = XiangqiPosition.initial();
      for (final iccs in ['h2e2', 'h9g7', 'h0g2', 'i9h9', 'i0h0']) {
        position = play(position, XiangqiMove.parseIccs(iccs)!);
      }
      expect(perft(position, 1), 38);
      expect(perft(position, 2), 1417);
      expect(perft(position, 3), 53611);
    });
  });

  group('an exchange in the corner', () {
    test(
      'counts 34, 1457 and 46642 nodes after a cannon takes a horse and a chariot recaptures',
      () {
        // Two captures leave both sides with one cannon fewer, and a chariot standing on b9 where a
        // horse began.
        var position = XiangqiPosition.initial();
        for (final iccs in ['b2b9', 'a9b9']) {
          position = play(position, XiangqiMove.parseIccs(iccs)!);
        }
        expect(perft(position, 1), 34);
        expect(perft(position, 2), 1457);
        expect(perft(position, 3), 46642);
      },
    );
  });

  group('a general in check', () {
    test('counts 2, 36 and 387 nodes from a position that is not even reachable', () {
      // A chariot checks the general down the file, the black general behind it on the same file
      // so that it cannot be taken, and a red chariot in the corner to give the two replies
      // something to have to answer a move later. The counts fall away because both sides have to
      // deal with the chariot every ply.
      final position = XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/4r4/R3K4 w - - 0 1');
      expect(perft(position, 1), 2);
      expect(perft(position, 2), 36);
      expect(perft(position, 3), 387);
    });
  });
}
