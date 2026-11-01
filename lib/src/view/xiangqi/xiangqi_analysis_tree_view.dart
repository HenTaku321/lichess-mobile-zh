import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_tree.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/widgets/move_tree_view.dart';
import 'package:material_ui/material_ui.dart';

/// Xiangqi adapter for the same tree traversal, caching, cells and node menus used by chess.
/// The immutable projection is rebuilt only when the retained tree changes, not on every seek.
class const XiangqiAnalysisTreeView({
  required final XiangqiAnalysisNode root,
  required final IList<XiangqiMove> currentPath,
  required final XiangqiAnalysisController controller,
  final PgnTreeDisplayMode displayMode = PgnTreeDisplayMode.twoColumn,
  super.key,
}) extends StatefulWidget {
  @override
  State<XiangqiAnalysisTreeView> createState() => _XiangqiAnalysisTreeViewState();
}

MoveTreeNode<XiangqiMove> _treeNode(XiangqiAnalysisNode node, [XiangqiPosition? before]) =>
    MoveTreeNode(
      moveId: node.move,
      ply: (node.position.fullmoveNumber - 1) * 2 + (node.position.turn == .black ? 1 : 0),
      fullmoveNumber: node.position.fullmoveNumber,
      firstSideToMove: node.position.turn == .red,
      notation: node.move == null ? '' : xiangqiMoveNotation(before!, node.move!),
      children: node.children.map((child) => _treeNode(child, node.position)).toIList(),
      isCollapsed: node.isCollapsed,
    );

class _XiangqiTreeNotifier(final XiangqiAnalysisController controller)
    extends MoveTreeNotifier<XiangqiMove> {
  @override
  void userJump(MoveTreePath<XiangqiMove> path) => controller.goToPath(path.ids);
  @override
  void deleteFromHere(MoveTreePath<XiangqiMove> path) => controller.deleteFromHere(path.ids);
  @override
  void promoteVariation(MoveTreePath<XiangqiMove> path, bool toMainLine) =>
      controller.promoteVariation(path: path.ids, toMainline: toMainLine);
  @override
  void collapseVariations(MoveTreePath<XiangqiMove> path) =>
      controller.collapseVariations(path.ids);
  @override
  void expandVariations(MoveTreePath<XiangqiMove> path) => controller.expandVariations(path.ids);
  @override
  String makeLineText(MoveTreePath<XiangqiMove> path, {required bool includeVariations}) =>
      controller.makeLineExport(path: path.ids, includeVariations: includeVariations);
}

class _XiangqiAnalysisTreeViewState() extends State<XiangqiAnalysisTreeView> {
  late MoveTreeNode<XiangqiMove> _root;
  late _XiangqiTreeNotifier _notifier;
  @override
  void initState() {
    super.initState();
    _root = _treeNode(widget.root);
    _notifier = _XiangqiTreeNotifier(widget.controller);
  }

  @override
  void didUpdateWidget(covariant XiangqiAnalysisTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.root, oldWidget.root)) _root = _treeNode(widget.root);
    if (oldWidget.controller != widget.controller) {
      _notifier = _XiangqiTreeNotifier(widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: DebouncedMoveTreeView<XiangqiMove>(
      root: _root,
      currentPath: MoveTreePath(widget.currentPath),
      pgnRootComments: const IListConst([]),
      notifier: _notifier,
      displayMode: widget.displayMode,
    ),
  );
}
