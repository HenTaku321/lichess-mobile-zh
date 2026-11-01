import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_replay.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

/// Immutable analysis history. The first child is the main continuation; siblings are retained
/// when the user experiments at an earlier position. Paths contain ICCS moves, not chess squares.
class const XiangqiAnalysisNode({
  required final XiangqiPosition position,
  final XiangqiMove? move,
  final IList<XiangqiAnalysisNode> children = const IListConst([]),
  final bool isCollapsed = false,
}) {
  factory fromLine(XiangqiPosition initial, IList<XiangqiMove> moves) {
    final positions = <XiangqiPosition>[initial];
    for (final move in moves) {
      positions.add(rules.play(positions.last, move));
    }
    var node = XiangqiAnalysisNode(
      position: positions.last,
      move: moves.isEmpty ? null : moves.last,
    );
    for (var i = moves.length - 1; i >= 0; i--) {
      node = XiangqiAnalysisNode(
        position: positions[i],
        move: i == 0 ? null : moves[i - 1],
        children: IList([node]),
      );
    }
    return node;
  }

  /// Keep every validated recorded position, including non-alternating teaching steps. Only the
  /// snapshot's factory may validate forced transitions; game add/play methods remain strict.
  factory fromReplay(XiangqiReplaySnapshot snapshot) {
    var node = XiangqiAnalysisNode(
      position: snapshot.positions.last,
      move: snapshot.moves.lastOrNull,
    );
    for (var i = snapshot.moves.length - 1; i >= 0; i--) {
      node = XiangqiAnalysisNode(
        position: snapshot.positions[i],
        move: i == 0 ? null : snapshot.moves[i - 1],
        children: IList([node]),
      );
    }
    return node;
  }

  XiangqiAnalysisNode nodeAt(IList<XiangqiMove> path) {
    var node = this;
    for (final move in path) {
      node = node.children.firstWhere((child) => child.move == move);
    }
    return node;
  }

  bool hasPath(IList<XiangqiMove> path) {
    var node = this;
    for (final move in path) {
      final child = node.children.where((child) => child.move == move).firstOrNull;
      if (child == null) return false;
      node = child;
    }
    return true;
  }

  XiangqiAnalysisNode copyWith({IList<XiangqiAnalysisNode>? children, bool? isCollapsed}) =>
      XiangqiAnalysisNode(
        position: position,
        move: move,
        children: children ?? this.children,
        isCollapsed: isCollapsed ?? this.isCollapsed,
      );

  XiangqiAnalysisNode updateAt(
    IList<XiangqiMove> path,
    XiangqiAnalysisNode Function(XiangqiAnalysisNode) update,
  ) {
    if (path.isEmpty) return update(this);
    if (!hasPath(path)) return this;
    return copyWith(
      children: children
          .map(
            (child) => child.move == path.first ? child.updateAt(path.sublist(1), update) : child,
          )
          .toIList(),
    );
  }

  bool canPromote(IList<XiangqiMove> path) {
    var node = this;
    for (final move in path) {
      final index = node.children.indexWhere((child) => child.move == move);
      if (index < 0) return false;
      if (index > 0) return true;
      node = node.children[index];
    }
    return false;
  }

  /// Moves the closest sideline on the selected path up one rank, retaining every subtree.
  XiangqiAnalysisNode promote(IList<XiangqiMove> path) {
    if (path.isEmpty) return this;
    final index = children.indexWhere((child) => child.move == path.first);
    if (index < 0) return this;
    final child = children[index];
    final promoted = child.promote(path.sublist(1));
    final updated = children.toList();
    if (!identical(child, promoted)) {
      updated[index] = promoted;
    } else if (index > 0) {
      updated[index] = updated[index - 1];
      updated[index - 1] = child;
    } else {
      return this;
    }
    return copyWith(children: updated.lock);
  }

  XiangqiAnalysisNode add(IList<XiangqiMove> path, XiangqiMove move) {
    if (path.isEmpty) {
      if (children.any((child) => child.move == move)) return this;
      return copyWith(
        children: children.add(
          XiangqiAnalysisNode(position: rules.play(position, move), move: move),
        ),
      );
    }
    if (!children.any((child) => child.move == path.first)) {
      throw ArgumentError.value(path, 'path', 'The analysis path does not exist.');
    }
    return copyWith(
      children: IList([
        for (final child in children)
          if (child.move == path.first) child.add(path.sublist(1), move) else child,
      ]),
    );
  }

  /// Explicit deletion, used by retract; adding a variation never calls this operation.
  XiangqiAnalysisNode remove(IList<XiangqiMove> path) {
    if (path.isEmpty) return this;
    return copyWith(
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
