import 'package:chessground/chessground.dart' show Annotation;
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/move_tree_view.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lichess_mobile/src/widgets/move_tree_view.dart'
    show
        PgnTreeDisplayMode,
        kCommentVerticalPadding,
        kFastReplayDebounceDelay,
        kIndexOpacity,
        kInlineMovePadding,
        kViewHorizontalPadding,
        kViewVerticalPadding,
        moveAnnotationChar;

/// Retain the public chess move-cell type for existing consumers and tests.
typedef InlineMove = TreeInlineMove<UciCharPair>;

Annotation? makeAnnotation(Iterable<int>? nags) {
  final nag = nags?.firstOrNull;
  if (nag == null) return null;
  final annotation = moveAnnotationPresentation(nag);
  return annotation == null ? null : Annotation(symbol: annotation.symbol, color: annotation.color);
}

MoveTreePath<UciCharPair> _treePath(UciPath path) =>
    MoveTreePath.fromIds(List.generate(path.size, (i) => path[i]));

MoveTreeNode<UciCharPair> _treeNode(ViewNode node) => MoveTreeNode(
  ply: node.position.ply,
  fullmoveNumber: node.position.fullmoves,
  firstSideToMove: node.position.turn == Side.white,
  children: node.children.map(_treeNode).toIList(),
  moveId: node is ViewBranch ? node.id : null,
  notation: node is ViewBranch
      ? node.sanMove.san.startsWith('P')
            ? node.sanMove.san.substring(1)
            : node.sanMove.san
      : '',
  comments: node is ViewBranch ? node.textComments.toIList() : const IListConst([]),
  nags: node is ViewBranch ? node.nags : null,
  evaluation: node is ViewBranch ? (node.eval ?? node.serverEval)?.evalString : null,
  clock: node is ViewBranch ? node.clock : null,
  elapsedMoveTime: node is ViewBranch ? node.elapsedMoveTime : null,
  isCollapsed: node is ViewBranch && node.isCollapsed,
  isUserAdded: node is ViewBranch && node.isUserAdded,
  isComputerVariation: node is ViewBranch && node.isComputerVariation,
);

class _ChessTreeNotifier(final PgnTreeNotifier notifier) extends MoveTreeNotifier<UciCharPair> {
  UciPath _path(MoveTreePath<UciCharPair> path) => UciPath.fromIds(path.ids);
  @override
  void userJump(MoveTreePath<UciCharPair> path) => notifier.userJump(_path(path));
  @override
  void deleteFromHere(MoveTreePath<UciCharPair> path) => notifier.deleteFromHere(_path(path));
  @override
  void promoteVariation(MoveTreePath<UciCharPair> path, bool toMainLine) =>
      notifier.promoteVariation(_path(path), toMainLine);
  @override
  void collapseVariations(MoveTreePath<UciCharPair> path) =>
      notifier.collapseVariations(_path(path));
  @override
  void expandVariations(MoveTreePath<UciCharPair> path) => notifier.expandVariations(_path(path));
  @override
  String makeLineText(MoveTreePath<UciCharPair> path, {required bool includeVariations}) => notifier
      .makeLinePgn(_path(path), includeVariations: includeVariations)
      .trimRight()
      .replaceFirst(RegExp(r'\s*\*$'), '');
}

/// Chess model adapter; the typed move tree renderer is shared with xiangqi.
class const DebouncedPgnTreeView({
  /// Root of the PGN tree to display
  required final ViewNode root,

  /// Path to the currently selected move in the tree
  required final UciPath currentPath,

  /// Path to the last live move in the tree if it is an ongoing game (usually broadcast or correspondence).
  final UciPath? livePath,

  /// Paths relative to [DebouncedPgnTreeView.livePath] that are currently saved as premoves in an ongoing correspondence game.
  /// We highlight these in a different color
  final IList<UciPath>? premovePaths,

  /// Comments associated with the root node
  required final IList<PgnComment>? pgnRootComments,

  /// Callbacks for when the user interacts with the tree view, e.g. selecting a different move or collapsing variations
  final PgnTreeNotifier? notifier,

  /// Whether to show a divider line above the first mainline part.
  final bool showTopDivider = true,

  /// Whether to show computer analysis informations.
  ///
  /// If `true`, the tree view will show computer analysis variations and evaluations.
  /// Only applied to lichess game analysis.
  final bool shouldShowComputerAnalysis = true,

  /// Whether to show NAG annotations like '!' and '??'.
  final bool shouldShowAnnotations = true,

  /// Whether to show comments associated with the moves.
  final bool shouldShowComments = true,

  /// Display mode of the tree view.
  ///
  /// Either [PgnTreeDisplayMode.twoColumn] or [PgnTreeDisplayMode.inlineNotation].
  final PgnTreeDisplayMode displayMode = PgnTreeDisplayMode.twoColumn,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<DebouncedPgnTreeView> createState() => _DebouncedPgnTreeViewState();
}

class _DebouncedPgnTreeViewState() extends ConsumerState<DebouncedPgnTreeView> {
  late MoveTreeNode<UciCharPair> _root;
  MoveTreeNotifier<UciCharPair>? _notifier;
  @override
  void initState() {
    super.initState();
    _root = _treeNode(widget.root);
    _notifier = widget.notifier == null ? null : _ChessTreeNotifier(widget.notifier!);
  }

  @override
  void didUpdateWidget(covariant DebouncedPgnTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root) _root = _treeNode(widget.root);
    if (oldWidget.notifier != widget.notifier) {
      _notifier = widget.notifier == null ? null : _ChessTreeNotifier(widget.notifier!);
    }
  }

  @override
  Widget build(BuildContext context) => DebouncedMoveTreeView<UciCharPair>(
    root: _root,
    currentPath: _treePath(widget.currentPath),
    livePath: widget.livePath == null ? null : _treePath(widget.livePath!),
    premovePaths: widget.premovePaths?.map(_treePath).toIList(),
    pgnRootComments: widget.pgnRootComments?.map((c) => c.text).nonNulls.toIList(),
    notifier: _notifier,
    showTopDivider: widget.showTopDivider,
    shouldShowComputerAnalysis: widget.shouldShowComputerAnalysis,
    shouldShowAnnotations: widget.shouldShowAnnotations,
    shouldShowComments: widget.shouldShowComments,
    displayMode: widget.displayMode,
    usesChessFont: true,
    mainlineCopyLabel: context.l10n.copyMainLinePgn,
    variationCopyLabel: context.l10n.copyVariationPgn,
    copyMessage: context.l10n.mobilePgnCopied,
  );
}
