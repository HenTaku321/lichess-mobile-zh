import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:material_ui/material_ui.dart';

/// Identity typography and alignment, independent of accounts, piece colours and ratings.
class const PlayerIdentityLine({
  required final String name,
  final ClockPosition clockPosition = ClockPosition.right,
  final bool compact = false,
  final List<Widget> beforeName = const [],
  final List<Widget> afterName = const [],
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fontSize = compact
        ? 13.0
        : isShortVerticalScreen(context)
        ? 15.0
        : 16.0;
    return Row(
      mainAxisAlignment: clockPosition == ClockPosition.right
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        ...beforeName,
        Flexible(
          child: Tooltip(
            message: name,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        ...afterName,
      ],
    );
  }
}

/// Common allocation of player content and clock. The content slot also hosts confirmation,
/// practice feedback and game-specific identity decorations; no account or clock is read here.
class const PlayerTable({
  required final Widget content,
  final Widget? clock,
  final ClockPosition clockPosition = ClockPosition.right,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (clock != null && clockPosition == ClockPosition.left) Flexible(flex: 3, child: clock!),
      Expanded(
        flex: 7,
        child: Padding(padding: const EdgeInsets.only(right: 16), child: content),
      ),
      if (clock != null && clockPosition == ClockPosition.right) Flexible(flex: 3, child: clock!),
    ],
  );
}
