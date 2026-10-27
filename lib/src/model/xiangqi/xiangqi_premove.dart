import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

/// Like chessground's premovesOf, these are geometric candidates, not legal moves. Blockers,
/// cannon screens, horse legs and check may change on the opponent's turn. Actual execution must
/// go through validateXiangqiPremove after the opponent's confirmed incremental move.
IList<XiangqiMove> xiangqiPremovesFrom(XiangqiPosition position, XiangqiSquare from) {
  final piece = position.pieceAt(from);
  if (piece == null) return const IListConst([]);
  return [
    for (var index = 0; index < kXiangqiSquares; index++)
      if (index != from.index)
        if (_canReach(piece, from, XiangqiSquare(index))) XiangqiMove(from, XiangqiSquare(index)),
  ].lock;
}

bool _canReach(XiangqiPiece piece, XiangqiSquare from, XiangqiSquare to) {
  final dx = (from.file - to.file).abs();
  final dy = (from.rank - to.rank).abs();
  return switch (piece.type) {
    .rook || .cannon => dx == 0 || dy == 0,
    .knight => dx * dy == 2,
    .bishop => dx == 2 && dy == 2 && to.onOwnHalf(piece.side),
    .advisor => dx == 1 && dy == 1 && to.inPalaceOf(piece.side),
    .king => dx + dy == 1 && to.inPalaceOf(piece.side),
    .pawn =>
      (dx == 0 && to.rank - from.rank == (piece.side == .red ? 1 : -1)) ||
          (!from.onOwnHalf(piece.side) && dy == 0 && dx == 1),
  };
}

XiangqiMove? validateXiangqiPremove(
  XiangqiPosition queuedAt,
  XiangqiPosition confirmed,
  XiangqiMove move,
  XiangqiSide playerSide,
) {
  final piece = queuedAt.pieceAt(move.from);
  if (piece == null ||
      piece.side != playerSide ||
      confirmed.turn != playerSide ||
      confirmed.pieceAt(move.from) != piece ||
      !rules.isLegal(confirmed, move)) {
    return null;
  }
  return move;
}
