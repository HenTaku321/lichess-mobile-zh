import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

enum XiangqiPositionError() {
  counters,
  generals,
  material,
  placement,
  facingGenerals,
  inactiveSideInCheck,
}

/// Validate a position before handing an arbitrary teaching diagram to a game or engine. This
/// checks local position legality, not whether an entire game can reach the diagram.
XiangqiPositionError? xiangqiPositionError(XiangqiPosition position) {
  if (position.board.length != kXiangqiSquares ||
      position.halfmoveClock < 0 ||
      position.halfmoveClock > 0x7fffffff ||
      position.fullmoveNumber < 1 ||
      position.fullmoveNumber > 0x7fffffff) {
    return .counters;
  }
  final generals = <XiangqiSide, XiangqiSquare>{};
  for (final side in XiangqiSide.values) {
    final counts = <XiangqiPieceType, int>{};
    for (var i = 0; i < position.board.length; i++) {
      final piece = position.board[i];
      if (piece == null || piece.side != side) continue;
      counts.update(piece.type, (count) => count + 1, ifAbsent: () => 1);
      if (piece.type == .king) generals[side] = XiangqiSquare(i);
    }
    if (counts[XiangqiPieceType.king] != 1) return .generals;
    if (counts.entries.any((entry) => entry.value > (entry.key == .pawn ? 5 : 2))) {
      return .material;
    }
  }
  for (var i = 0; i < position.board.length; i++) {
    final piece = position.board[i];
    if (piece == null) continue;
    final square = XiangqiSquare(i);
    final rank = piece.side == .red ? square.rank : 9 - square.rank;
    final valid = switch (piece.type) {
      .king => square.inPalaceOf(piece.side),
      .advisor => square.inPalaceOf(piece.side) && (square.file + rank).isOdd,
      .bishop => switch ((square.file, rank)) {
        (2, 0) || (6, 0) || (0, 2) || (4, 2) || (8, 2) || (2, 4) || (6, 4) => true,
        _ => false,
      },
      .pawn => rank >= 3 && (rank >= 5 || square.file.isEven),
      _ => true,
    };
    if (!valid) return .placement;
  }
  final red = generals[XiangqiSide.red]!;
  final black = generals[XiangqiSide.black]!;
  if (red.file == black.file &&
      Iterable<int>.generate(
        black.rank - red.rank - 1,
        (i) => red.rank + i + 1,
      ).every((rank) => position.pieceAt(XiangqiSquare.at(red.file, rank)) == null)) {
    return .facingGenerals;
  }
  if (rules.isCheck(
    XiangqiPosition(
      board: position.board,
      turn: position.turn.opposite,
      halfmoveClock: position.halfmoveClock,
      fullmoveNumber: position.fullmoveNumber,
    ),
  )) {
    return .inactiveSideInCheck;
  }
  return null;
}
