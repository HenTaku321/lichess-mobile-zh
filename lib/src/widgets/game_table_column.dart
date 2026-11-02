import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A game's landscape tables keep their natural height when they fit. On a short or large-text
/// viewport the tables scroll independently, leaving the action bar and a move-list row reachable.
///
/// Measure the actual tables, not text-height estimates: they may contain clocks, multiline
/// feedback, progress indicators or platform controls whose sizes change without a screen rebuild.
class GameTableColumn({
  required Widget topTable,
  required Widget bottomTable,
  Widget? moves,
  Widget? actions,
  final double minimumMoveHeight = 48,
  super.key,
}) extends MultiChildRenderObjectWidget {
  this
    : super(
        children: [
          SingleChildScrollView(primary: false, child: topTable),
          moves ?? const SizedBox.shrink(),
          actions ?? const SizedBox.shrink(),
          SingleChildScrollView(primary: false, child: bottomTable),
        ],
      );

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGameTableColumn(minimumMoveHeight);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderGameTableColumn renderObject) {
    renderObject.minimumMoveHeight = minimumMoveHeight;
  }
}

class _RenderGameTableColumn(double minimumMoveHeight)
    extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<RenderBox, ContainerBoxParentData<RenderBox>> {
  double _minimumMoveHeight = minimumMoveHeight;

  set minimumMoveHeight(double value) {
    if (_minimumMoveHeight == value) return;
    _minimumMoveHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = ContainerBoxParentData<RenderBox>();
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
      (child.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(0, y);
      y += child.size.height;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
