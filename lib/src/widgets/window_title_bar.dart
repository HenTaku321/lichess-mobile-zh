import 'dart:math' show max;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/service/window_service.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:material_ui/material_ui.dart';

/// The height of the strip the app draws for itself at the top of a desktop window.
///
/// A fixed height rather than one taken from the app bar under it: the two are separate bands, and
/// this one is chrome — a size of its own is what keeps the app's own app bar at the size the app
/// gives it.
const kWindowTitleBarHeight = 36.0;

/// Wraps [child] in the window decoration the app draws for itself.
///
/// Meant for `MaterialApp.builder`, which places it above the app's `Navigator`: a dialog is a
/// route inside that navigator, so it opens below the strip and the window stays closable with one
/// open. Anywhere but Linux this returns [child] untouched; the desktop there draws the title bar,
/// and only the Linux runner takes GTK's away.
///
/// Being above the navigator also means being above the app's only [Overlay], which is inside it:
/// nothing in the strip can float — see [_TitleBarButton].
Widget buildAppWindow(BuildContext context, Widget? child) {
  if (child == null) return const SizedBox.shrink();
  if (Theme.of(context).platform != TargetPlatform.linux) return child;

  final mediaQuery = MediaQuery.of(context);
  return Column(
    children: [
      const WindowTitleBar(),
      Expanded(
        child: MediaQuery(
          // The strip is not the app's to draw on, so it is not the app's to measure either: the
          // height the screens below are told about is what is left of the window. Without this the
          // app would place itself in a screen that includes a band it cannot reach.
          data: mediaQuery.copyWith(
            size: Size(
              mediaQuery.size.width,
              max(0, mediaQuery.size.height - kWindowTitleBarHeight),
            ),
          ),
          child: child,
        ),
      ),
    ],
  );
}

/// The window's title bar, drawn by the app instead of by the desktop.
///
/// Only ever mounted on Linux, through [buildAppWindow]. It exists because that window has no GTK
/// title bar at all: the strip carries the app's name, the gestures that move the window and toggle
/// it between maximized and restored, and the three buttons the desktop would otherwise have drawn.
class const WindowTitleBar({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(windowServiceProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: kWindowTitleBarHeight,
        child: ValueListenableBuilder<bool>(
          // Watched rather than read: the window can be maximized by the desktop's own gestures, and
          // the icon has to follow those too.
          valueListenable: service.maximized,
          builder: (context, maximized, _) {
            return Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    // Opaque: everything under this strip belongs to it, so a click that lands here
                    // is a click on the title bar and not one the app underneath also sees.
                    behavior: HitTestBehavior.opaque,
                    // The compositor does the moving. There is no GTK title bar left to hit, so
                    // this gesture is the only way the window can be dragged at all.
                    onPanStart: (_) => service.startDragging(),
                    // What a double click on a title bar does everywhere else.
                    onDoubleTap: service.toggleMaximized,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(
                          LichessIcons.chess_knight,
                          size: 17,
                          color: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Lichess',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _TitleBarButton(
                  icon: Icons.minimize,
                  label: 'Minimize',
                  onPressed: service.minimize,
                ),
                _TitleBarButton(
                  icon: maximized ? Icons.restore : Icons.crop_square,
                  label: maximized ? 'Restore' : 'Maximize',
                  onPressed: service.toggleMaximized,
                ),
                _TitleBarButton(icon: Icons.close, label: 'Close', onPressed: service.close),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One of the three window buttons at the right of the strip.
///
/// Not an [IconButton]: that one brings a tap target and padding sized for a Material toolbar,
/// which is larger than the whole strip is tall.
///
/// The name is a semantics label rather than a [Tooltip]: a tooltip is drawn in an [Overlay], and
/// the strip is mounted in `MaterialApp.builder`, above the `Navigator` that owns the app's only
/// overlay — a tooltip there asserts instead of appearing. See [buildAppWindow], which puts it
/// there on purpose.
class const _TitleBarButton({
  required final IconData icon,
  required final String label,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: kWindowTitleBarHeight,
          child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
