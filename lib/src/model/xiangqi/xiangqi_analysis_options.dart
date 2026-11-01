import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_tree.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_replay.dart';

typedef XiangqiAnalysisSourceKey = (String, IList<String>, XiangqiReplayKind, int);

final class const XiangqiAnalysisCapabilities({
  final bool engine = true,
  final bool editHistory = true,
  final bool exportHistory = true,
  final bool editPosition = true,
  final bool positionAnalysis = true,
  final bool continueGame = true,
}) {
  XiangqiAnalysisCapabilities restrictedTo(XiangqiAnalysisCapabilities other) =>
      XiangqiAnalysisCapabilities(
        engine: engine && other.engine,
        editHistory: editHistory && other.editHistory,
        exportHistory: exportHistory && other.exportHistory,
        editPosition: editPosition && other.editPosition,
        positionAnalysis: positionAnalysis && other.positionAnalysis,
        continueGame: continueGame && other.continueGame,
      );

  int get cacheMask =>
      (engine ? 1 : 0) |
      (editHistory ? 2 : 0) |
      (exportHistory ? 4 : 0) |
      (editPosition ? 8 : 0) |
      (positionAnalysis ? 16 : 0) |
      (continueGame ? 32 : 0);
}

const kFullXiangqiAnalysisCapabilities = XiangqiAnalysisCapabilities();
const kTeachingXiangqiAnalysisCapabilities = XiangqiAnalysisCapabilities(
  engine: false,
  editHistory: false,
  editPosition: false,
);

/// An immutable, replay-validated handoff. The snapshot participates in the session key, so a
/// changed game never restores branches from an older history under the same upstream id.
/// Permissions also participate: a restricted source never inherits a broader source's edits.
final class const XiangqiAnalysisOptions._({
  required final XiangqiReplaySnapshot replay,
  required final XiangqiAnalysisCapabilities capabilities,
  required final XiangqiAnalysisNode root,
}) {
  factory line({
    required String sourceId,
    required XiangqiPosition initialPosition,
    required IList<XiangqiMove> moves,
    int? initialCursor,
    XiangqiSide orientation = XiangqiSide.red,
    bool engineAllowed = true,
  }) => XiangqiAnalysisOptions.snapshot(
    XiangqiReplaySnapshot.line(
      sourceId: sourceId,
      initialPosition: initialPosition,
      moves: moves,
      initialCursor: initialCursor,
      orientation: orientation,
    ),
    // Compatibility: legacy restricted analysis allowed local branch experiments but no engine,
    // editor, export or continuation. New sources can control each capability independently.
    capabilities: XiangqiAnalysisCapabilities(
      engine: engineAllowed,
      exportHistory: engineAllowed,
      editPosition: engineAllowed,
      positionAnalysis: engineAllowed,
      continueGame: engineAllowed,
    ),
  );

  factory snapshot(
    XiangqiReplaySnapshot replay, {
    XiangqiAnalysisCapabilities capabilities = kFullXiangqiAnalysisCapabilities,
  }) => XiangqiAnalysisOptions._(
    replay: replay,
    capabilities: capabilities.restrictedTo(
      replay.kind == .teaching
          ? kTeachingXiangqiAnalysisCapabilities
          : kFullXiangqiAnalysisCapabilities,
    ),
    root: XiangqiAnalysisNode.fromReplay(replay),
  );

  String get sourceId => replay.sourceId;
  IList<XiangqiMove> get initialMoves => replay.moves;
  int get initialCursor => replay.initialCursor;
  XiangqiSide get orientation => replay.orientation;
  bool get engineAllowed => capabilities.engine;
  XiangqiAnalysisSourceKey get sourceKey =>
      (sourceId, replay.recordedFens, replay.kind, capabilities.cacheMask);
}
