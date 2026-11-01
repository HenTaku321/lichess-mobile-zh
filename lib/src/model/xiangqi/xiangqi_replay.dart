import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position_validation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

enum XiangqiReplayKind() {
  game,
  teaching,
}

/// A handoff of already displayed moves only. No solution, unplayed script, completion callback
/// or upstream client belongs to a replay. Recorded counters are checked as well as board/turn.
final class const XiangqiReplaySnapshot._({
  required final String sourceId,
  required final XiangqiReplayKind kind,
  required final IList<XiangqiPosition> positions,
  required final IList<XiangqiMove> moves,
  required final int initialCursor,
  required final XiangqiSide orientation,
}) {
  factory line({
    required String sourceId,
    required XiangqiPosition initialPosition,
    required IList<XiangqiMove> moves,
    int? initialCursor,
    XiangqiSide orientation = XiangqiSide.red,
  }) {
    final positions = <XiangqiPosition>[initialPosition];
    for (final move in moves) {
      positions.add(rules.play(positions.last, move));
    }
    return XiangqiReplaySnapshot._(
      sourceId: sourceId,
      kind: .game,
      positions: positions.lock,
      moves: moves,
      initialCursor: (initialCursor ?? moves.length).clamp(0, moves.length),
      orientation: orientation,
    );
  }

  factory recorded({
    required String sourceId,
    required XiangqiReplayKind kind,
    required IList<XiangqiPosition> positions,
    required IList<XiangqiMove> moves,
    int? initialCursor,
    XiangqiSide orientation = XiangqiSide.red,
  }) {
    if (positions.length != moves.length + 1 ||
        positions.any((position) => position.board.length != kXiangqiSquares)) {
      throw const FormatException('Replay moves and recorded positions do not align.');
    }
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (move.from.index < 0 ||
          move.from.index >= kXiangqiSquares ||
          move.to.index < 0 ||
          move.to.index >= kXiangqiSquares ||
          move.from == move.to) {
        throw const FormatException('Replay move is outside the board or does not move.');
      }
      if (positions[i].pieceAt(move.from) == null) {
        throw const FormatException('Replay step has no piece on its starting square.');
      }
      final next = kind == .game
          ? rules.play(positions[i], move)
          : rules.playForced(positions[i], move);
      if (next.toFen() != positions[i + 1].toFen()) {
        throw FormatException('Replay position after step ${i + 1} differs from its move.');
      }
    }
    return XiangqiReplaySnapshot._(
      sourceId: sourceId,
      kind: kind,
      positions: positions,
      moves: moves,
      initialCursor: (initialCursor ?? moves.length).clamp(0, moves.length),
      orientation: orientation,
    );
  }

  /// Classify a completed training record without changing or truncating it. A teaching diagram
  /// with non-game material or forced steps stays teaching even if its final position is playable.
  factory training({
    required String sourceId,
    required IList<XiangqiPosition> positions,
    required IList<XiangqiMove> moves,
    int? initialCursor,
    XiangqiSide orientation = XiangqiSide.red,
  }) {
    final teaching = XiangqiReplaySnapshot.recorded(
      sourceId: sourceId,
      kind: .teaching,
      positions: positions,
      moves: moves,
      initialCursor: initialCursor,
      orientation: orientation,
    );
    final game =
        positions.every((position) => xiangqiPositionError(position) == null) &&
        Iterable<int>.generate(moves.length).every((i) => rules.isLegal(positions[i], moves[i]));
    return !game
        ? teaching
        : XiangqiReplaySnapshot.recorded(
            sourceId: sourceId,
            kind: .game,
            positions: positions,
            moves: moves,
            initialCursor: initialCursor,
            orientation: orientation,
          );
  }

  /// Unlike XiangqiPosition equality, this includes the move counters.
  IList<String> get recordedFens => positions.map((position) => position.toFen()).toIList();
}
