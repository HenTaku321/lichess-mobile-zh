import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps the same visible row at the same logical-pixel offset when asynchronous sources insert
/// or reorder items. Keys identify real rows, not fixed-height estimates or invented server IDs.
///
/// The viewport's leading edge still follows new content when it is already at offset zero.
/// Identity/filter boundaries belong in this widget's key. A user scroll between capture and
/// layout wins over restoration, so a network update cannot fight a wheel, drag or ballistic scroll.
class const AnchoredListView({
  required final int itemCount,
  required final Object Function(int index) itemKey,
  required final IndexedWidgetBuilder itemBuilder,
  final IndexedWidgetBuilder? separatorBuilder,
  final ScrollController? controller,
  final EdgeInsetsGeometry? padding,
  final ScrollPhysics? physics,
  final bool reverse = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<AnchoredListView> createState() => _AnchoredListViewState();
}

class _AnchoredListViewState() extends State<AnchoredListView> {
  final _ownedController = ScrollController();
  final _viewport = GlobalKey();
  final Map<Object, GlobalKey> _rows = {};
  final Map<Key, Object> _ids = {};
  Map<Object, int> _indexes = {};
  _ScrollAnchor? _pending;
  bool _scheduled = false;

  ScrollController get _controller => widget.controller ?? _ownedController;

  @override
  void didUpdateWidget(AnchoredListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller || oldWidget.reverse != widget.reverse) {
      _pending = null;
      return;
    }
    final nextIds = {for (var index = 0; index < widget.itemCount; index++) widget.itemKey(index)};
    _pending ??= _capture(nextIds);
    if (_pending != null && !_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    }
  }

  _ScrollAnchor? _capture(Set<Object> nextIds) {
    if (!_controller.hasClients || _controller.offset <= 1) return null;
    if (_controller.position.isScrollingNotifier.value) return null;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    Object? selected;
    double? leading;
    for (final entry in _rows.entries) {
      if (!nextIds.contains(entry.key)) continue;
      final row = entry.value.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached || !row.hasSize) continue;
      final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top + row.size.height <= 0 || top >= viewport.size.height) continue;
      if (leading == null || top < leading) {
        selected = entry.key;
        leading = top;
      }
    }
    return selected == null ? null : _ScrollAnchor(selected, leading!, _controller.offset);
  }

  void _restore() {
    _scheduled = false;
    final anchor = _pending;
    _pending = null;
    if (!mounted || anchor == null || !_controller.hasClients) return;
    if (_controller.position.isScrollingNotifier.value ||
        (_controller.offset - anchor.scrollOffset).abs() > 1) {
      return;
    }
    final viewport = _viewport.currentContext?.findRenderObject();
    final row = _rows[anchor.id]?.currentContext?.findRenderObject();
    if (viewport is! RenderBox || row is! RenderBox || !row.attached || !row.hasSize) return;
    final delta = row.localToGlobal(Offset.zero, ancestor: viewport).dy - anchor.visualOffset;
    if (delta.abs() < 0.01) return;
    final position = _controller.position;
    final target = (_controller.offset + (widget.reverse ? -delta : delta))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - _controller.offset).abs() >= 0.01) _controller.jumpTo(target);
  }

  @override
  void dispose() {
    _pending = null;
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _indexes = {
      for (var index = 0; index < widget.itemCount; index++) widget.itemKey(index): index,
    };
    assert(_indexes.length == widget.itemCount, 'Anchored list row keys must be unique.');
    _rows.removeWhere((id, key) {
      if (_indexes.containsKey(id)) return false;
      _ids.remove(key);
      return true;
    });
    return SizedBox(
      key: _viewport,
      child: ListView.builder(
        controller: _controller,
        reverse: widget.reverse,
        padding: widget.padding,
        physics: widget.physics,
        itemCount: widget.itemCount,
        findChildIndexCallback: (key) => _indexes[_ids[key]],
        itemBuilder: (context, index) {
          final id = widget.itemKey(index);
          final key = _rows.putIfAbsent(id, GlobalKey.new);
          _ids[key] = id;
          final item = widget.itemBuilder(context, index);
          final separator = widget.separatorBuilder;
          return KeyedSubtree(
            key: key,
            child: separator == null || index == widget.itemCount - 1
                ? item
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [item, separator(context, index)],
                  ),
          );
        },
      ),
    );
  }
}

class _ScrollAnchor(final Object id, final double visualOffset, final double scrollOffset);
