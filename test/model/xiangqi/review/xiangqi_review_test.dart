// Tests for reading a review, and for the one thing in it this app computes rather than reads.
//
// The classification is the app's own arithmetic on the server's numbers, so it is the part of this
// domain that most needs pinning: the thresholds and the win-rate curve are the shipped client's,
// taken out of its bundle (`xiangqi-com-re/docs/review.md` has the module), and every case below is
// a value that curve really produces rather than a value chosen to make a test pass.
//
// The values here are all invented. The captures the shapes come from are in
// `xiangqi-com-re/captures/review/`.

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/review/xiangqi_review.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart' show XiangqiEvaluation;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

XiangqiMove move(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

void main() {
  group('the score a classification is computed from', () {
    test('is the centipawn score, clamped to the bound the mate scores start at', () {
      expect(xiangqiReviewScore(const XiangqiEvaluation(cp: 65)), 65);
      expect(xiangqiReviewScore(const XiangqiEvaluation(cp: -38)), -38);
      expect(xiangqiReviewScore(const XiangqiEvaluation(cp: 9999)), 5000);
      expect(xiangqiReviewScore(const XiangqiEvaluation(cp: -9999)), -5000);
    });

    test('is worth more than any centipawn score when it is a mate', () {
      // 100 * (60 - min(10, |mate|)): a mate in one is 5900 and a mate in ten or more is 5000, so
      // every mate outranks every centipawn score, which is clamped to 5000.
      expect(xiangqiReviewScore(const XiangqiEvaluation(mate: 1)), 5900);
      expect(xiangqiReviewScore(const XiangqiEvaluation(mate: -1)), -5900);
      expect(xiangqiReviewScore(const XiangqiEvaluation(mate: 10)), 5000);
      expect(xiangqiReviewScore(const XiangqiEvaluation(mate: 40)), 5000);
    });
  });

  group('the win rate', () {
    test('is 50 at level and saturates at the ends rather than reaching them', () {
      expect(xiangqiWinRate(0), 50);
      expect(xiangqiWinRate(5000), greaterThan(99));
      expect(xiangqiWinRate(5000), lessThan(100));
      expect(xiangqiWinRate(-5000), lessThan(1));
      expect(xiangqiWinRate(-5000), greaterThan(0));
    });

    test('is symmetric about level', () {
      for (final score in [50, 200, 1000]) {
        expect(xiangqiWinRate(score) + xiangqiWinRate(-score), closeTo(100, 0.0001));
      }
    });
  });

  group('the accuracy of a move', () {
    test('is 100 for a move that lost nothing, and never below 1', () {
      expect(xiangqiMoveAccuracy(before: 50, after: 50), 100);
      expect(xiangqiMoveAccuracy(before: 50, after: 80), 100);
      // The curve goes negative well before the loss reaches 100 points, and the floor is what
      // stops a move that threw the game away from being worth less than nothing.
      expect(xiangqiMoveAccuracy(before: 50, after: 0), 9);
      expect(xiangqiMoveAccuracy(before: 50, after: -50), 1);
    });

    test("is the shipped client's curve of what the move gave up", () {
      // 103.1668 * exp(-0.04354 * loss) - 3.1669, rounded. These are that curve's own values.
      expect(xiangqiMoveAccuracy(before: 50, after: 40), 64);
      expect(xiangqiMoveAccuracy(before: 60, after: 45), 51);
      expect(xiangqiMoveAccuracy(before: 63.4, after: 36.6), 29);
    });
  });

  group('the seven names', () {
    test("are read off the shipped client's own thresholds", () {
      // 99.9, 91, 80, 63 and 40, each an exclusive bound.
      expect(xiangqiMoveClassificationOf(100), XiangqiMoveClassification.best);
      expect(xiangqiMoveClassificationOf(99), XiangqiMoveClassification.excellent);
      expect(xiangqiMoveClassificationOf(92), XiangqiMoveClassification.excellent);
      expect(xiangqiMoveClassificationOf(91), XiangqiMoveClassification.good);
      expect(xiangqiMoveClassificationOf(81), XiangqiMoveClassification.good);
      expect(xiangqiMoveClassificationOf(80), XiangqiMoveClassification.inaccuracy);
      expect(xiangqiMoveClassificationOf(64), XiangqiMoveClassification.inaccuracy);
      expect(xiangqiMoveClassificationOf(63), XiangqiMoveClassification.mistake);
      expect(xiangqiMoveClassificationOf(41), XiangqiMoveClassification.mistake);
      expect(xiangqiMoveClassificationOf(40), XiangqiMoveClassification.blunder);
      expect(xiangqiMoveClassificationOf(1), XiangqiMoveClassification.blunder);
    });

    test('never reach brilliant, which this app does not award', () {
      // The shipped client only gets there through a second, cloud-side verification, and a name
      // this app cannot justify is a name it does not print.
      for (var accuracy = 1; accuracy <= 100; accuracy++) {
        expect(
          xiangqiMoveClassificationOf(accuracy),
          isNot(XiangqiMoveClassification.brilliant),
          reason: 'accuracy $accuracy',
        );
      }
    });
  });

  group('the review of one move', () {
    test('is a best move when the position is left as good as it was found', () {
      final review = xiangqiMoveReviewOf(
        ply: 0,
        move: move('h2e2'),
        before: const XiangqiEvaluation(cp: 100),
        after: const XiangqiEvaluation(cp: 100),
      );
      expect(review.classification, XiangqiMoveClassification.best);
      expect(review.accuracy, 100);
      expect(review.side, XiangqiSide.red);
    });

    test('is a blunder when the move gives the game away', () {
      final review = xiangqiMoveReviewOf(
        ply: 0,
        move: move('h2e2'),
        before: const XiangqiEvaluation(cp: 500),
        after: const XiangqiEvaluation(cp: -500),
      );
      expect(review.classification, XiangqiMoveClassification.blunder);
      expect(review.accuracy, lessThan(40));
    });

    test("reads the two evaluations from the mover's side, not from red's", () {
      // The same swing is the same verdict whoever made it: red going from +500 to -500 and black
      // going from -500 to +500 are one and the same loss of the position.
      final asRed = xiangqiMoveReviewOf(
        ply: 0,
        move: move('h2e2'),
        before: const XiangqiEvaluation(cp: 500),
        after: const XiangqiEvaluation(cp: -500),
      );
      final asBlack = xiangqiMoveReviewOf(
        ply: 1,
        move: move('h9g7'),
        before: const XiangqiEvaluation(cp: -500),
        after: const XiangqiEvaluation(cp: 500),
      );
      expect(asBlack.accuracy, asRed.accuracy);
      expect(asBlack.classification, asRed.classification);
      expect(asBlack.side, XiangqiSide.black);
    });

    test('carries the best move and the depth the verdict was reached at', () {
      final review = xiangqiMoveReviewOf(
        ply: 0,
        move: move('h2e2'),
        before: const XiangqiEvaluation(cp: 0),
        after: const XiangqiEvaluation(cp: -300),
        bestMove: move('h0g2'),
        depth: 16,
      );
      expect(review.bestMove, move('h0g2'));
      expect(review.depth, 16);
    });
  });

  group('the reviews of a whole game', () {
    test('are one per move, each read from the two verdicts that bracket it', () {
      final moves = IList([move('h2e2'), move('h9g7')]);
      final reviews = xiangqiMoveReviewsFromAnalysis(
        moves: moves,
        // Three verdicts for two moves: one per position, the last of which has no move after it.
        evaluations: IList(const [
          XiangqiEvaluation(cp: 0),
          XiangqiEvaluation(cp: 0),
          // The evaluation of the last position, in red's point of view: red is winning outright,
          // which is exactly what black's move handed over.
          XiangqiEvaluation(cp: 5000),
        ]),
        bestMoves: IList([move('h2e2'), move('h9g7')]),
        depths: IList(const [16, 16]),
      );

      expect(reviews.length, 2);
      expect(reviews[0].classification, XiangqiMoveClassification.best);
      expect(reviews[1].classification, XiangqiMoveClassification.blunder);
      expect(reviews[0].ply, 0);
      expect(reviews[1].ply, 1);
    });

    test('are none at all when the verdicts do not match the moves', () {
      // Half a review is worse than none: it would mark up a game that is not the one on the board.
      expect(
        xiangqiMoveReviewsFromAnalysis(
          moves: IList([move('h2e2')]),
          evaluations: IList(const [XiangqiEvaluation(cp: 0)]),
          bestMoves: IList([move('h2e2')]),
          depths: IList(const [16]),
        ),
        isEmpty,
      );
    });
  });

  group('the moves of a snapshot', () {
    test('are read from the first token of each history entry', () {
      // A `move_history` entry is `"h3e3 885/120 900/120 20"`: the UCI, then the clock readings.
      final moves = xiangqiReviewMovesFromHistory(const [
        'h3e3 885/120 900/120 20',
        'h10g8 885/120 901/120 4',
      ]);
      expect(moves, isNotNull);
      expect(moves!.map((m) => m), [move('h2e2'), move('h9g7')]);
    });

    test('are none when an entry is not a move', () {
      expect(xiangqiReviewMovesFromHistory(const ['h3e3 1/2 3/4 5', 'nonsense']), isNull);
      expect(xiangqiReviewMovesFromHistory(const [42]), isNull);
      expect(xiangqiReviewMovesFromHistory(null), isNull);
    });
  });

  group('the positions of a game', () {
    test('are one per move, plus the one it started from', () {
      final initial = XiangqiPosition.initial();
      final positions = xiangqiReviewPositions(initial, IList([move('h2e2'), move('h9g7')]));
      expect(positions, isNotNull);
      expect(positions!.length, 3);
      expect(positions.first.toFen(), initial.toFen());
    });

    test('are none when a move does not fit the position it is played in', () {
      final initial = XiangqiPosition.initial();
      // A black horse cannot move on red's turn.
      expect(xiangqiReviewPositions(initial, IList([move('h9g7')])), isNull);
    });
  });

  group('a whole review', () {
    final review = XiangqiReview(
      gameId: 'AbCdEf1234',
      initialPosition: XiangqiPosition.initial(),
      positions: IList([XiangqiPosition.initial(), XiangqiPosition.initial()]),
      evaluations: const IListConst([XiangqiEvaluation(cp: 100), XiangqiEvaluation(cp: 100)]),
      moves: IList([move('h2e2')]),
      reviews: IList([
        xiangqiMoveReviewOf(
          ply: 0,
          move: move('h2e2'),
          before: const XiangqiEvaluation(cp: 100),
          after: const XiangqiEvaluation(cp: 100),
        ),
      ]),
    );

    test('has an accuracy for the side that moved, and none for the side that did not', () {
      expect(review.accuracyOf(XiangqiSide.red), 100);
      expect(review.accuracyOf(XiangqiSide.black), isNull);
    });

    test('counts the moves that fell in each name', () {
      expect(review.countOf(XiangqiSide.red, XiangqiMoveClassification.best), 1);
      expect(review.countOf(XiangqiSide.red, XiangqiMoveClassification.blunder), 0);
      expect(review.countOf(XiangqiSide.black, XiangqiMoveClassification.best), 0);
    });
  });
}
