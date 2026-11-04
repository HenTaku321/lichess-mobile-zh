import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:material_ui/material_ui.dart';

/// The complete computer-game header is shared; board adapters supply the mode and settings.
/// The body remains in its original session scope, so this shell never owns a game or an engine.
class const ComputerGameScaffold({
  required final bool practiceMode,
  required final VoidCallback onSettings,
  required final Widget body,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppBarTitleText(
        practiceMode ? context.l10n.practiceWithComputer : context.l10n.playAgainstComputer,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: context.l10n.settingsSettings,
          onPressed: onSettings,
        ),
      ],
    ),
    body: body,
  );
}

/// Computer-game actions have one ordering and presentation. Each controller supplies nullable
/// callbacks for its real capabilities, rather than the shell guessing rules or permissions.
class const ComputerGameBottomBar({
  required final VoidCallback onMenu,
  final VoidCallback? onResign,
  final VoidCallback? onTakeback,
  final VoidCallback? onHint,
  final bool hintVisible = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BottomBar(
    children: [
      BottomBarButton(label: context.l10n.menu, icon: Icons.menu, onTap: onMenu),
      BottomBarButton(label: context.l10n.resign, icon: CupertinoIcons.flag, onTap: onResign),
      BottomBarButton(
        label: context.l10n.takeback,
        icon: CupertinoIcons.arrow_uturn_left,
        onTap: onTakeback,
      ),
      BottomBarButton(
        label: context.l10n.getAHint,
        icon: CupertinoIcons.lightbulb,
        onTap: onHint,
        highlighted: hintVisible,
      ),
    ],
  );
}

Future<void> showComputerGameMenu(
  BuildContext context, {
  required VoidCallback onFlipBoard,
  required VoidCallback onNewGame,
  VoidCallback? onAnalysis,
  VoidCallback? onResign,
}) => showAdaptiveActionSheet<void>(
  context: context,
  actions: [
    BottomSheetAction(makeLabel: (context) => Text(context.l10n.flipBoard), onPressed: onFlipBoard),
    if (onAnalysis != null)
      BottomSheetAction(makeLabel: (context) => Text(context.l10n.analysis), onPressed: onAnalysis),
    if (onResign != null)
      BottomSheetAction(makeLabel: (context) => Text(context.l10n.resign), onPressed: onResign),
    BottomSheetAction(
      makeLabel: (context) => Text(context.l10n.mobileNewGame),
      onPressed: onNewGame,
    ),
  ],
);
