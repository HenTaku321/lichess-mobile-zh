import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// One soldier, in the units [xiangqiPieceValue] counts in.
///
/// Pikafish's `PawnValue` — see [xiangqiPieceValue] for where that comes from — and the divisor
/// that turns a raw difference into the points a player counts a position in.
const int kXiangqiPawnValue = 144;

/// What a piece of [type] is worth, in the units Pikafish itself counts material in.
///
/// These are Pikafish's own `Value` constants, taken from the engine the app vendors rather than
/// chosen here: `RookValue = 1305`, `AdvisorValue = 219`, `CannonValue = 773`, `PawnValue = 144`,
/// `KnightValue = 720`, `BishopValue = 187`, in the table the search reads its piece values out of.
/// The source is the copy of Pikafish under `multistockfish_pikafish`,
/// `pikafish/…/Pikafish-532c3ff216/src/types.h:176-181` for the constants and `:198-201` for the
/// `PieceValue[]` table they fill. Pikafish's own piece order is `ROOK, ADVISOR, CANNON, PAWN,
/// KNIGHT, BISHOP`, and its `ADVISOR` is the app's [XiangqiPieceType.advisor] while its `BISHOP` is
/// the app's [XiangqiPieceType.bishop].
///
/// A general is worth nothing. Pikafish's `KING` entry is `VALUE_ZERO`, because losing the general
/// ends the game rather than costing material — a position without one is not a material
/// disadvantage, it is a lost game — and a tally that priced it would be ranking a piece that is
/// never traded.
///
/// The absolute size of these numbers is Pikafish's own and is not centipawns: it scales a score
/// into centipawns by a factor that depends on the position before it prints one (see `uci.cpp`),
/// so there is no fixed conversion from these to what the app's evaluation bar shows. Their ratios
/// are the engine's judgement of what the pieces are worth, and the ratios are what a material
/// tally is made of — which is why [xiangqiMaterialDifferenceInPawns] normalises them by
/// [kXiangqiPawnValue] rather than pretending to be centipawns.
int xiangqiPieceValue(XiangqiPieceType type) => switch (type) {
  .king => 0,
  .advisor => 219,
  .bishop => 187,
  .knight => 720,
  .rook => 1305,
  .cannon => 773,
  .pawn => 144,
};

/// The value of everything [side] still has on the board, in [xiangqiPieceValue]'s units.
int xiangqiMaterialCount(XiangqiPosition position, XiangqiSide side) {
  var total = 0;
  for (final piece in position.board) {
    if (piece != null && piece.side == side) total += xiangqiPieceValue(piece.type);
  }
  return total;
}

/// Red's material minus black's, in [xiangqiPieceValue]'s units: positive means red is ahead.
int xiangqiMaterialDifference(XiangqiPosition position) =>
    xiangqiMaterialCount(position, .red) - xiangqiMaterialCount(position, .black);

/// The same difference in soldiers, which is the unit a player counts a position in.
///
/// One soldier is one point, so a chariot comes out at a little over nine, a cannon at five and a
/// third, a horse at exactly five, an advisor at about one and a half and an elephant at about one
/// and a third. None of those are round numbers, and that is Pikafish's own judgement rather than
/// this file's: the pieces are worth what the engine that plays them counts them worth, and
/// rounding them off here would be a second opinion about the game dressed up as a display choice.
double xiangqiMaterialDifferenceInPawns(XiangqiPosition position) =>
    xiangqiMaterialDifference(position) / kXiangqiPawnValue;

/// The value of one piece of [type] in soldiers, for a table a player reads.
double xiangqiPieceValueInPawns(XiangqiPieceType type) =>
    xiangqiPieceValue(type) / kXiangqiPawnValue;
