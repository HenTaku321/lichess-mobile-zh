import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_tree.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

typedef XiangqiAnalysisSourceKey = (String, XiangqiPosition, IList<XiangqiMove>);

/// An immutable, replay-validated handoff. The snapshot participates in the session key, so a
/// changed game never restores branches from an older history under the same upstream id.
final class const XiangqiAnalysisOptions._({
  required final String sourceId,
  required final XiangqiAnalysisNode root,
  required final IList<XiangqiMove> initialMoves,
  required final int initialCursor,
  required final XiangqiSide orientation,
  required final bool engineAllowed,
}) {
  factory line({
    required String sourceId,
    required XiangqiPosition initialPosition,
    required IList<XiangqiMove> moves,
    int? initialCursor,
    XiangqiSide orientation = XiangqiSide.red,
    bool engineAllowed = true,
  }) => XiangqiAnalysisOptions._(
    sourceId: sourceId,
    root: XiangqiAnalysisNode.fromLine(initialPosition, moves),
    initialMoves: moves,
    initialCursor: (initialCursor ?? moves.length).clamp(0, moves.length),
    orientation: orientation,
    engineAllowed: engineAllowed,
  );

  XiangqiAnalysisSourceKey get sourceKey => (sourceId, root.position, initialMoves);
}
