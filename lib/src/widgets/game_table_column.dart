import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// A game's landscape tables keep their natural height when they fit. On a short or large-text
/// viewport the tables scroll independently, leaving the action bar and a move-list row reachable.
///
/// Measure the actual tables, not text-height estimates: they may contain clocks, multiline
/// feedback, progress indicators or platform controls whose sizes change without a screen rebuild.
class const GameTableColumn({
  required final Widget topTable,
  required final Widget bottomTable,
  final Widget? moves,
  final Widget? actions,
  final double minimumMoveHeight = 48,
  super.key,
}) extends StatefulWidget {
  @override
  State<GameTableColumn> createState() => _GameTableColumnState();
}

class _GameTableColumnState() extends State<GameTableColumn> {
  final _topController = ScrollController();
  final _bottomController = ScrollController();

  @override
  void dispose() {
    _topController.dispose();
    _bottomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _TableColumnLayout(
    minimumMoveHeight: widget.minimumMoveHeight,
    topController: _topController,
    bottomController: _bottomController,
    children: [
      SingleChildScrollView(controller: _topController, primary: false, child: widget.topTable),
      widget.moves ?? const SizedBox.shrink(),
      widget.actions ?? const SizedBox.shrink(),
      SingleChildScrollView(
        controller: _bottomController,
        primary: false,
        child: widget.bottomTable,
      ),
    ],
  );
}

class const _TableColumnLayout({
  required final double minimumMoveHeight,
  required final ScrollController topController,
  required final ScrollController bottomController,
  required super.children,
}) extends MultiChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGameTableColumn(minimumMoveHeight, topController, bottomController);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderGameTableColumn renderObject) {
    renderObject.minimumMoveHeight = minimumMoveHeight;
  }
}

class _RenderGameTableColumn(
  double minimumMoveHeight,
  final ScrollController topController,
  final ScrollController bottomController,
) extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TableParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TableParentData> {
  double _minimumMoveHeight = minimumMoveHeight;

  double get minimumMoveHeight => _minimumMoveHeight;

  set minimumMoveHeight(double value) {
    if (_minimumMoveHeight == value) return;
    _minimumMoveHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TableParentData) {
      child.parentData = _TableParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth && constraints.hasBoundedHeight);
    size = constraints.biggest;
    final children = getChildrenAsList();
    assert(children.length == 4);
    final top = children[0];
    final moves = children[1];
    final actions = children[2];
    final bottom = children[3];
    final topPixels = topController.hasClients ? topController.offset : 0.0;
    final bottomPixels = bottomController.hasClients ? bottomController.offset : 0.0;
    final natural = BoxConstraints.tightFor(width: size.width);
    top.layout(natural, parentUsesSize: true);
    bottom.layout(natural, parentUsesSize: true);
    actions.layout(natural, parentUsesSize: true);
    final available = math.max(0.0, size.height - actions.size.height);
    final tableBudget = math.max(0.0, available - math.min(_minimumMoveHeight, available * 0.4));
    final naturalTableHeight = top.size.height + bottom.size.height;
    if (naturalTableHeight > tableBudget) {
      final topHeight = naturalTableHeight == 0
          ? 0.0
          : tableBudget * top.size.height / naturalTableHeight;
      // Natural-height measurement temporarily makes a scroll viewport content-sized. Restore its
      // old offset before bounded layout using a correction, not a jumpTo notification/gesture.
      // That final layout still clamps correctly when the content genuinely becomes shorter.
      if (topController.hasClients) {
        topController.position.correctBy(topPixels - topController.offset);
      }
      if (bottomController.hasClients) {
        bottomController.position.correctBy(bottomPixels - bottomController.offset);
      }
      top.layout(
        BoxConstraints.tightFor(width: size.width, height: topHeight),
        parentUsesSize: true,
      );
      bottom.layout(
        BoxConstraints.tightFor(width: size.width, height: tableBudget - topHeight),
        parentUsesSize: true,
      );
    }
    final moveHeight = math.max(0.0, available - top.size.height - bottom.size.height);
    moves.layout(
      BoxConstraints.tightFor(width: size.width, height: moveHeight),
      parentUsesSize: true,
    );
    var y = 0.0;
    for (final child in children) {
      (child.parentData! as _TableParentData).offset = Offset(0, y);
      y += child.size.height;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _TableParentData() extends ContainerBoxParentData<RenderBox>;
