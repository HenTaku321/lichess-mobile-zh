import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
// `$XiangqiEvaluationCopyWith` is freezed's own generated type and is named here for the same
// reason `XiangqiEvaluation` is: [XiangqiMoveReview] holds an evaluation, and the `copyWith` freezed
// writes for that field is written in terms of this type. A `show` clause hides it along with
// everything else it does not name, and the generated code then does not compile.
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart'
    show $XiangqiEvaluationCopyWith, XiangqiEvaluation;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:logging/logging.dart';

part 'xiangqi_review.freezed.dart';

final _logger = Logger('XiangqiReview');

/// How good a move was, on xiangqi.com's own scale.
///
/// The seven names are the shipped client's, and so are the thresholds between them — see
/// [xiangqiMoveClassificationOf], which is where the numbers are written down. The order of the
/// values is the order of the scale, best first, which is the order a legend lists them in.
enum XiangqiMoveClassification() {
  brilliant,
  best,
  excellent,
  good,
  inaccuracy,
  mistake,
  blunder;

  /// Whether this is one of the two the app draws as a *good* move.
  bool get isGood => index <= XiangqiMoveClassification.best.index;
}

/// One ply of a review: the move that was played, and what the engine made of it.
@freezed
sealed class const XiangqiMoveReview._() with _$XiangqiMoveReview {
  const factory({
    /// Which ply this is, counted from zero. Red plays the even ones.
    required int ply,

    /// The move that was played.
    required XiangqiMove move,

    /// The engine's verdict on the position **before** the move, in red's point of view.
    required XiangqiEvaluation evaluation,

    /// How good the move was.
    required XiangqiMoveClassification classification,

    /// How much of the position's win rate the move kept, 1 to 100.
    ///
    /// The same number the classification is read from, kept because a list of seven names loses
    /// the difference between a move that just missed and one that was nowhere near.
    required int accuracy,

    /// What the engine would have played instead, or null when the server did not say.
    XiangqiMove? bestMove,

    /// The depth the verdict was reached at.
    @Default(0) int depth,
  }) = _XiangqiMoveReview;

  /// Which side played this move.
  XiangqiSide get side => ply.isEven ? XiangqiSide.red : XiangqiSide.black;
}

/// A finished game, with every move of it marked up.
///
/// The whole of what the review screen draws: the game as the socket's snapshot describes it, and
/// one [XiangqiMoveReview] per move. There is no separate "is the analysis ready" state because the
/// server answers the whole analysis in one frame — see `xiangqi-com-re/docs/review.md` — so a
/// review that exists is a review that is complete.
@freezed
sealed class const XiangqiReview._() with _$XiangqiReview {
  const factory({
    required String gameId,

    /// The position the game started from.
    required XiangqiPosition initialPosition,

    /// Every position of the game: `positions[i]` is the position before `moves[i]` was played, so
    /// this is one longer than [moves] and `positions.last` is the final position.
    required IList<XiangqiPosition> positions,

    /// Every move of the game, in order.
    required IList<XiangqiMove> moves,

    /// One entry per move, in the same order.
    required IList<XiangqiMoveReview> reviews,

    /// The player of the red pieces, or null when the snapshot did not name one.
    XiangqiLivePlayer? red,

    /// The player of the black pieces, or null when the snapshot did not name one.
    XiangqiLivePlayer? black,

    /// xiangqi.com's own end-reason code, or null when the snapshot did not carry one.
    int? endReason,

    /// When the game ended, or null when the snapshot did not say.
    DateTime? endedAt,
  }) = _XiangqiReview;

  /// The mean accuracy of [side]'s moves, or null when they played none.
  ///
  /// A plain mean of the per-move accuracies, rounded. The server's own `accuracy` field is a
  /// different number computed a way this app does not reproduce — see `docs/review.md` — so this
  /// is the app's own reading of its own per-move numbers and is labelled as such on the screen.
  int? accuracyOf(XiangqiSide side) {
    final mine = reviews.where((review) => review.side == side).toList();
    if (mine.isEmpty) return null;
    final total = mine.fold<int>(0, (sum, review) => sum + review.accuracy);
    return (total / mine.length).round();
  }

  /// How many of [side]'s moves fell in [classification].
  int countOf(XiangqiSide side, XiangqiMoveClassification classification) => reviews
      .where((review) => review.side == side && review.classification == classification)
      .length;
}

/// The score [evaluation] is worth, in centipawns, on the scale the classification is computed on.
///
/// A mate is worth more than any centipawn score: the shipped client maps it to
/// `100 * (60 - min(10, |mate|))`, so a mate in one is 5900 and a mate in ten or more is 5000, and
/// the sign is the mating side's. Everything else is the centipawn score clamped to ±5000, which is
/// the same bound the mate scores start at — see [kXiangqiCompletelyWinningCp].
int xiangqiReviewScore(XiangqiEvaluation evaluation) {
  final mate = evaluation.mate;
  if (mate != null) {
    // `math.min` is generic over `num`, and a literal and an `int` do not pin it to `int` on their
    // own: the bound is written as an `int` for that reason and the product is taken as one.
    final reach = mate.abs() < 10 ? mate.abs() : 10;
    return 100 * (60 - reach) * (mate > 0 ? 1 : -1);
  }
  final cp = evaluation.cp ?? 0;
  if (cp > kXiangqiCompletelyWinningCp) return kXiangqiCompletelyWinningCp;
  if (cp < -kXiangqiCompletelyWinningCp) return -kXiangqiCompletelyWinningCp;
  return cp;
}

/// The score above which the shipped client stops treating a position as one to be won.
///
/// `f.j` in its bundle. It is also the bound a centipawn score is clamped to, so a position is
/// "completely winning" exactly when it is a mate — which is what the branch in
/// [xiangqiMoveClassificationOf] is for.
const int kXiangqiCompletelyWinningCp = 5000;

/// How likely the side holding [score] is to win, as a percentage.
///
/// The shipped client's own curve, `O(x) = 50 + 50 * (2 / (1 + exp(-0.0011 * x)) - 1)`: 0
/// centipawns is 50, and the curve saturates at 0 and 100 rather than ever reaching them.
double xiangqiWinRate(int score) => 50 + 50 * (2 / (1 + math.exp(-0.0011 * score)) - 1);

/// How much of the win rate a move kept, 1 to 100.
///
/// [before] and [after] are the win rates of the **same side** — the one that moved — before and
/// after the move, so a move that improved the position loses nothing and scores 100. The curve is
/// the shipped client's, `103.1668 * exp(-0.04354 * loss) - 3.1669`, and it is the one thing here
/// that is quoted rather than derived: it is what puts the thresholds below where they are.
///
/// The losses it turns into the seven names: nothing lost is a best move, ten points is an
/// inaccuracy, twenty is a mistake and thirty is a blunder.
int xiangqiMoveAccuracy({required double before, required double after}) {
  final loss = math.max(0.0, before - after);
  final value = (103.1668 * math.exp(-0.04354 * loss) - 3.1669).round();
  return math.max(1, value);
}

/// The name [accuracy] earns, on the shipped client's own thresholds.
///
/// Its bundle spells them `I`, `k`, `C`, `q` and `P`: 99.9, 91, 80, 63 and 40, each an exclusive
/// bound. Read out, a move that lost nothing at all is a **best** move, one that gave up ten
/// win-rate points is an **inaccuracy**, twenty is a **mistake** and thirty is a **blunder**.
///
/// **`brilliant` is never answered here.** The shipped client only ever reaches it by upgrading a
/// best or excellent move after a second, cloud-side verification, and this app does not make that
/// call: a name it cannot justify is a name it does not print. See `xiangqi-com-re/docs/review.md`.
XiangqiMoveClassification xiangqiMoveClassificationOf(int accuracy) {
  if (accuracy > 99.9) return XiangqiMoveClassification.best;
  if (accuracy > 91) return XiangqiMoveClassification.excellent;
  if (accuracy > 80) return XiangqiMoveClassification.good;
  if (accuracy > 63) return XiangqiMoveClassification.inaccuracy;
  if (accuracy > 40) return XiangqiMoveClassification.mistake;
  return XiangqiMoveClassification.blunder;
}

/// The review of one move, read from the two verdicts that bracket it.
///
/// [before] is the engine's reading of the position the move was played in, [after] the reading of
/// the position it led to. **Both are in red's point of view**, which is what [XiangqiEvaluation]
/// is everywhere in this app — the server sends them in the side to move's, and `xiangqi_review_
/// repository.dart` is where they are turned round.
///
/// The win rate is taken from the mover's side twice: once from [before], and once from [after]
/// with the sign flipped, because a win rate is always somebody's. A move that leaves the position
/// exactly as good as it found it scores 100; one that hands the opponent the game scores near 1.
XiangqiMoveReview xiangqiMoveReviewOf({
  required int ply,
  required XiangqiMove move,
  required XiangqiEvaluation before,
  required XiangqiEvaluation after,
  XiangqiMove? bestMove,
  int depth = 0,
}) {
  final side = ply.isEven ? XiangqiSide.red : XiangqiSide.black;
  final sign = side == XiangqiSide.red ? 1 : -1;
  final beforeRate = xiangqiWinRate(xiangqiReviewScore(before) * sign);
  final afterRate = xiangqiWinRate(xiangqiReviewScore(after) * sign);
  final accuracy = xiangqiMoveAccuracy(before: beforeRate, after: afterRate);

  return XiangqiMoveReview(
    ply: ply,
    move: move,
    evaluation: before,
    classification: xiangqiMoveClassificationOf(accuracy),
    accuracy: accuracy,
    bestMove: bestMove,
    depth: depth,
  );
}

/// The analysis `game.review.success` carries, as the pairs of verdicts it is.
///
/// The frame holds one entry per position — `moves.length + 1` of them — and each entry is the
/// engine's reading of the position *before* the move of that ply. The last entry is therefore the
/// reading of the final position and has no move to go with it, which is why this drops it.
IList<XiangqiMoveReview> xiangqiMoveReviewsFromAnalysis({
  required IList<XiangqiMove> moves,
  required IList<XiangqiEvaluation> evaluations,
  required IList<XiangqiMove?> bestMoves,
  required IList<int> depths,
}) {
  if (evaluations.length != moves.length + 1) {
    _logger.warning(
      'The review carried ${evaluations.length} verdicts for ${moves.length} moves; '
      'a review is one verdict per position.',
    );
    return const IListConst<XiangqiMoveReview>([]);
  }
  return IList<XiangqiMoveReview>([
    for (var ply = 0; ply < moves.length; ply++)
      xiangqiMoveReviewOf(
        ply: ply,
        move: moves[ply],
        before: evaluations[ply],
        after: evaluations[ply + 1],
        bestMove: bestMoves[ply],
        depth: depths[ply],
      ),
  ]);
}

/// The moves `move_history` holds, or null if any entry is not a move.
///
/// Each entry is a string whose first whitespace-separated token is the UCI — the rest is the clock
/// readings the live screen uses and a review does not. This is the same rule
/// `xiangqi_online_game_controller.dart` follows, restated here because the two readers are in
/// different files and a review must not be built on a history it only half understood.
IList<XiangqiMove>? xiangqiReviewMovesFromHistory(Object? value) {
  if (value is! List) return null;
  final moves = <XiangqiMove>[];
  for (final entry in value) {
    if (entry is! String) return null;
    final token = entry.split(' ').first;
    final move = xiangqiMoveFromComUci(token);
    if (move == null) return null;
    moves.add(move);
  }
  return moves.lock;
}

/// Every position of [moves], played on from [initial], or null if a move does not fit.
IList<XiangqiPosition>? xiangqiReviewPositions(XiangqiPosition initial, IList<XiangqiMove> moves) {
  final positions = <XiangqiPosition>[initial];
  var position = initial;
  for (final move in moves) {
    if (!rules.isLegal(position, move)) return null;
    position = rules.play(position, move);
    positions.add(position);
  }
  return positions.lock;
}
