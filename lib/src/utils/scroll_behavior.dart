import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// The app's scroll behaviour: the Material one, with the mouse added to the
/// devices that can drag a scrollable.
///
/// Flutter lets touch, stylus and trackpad pan a scrollable; a mouse can only
/// turn the wheel. That default is right on a phone, where the only mouse is one
/// the user plugged in, and wrong on a desktop, where there is no touch screen:
/// a horizontally scrolling surface with no scrollbar has no other way to be
/// moved, so the home page's blog carousel cannot be slid at all.
///
/// The mouse is added on every platform rather than behind a desktop check: a
/// mouse is only ever attached to a desktop or to the web, so the check would
/// spell out the same state at length, and a mouse on a phone should pan too.
class const AppScrollBehavior() extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse};
}
