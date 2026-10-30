import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

/// Immutable analysis history. The first child is the main continuation; siblings are retained
/// when the user experiments at an earlier position. Paths contain ICCS moves, not chess squares.
class const XiangqiAnalysisNode({
  required final XiangqiPosition position,
  final XiangqiMove? move,
  final IList<XiangqiAnalysisNode> children = const IListConst([]),
}) {
  factory fromLine(XiangqiPosition initial, IList<XiangqiMove> moves) {
    var root = XiangqiAnalysisNode(position: initial);
    IList<XiangqiMove> path = const IListConst([]);
    for (final move in moves) {
      root = root.add(path, move);
      path = path.add(move);
    }
    return root;
  }

  XiangqiAnalysisNode nodeAt(IList<XiangqiMove> path) {
    var node = this;
    for (final move in path) {
      node = node.children.firstWhere((child) => child.move == move);
    }
    return node;
  }

  XiangqiAnalysisNode add(IList<XiangqiMove> path, XiangqiMove move) {
    if (path.isEmpty) {
      if (children.any((child) => child.move == move)) return this;
      return XiangqiAnalysisNode(
        position: position,
        move: this.move,
        children: children.add(
          XiangqiAnalysisNode(position: rules.play(position, move), move: move),
        ),
      );
    }
    return XiangqiAnalysisNode(
      position: position,
      move: this.move,
      children: IList([
        for (final child in children)
          if (child.move == path.first) child.add(path.sublist(1), move) else child,
      ]),
    );
  }

  /// Explicit deletion, used by retract; adding a variation never calls this operation.
  XiangqiAnalysisNode remove(IList<XiangqiMove> path) {
    if (path.isEmpty) return this;
    return XiangqiAnalysisNode(
      position: position,
      move: move,
      children: IList([
        for (final child in children)
          if (child.move != path.first)
            child
          else if (path.length > 1)
            child.remove(path.sublist(1)),
      ]),
    );
  }

  /// Projects a selected path, followed by its main continuation, into the existing linear view
  /// API. These arrays are read models; the retained tree remains the history's source of truth.
  ({IList<XiangqiPosition> positions, IList<XiangqiMove> moves}) lineThrough(
    IList<XiangqiMove> path,
  ) {
    final positions = <XiangqiPosition>[position];
    final moves = <XiangqiMove>[];
    var node = this;
    for (final move in path) {
      node = node.children.firstWhere((child) => child.move == move);
      positions.add(node.position);
      moves.add(move);
    }
    while (node.children.isNotEmpty) {
      node = node.children.first;
      positions.add(node.position);
      moves.add(node.move!);
    }
    return (positions: positions.lock, moves: moves.lock);
  }
}
