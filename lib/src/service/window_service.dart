import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:logging/logging.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger('WindowService');

/// The size the window opens at the first time, and what a record that lost its size falls back to.
///
/// Kept in step by hand with `gtk_window_set_default_size` in `linux/runner/my_application.cc`,
/// which is where a window with nothing stored gets its size.
const kDefaultWindowSize = Size(1280, 720);

/// The smallest size the app is usable at, and the floor every restored size is raised to.
const kMinimumWindowSize = Size(480, 480);

/// How much of a restored window has to land inside a work area for its position to be kept.
///
/// A window overlapping a screen by a sliver is one whose title bar cannot be reached, and on the
/// desktop this app is built for the board itself is what has to be visible.
const _minVisibleOverlap = 100.0;

/// The window's size, and where it is when that is known.
///
/// Immutable, and only about numbers: this is what gets read back from disk, so the rules deciding
/// whether a stored one can still be used live apart from it, in [clampWindowGeometry]. Two of them
/// are equal when they describe the same window, which is what makes "the clamp changed nothing"
/// something a test can say.
@immutable
class const WindowGeometry({
  /// The size of the window, in logical pixels — which is the unit both plugins speak on Linux.
  required final Size size,

  /// The top-left corner, or null where the position is not known: a window can be at 0,0, so
  /// "unknown" has to be told apart from it.
  final Offset? position,

  final bool isMaximized = false,
}) {
  /// The geometry of a window currently occupying [bounds].
  new fromBounds(Rect bounds) : this(size: bounds.size, position: bounds.topLeft);

  /// Reads a geometry back from the JSON string stored under the preference key.
  ///
  /// Null for anything that is not a usable geometry — absent, not JSON, missing fields, NaN,
  /// negatives, one coordinate without the other. All of those mean the same thing to the caller:
  /// there is nothing to restore, so the window opens the way the runner set it up.
  static WindowGeometry? tryDecode(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final width = _positive(decoded['width']);
    final height = _positive(decoded['height']);
    if (width == null || height == null) return null;

    // The two coordinates are written together or not at all, so half a pair is not a position the
    // window was ever at: it is a damaged record, and the desktop gets to place the window.
    final x = _finite(decoded['x']);
    final y = _finite(decoded['y']);

    return WindowGeometry(
      size: Size(width, height),
      position: x != null && y != null ? Offset(x, y) : null,
      isMaximized: decoded['maximized'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'width': size.width,
    'height': size.height,
    if (position != null) 'x': position!.dx,
    if (position != null) 'y': position!.dy,
    'maximized': isMaximized,
  };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is WindowGeometry &&
      other.size == size &&
      other.position == position &&
      other.isMaximized == isMaximized;

  @override
  int get hashCode => Object.hash(size, position, isMaximized);

  @override
  String toString() =>
      'WindowGeometry(${size.width}x${size.height} at $position'
      '${isMaximized ? ', maximized' : ''})';
}

double? _finite(Object? value) => value is num && value.isFinite ? value.toDouble() : null;

double? _positive(Object? value) {
  final number = _finite(value);
  return number != null && number > 0 ? number : null;
}

/// The parts of [displays] a window can be placed in: each screen minus its panels and docks.
///
/// A display the platform did not report a work area for is left out rather than guessed at.
List<Rect> workAreasOf(List<Display> displays) => [
  for (final display in displays)
    if (display.visiblePosition != null && display.visibleSize != null)
      display.visiblePosition! & display.visibleSize!,
];

/// Fits [geometry] to the screens that are attached now.
///
/// The size is raised to [kMinimumWindowSize] and capped at the largest work area. A position is
/// kept only where the window would land inside a work area with [_minVisibleOverlap] to spare in
/// both directions; anywhere else it is dropped and the desktop places the window, which is the
/// only other answer that ends with the window reachable.
///
/// With no work areas to measure against, nothing is clamped but the minimum size: a question that
/// went unanswered is not evidence that the geometry is wrong.
WindowGeometry clampWindowGeometry(WindowGeometry geometry, {required List<Rect> workAreas}) {
  const floors = kMinimumWindowSize;
  if (workAreas.isEmpty) {
    return WindowGeometry(
      size: Size(max(geometry.size.width, floors.width), max(geometry.size.height, floors.height)),
      position: geometry.position,
      isMaximized: geometry.isMaximized,
    );
  }

  final widest = workAreas.map((area) => area.width).reduce(max);
  final tallest = workAreas.map((area) => area.height).reduce(max);
  final size = Size(
    _fit(geometry.size.width, floors.width, widest),
    _fit(geometry.size.height, floors.height, tallest),
  );

  final position = geometry.position;
  final visible =
      position != null &&
      workAreas.any((area) {
        final overlap = (position & size).intersect(area);
        return overlap.width >= _minVisibleOverlap && overlap.height >= _minVisibleOverlap;
      });

  return WindowGeometry(
    size: size,
    position: visible ? position : null,
    isMaximized: geometry.isMaximized,
  );
}

/// Clamps [value] into `[floor, ceiling]`, tolerating a ceiling below the floor: a screen smaller
/// than the smallest usable window still gets the smallest usable window, there being nothing
/// better to offer.
double _fit(double value, double floor, double ceiling) => value.clamp(floor, max(floor, ceiling));

/// The part of [geometry] worth storing in this session.
///
/// The position is dropped where the session cannot put it back, so that what is on disk is never a
/// window position the app has no way of returning to: on Wayland a stored one would be replayed as
/// whatever the compositor chose, which is not the same place and would not be the truth about it.
WindowGeometry geometryToStore(WindowGeometry geometry, {required bool canRestorePosition}) =>
    canRestorePosition
    ? geometry
    : WindowGeometry(size: geometry.size, isMaximized: geometry.isMaximized);

/// Whether a session of [sessionType] lets a client place its own window.
///
/// Wayland does not: there a client cannot ask where it is (`gtk_window_get_position` answers 0,0)
/// and cannot ask to be moved (`gtk_window_move` is a no-op). A position saved in such a session
/// is one the window was never at, and restoring it would not work anyway — which is why the
/// session type decides whether a position is written at all, rather than being recorded and
/// thrown away later. X11 does let a client place itself, and there the position is both saved and
/// restored.
bool isPositionRestorable(String? sessionType) => sessionType?.toLowerCase() == 'x11';

/// This session's answer, taken from the environment the desktop set.
bool get canRestoreWindowPosition => isPositionRestorable(Platform.environment['XDG_SESSION_TYPE']);

/// The one instance the app runs, also reachable as [windowServiceProvider].
final windowService = WindowService();

final windowServiceProvider = Provider<WindowService>(
  (Ref ref) => windowService,
  name: 'WindowServiceProvider',
);

/// Remembers the window's size — and, where the session allows it, its position — across restarts.
///
/// Linux only: everywhere else the platform's own window decoration is the one the app wants, and
/// nothing here is called at all.
///
/// The window has no title bar of GTK's to drag or to click, so this is also where the app's own
/// title bar gets the operations it needs; see `widgets/window_title_bar.dart`.
///
/// The plugin is used for its geometry and its window operations only. Its `setAsFrameless` and
/// `setTitleBarStyle(hidden)` are deliberately never called: with no header bar of GTK's to hide,
/// both of them fall back to `gtk_window_set_decorated(window, FALSE)`, which takes the window's
/// drop shadow and its edge resizing grips with it. The runner keeps CSD and installs an empty
/// title bar instead — see its comment.
class WindowService() with WindowListener {
  static const _preferenceKey = 'window_geometry_v1';

  /// Long enough that dragging a window edge does not write a preference per frame, short enough
  /// that quitting straight after a resize still remembers it.
  static const _saveDebounce = Duration(milliseconds: 600);

  Timer? _saveTimer;

  /// The geometry the window last had while it was not maximized. A maximized window reports the
  /// maximized size, so this is the only record of the size to go back to, and it must not be
  /// overwritten while the flag is set.
  WindowGeometry? _normalGeometry;

  /// Whether the window is maximized, for the app's title bar.
  ///
  /// A notifier rather than a getter because the state also changes without the app asking: the
  /// desktop's own gestures and shortcuts maximize the window too, and the title bar's icon has to
  /// follow those as well as its own button.
  final maximized = ValueNotifier<bool>(false);

  /// Sizes and places the window where it was left.
  ///
  /// Called from `main` before `runApp`, because the runner only shows the window once Flutter has
  /// drawn a frame: doing this later would show the default size first and then jump.
  ///
  /// [restorePosition] overrides the session's answer, for tests. By default the position is
  /// restored only in a session that can place its own window — see [isPositionRestorable].
  ///
  /// Never throws. A missing plugin or a failing channel leaves the window exactly as the runner
  /// set it up, which is a far better outcome than an app that does not start; the reason lands in
  /// Settings → app log.
  Future<void> restore({bool? restorePosition}) async {
    if (defaultTargetPlatform != TargetPlatform.linux) return;
    final placePosition = restorePosition ?? canRestoreWindowPosition;

    try {
      await windowManager.ensureInitialized();
      // Every path below needs this, including the one that restores nothing.
      await windowManager.setMinimumSize(kMinimumWindowSize);

      final stored = WindowGeometry.tryDecode(
        LichessBinding.instance.sharedPreferences.getString(_preferenceKey),
      );
      if (stored == null) return;

      final geometry = clampWindowGeometry(stored, workAreas: await _workAreas());

      // In this order, and before the window is shown: the minimum first so a restored size is
      // never below it, then the size, then the position, and the maximized state last, since a
      // maximized window has no use for the size and position just set.
      await windowManager.setSize(geometry.size);
      if (placePosition && geometry.position != null) {
        await windowManager.setPosition(geometry.position!);
      }
      _normalGeometry = WindowGeometry(
        size: geometry.size,
        position: placePosition ? geometry.position : null,
      );
      maximized.value = geometry.isMaximized;
      if (geometry.isMaximized) {
        await windowManager.maximize();
      }
    } catch (error) {
      _logger.warning('Could not restore the window geometry', error);
    }
  }

  /// Starts recording what the user does to the window. Called from `_AppState.initState`, with
  /// the other long-running services.
  Future<void> start() async {
    if (defaultTargetPlatform != TargetPlatform.linux) return;
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      // One reading now, so that a window maximized a moment later has something to go back to.
      final alreadyMaximized = await windowManager.isMaximized();
      maximized.value = alreadyMaximized;
      if (!alreadyMaximized) {
        _normalGeometry = WindowGeometry.fromBounds(await windowManager.getBounds());
      }
    } catch (error) {
      _logger.warning('Could not start watching the window geometry', error);
    }
  }

  /// Minimizes the window, for the app's own title bar.
  Future<void> minimize() => _guard(windowManager.minimize(), 'minimize');

  /// Toggles between maximized and the size it had before, for the app's own title bar.
  Future<void> toggleMaximized() async {
    try {
      final nowMaximized = !await windowManager.isMaximized();
      if (nowMaximized) {
        await windowManager.maximize();
      } else {
        await windowManager.unmaximize();
      }
      // The plugin's event says the same thing a moment later and is what tells the icon about a
      // change made by the desktop; noting it here too is what tells it about this one without
      // waiting, and the second note changes nothing.
      _noteMaximized(nowMaximized);
    } catch (error) {
      _logger.warning('Could not maximize the window', error);
    }
  }

  /// Closes the window, for the app's own title bar.
  ///
  /// The pending save is written first: the window goes with the process, and a resize in the last
  /// fraction of a second before that would otherwise be lost. The write reaches the disk before
  /// the close does, so the next start finds it.
  Future<void> close() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (maximized.value) {
      await _saveMaximized();
    } else {
      await _saveNormal();
    }
    await _guard(windowManager.close(), 'close');
  }

  /// Lets the user drag the window by the app's own title bar.
  ///
  /// The compositor does the moving; this only asks it to. On a session that hands window placement
  /// to the compositor this is the one way the gesture exists at all, since there is no GTK title
  /// bar left to hit.
  Future<void> startDragging() => _guard(windowManager.startDragging(), 'drag');

  @override
  void onWindowResize() => _scheduleSave();

  @override
  void onWindowMove() => _scheduleSave();

  @override
  void onWindowMaximize() => _noteMaximized(true);

  @override
  void onWindowUnmaximize() => _noteMaximized(false);

  /// Notes that the window is or is not maximized, wherever that was learned from — the plugin's
  /// event or the app's own button — and writes the record that goes with it.
  void _noteMaximized(bool value) {
    if (maximized.value == value) return;
    maximized.value = value;
    unawaited(value ? _saveMaximized() : _saveRestored());
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(_saveNormal()));
  }

  /// Records the window as it is now, unless it is maximized: the size a maximized window reports
  /// is the maximized one, and writing it would lose the size to come back to.
  Future<void> _saveNormal() async {
    try {
      if (await windowManager.isMaximized()) return;
      final geometry = WindowGeometry.fromBounds(await windowManager.getBounds());
      _normalGeometry = geometry;
      await _write(geometry);
    } catch (error) {
      _logger.warning('Could not remember the window geometry', error);
    }
  }

  /// Records that the window is maximized, with the size and position it had before — which is the
  /// whole point of the record: what is maximized has to be known to be put back, and the size it
  /// was maximized from has to survive not being readable from the window while it is.
  Future<void> _saveMaximized() async {
    try {
      final normal =
          _normalGeometry ??
          WindowGeometry.tryDecode(
            LichessBinding.instance.sharedPreferences.getString(_preferenceKey),
          ) ??
          const WindowGeometry(size: kDefaultWindowSize);
      await _write(WindowGeometry(size: normal.size, position: normal.position, isMaximized: true));
    } catch (error) {
      _logger.warning('Could not remember that the window is maximized', error);
    }
  }

  /// Records the window as no longer maximized, at the size it had before it was.
  ///
  /// The size comes from [_normalGeometry] rather than from a reading of the window: the moment the
  /// event arrives, GTK may still report the maximized size, and storing that as the size to come
  /// back to would open every later start at maximized size without the window being maximized. The
  /// resize that follows the restore arrives as an ordinary event and corrects the record, so a
  /// wrong reading here is not one that lasts.
  Future<void> _saveRestored() async {
    try {
      final normal = _normalGeometry ?? WindowGeometry.fromBounds(await windowManager.getBounds());
      await _write(WindowGeometry(size: normal.size, position: normal.position));
    } catch (error) {
      _logger.warning('Could not remember the restored window geometry', error);
    }
  }

  /// Writes [geometry] under the preference key.
  ///
  /// What goes in is [geometryToStore], which drops the position where the session cannot restore
  /// one.
  Future<void> _write(WindowGeometry geometry) async {
    final record = geometryToStore(geometry, canRestorePosition: canRestoreWindowPosition);
    await LichessBinding.instance.sharedPreferences.setString(_preferenceKey, record.encode());
  }

  Future<List<Rect>> _workAreas() async {
    try {
      return workAreasOf(await screenRetriever.getAllDisplays());
    } catch (error) {
      _logger.warning('Could not read the displays; using the geometry as stored', error);
      return const [];
    }
  }

  Future<void> _guard(Future<void> action, String what) async {
    try {
      await action;
    } catch (error) {
      _logger.warning('Could not $what the window', error);
    }
  }
}
