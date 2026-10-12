import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:meta/meta.dart';

/// A move: where a piece is, and where it goes.
///
/// In this game that is all a move can be. There is no promotion, no castling, no en passant and
/// nothing is ever dropped back onto the board, so the two ends describe a move completely and
/// there is nothing else for this to carry.
@immutable
final class const XiangqiMove(
  /// Where the piece is.
  final XiangqiSquare from,

  /// Where it goes. Whatever was there is captured.
  final XiangqiSquare to,
) {
  /// The move written as [iccs], `h2e2`, or null if it is not two square names.
  static XiangqiMove? parseIccs(String iccs) {
    if (iccs.length != 4) return null;
    final from = XiangqiSquare.parse(iccs.substring(0, 2));
    final to = XiangqiSquare.parse(iccs.substring(2, 4));
    if (from == null || to == null) return null;
    return XiangqiMove(from, to);
  }

  /// The move in ICCS coordinates.
  ///
  /// The notation the engine speaks: Pikafish takes `position ... moves h2e2` and answers
  /// `bestmove h2e2`, so this is both what the app sends and reads back, and — since a square name
  /// is the name FEN uses too — the one spelling of a move that appears nowhere but here.
  String get iccs => '${from.name}${to.name}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is XiangqiMove && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => iccs;
}
