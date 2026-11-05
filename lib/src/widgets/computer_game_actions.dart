import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/game_action.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:material_ui/material_ui.dart';

/// The complete computer-game header is shared; board adapters supply the mode and settings.
/// The body remains in its original session scope, so this shell never owns a game or an engine.
class const ComputerGameScaffold({
  required final bool practiceMode,
  required final GameActionCallback onSettings,
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
        GameActionButton(
          key: const ValueKey('computer-settings'),
          iconOnly: true,
          action: GameActionSpec(
            id: 'settings',
            label: (context) => context.l10n.settingsSettings,
            icon: Icons.settings,
            onInvoke: onSettings,
          ),
        ),
      ],
    ),
    body: body,
  );
}

/// Computer-game actions have one ordering and presentation. Each controller supplies nullable
/// callbacks for its real capabilities, rather than the shell guessing rules or permissions.
class const ComputerGameBottomBar({
  required final GameActionCallback onMenu,
  final GameActionCallback? onResign,
  final GameActionCallback? onTakeback,
  final GameActionCallback? onHint,
  final bool hintVisible = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      GameActionSpec(
        id: 'menu',
        label: (context) => context.l10n.menu,
        icon: Icons.menu,
        onInvoke: onMenu,
      ),
      GameActionSpec(
        id: 'resign',
        label: (context) => context.l10n.resign,
        icon: CupertinoIcons.flag,
        onInvoke: onResign,
      ),
      GameActionSpec(
        id: 'takeback',
        label: (context) => context.l10n.takeback,
        icon: CupertinoIcons.arrow_uturn_left,
        onInvoke: onTakeback,
      ),
      GameActionSpec(
        id: 'hint',
        label: (context) => context.l10n.getAHint,
        icon: CupertinoIcons.lightbulb,
        onInvoke: onHint,
        highlighted: hintVisible,
      ),
    ];
    return BottomBar(
      children: [
        for (final action in actions) GameActionButton(key: ValueKey(action.id), action: action),
      ],
    );
  }
}

Future<void> showComputerGameMenu(
  BuildContext context, {
  required VoidCallback onFlipBoard,
  required FutureOr<void> Function() onNewGame,
  VoidCallback? onAnalysis,
  VoidCallback? onResign,
}) async {
  final operation = Completer<void>();
  Future<void> run(FutureOr<void> Function() callback) async {
    try {
      await callback();
      if (!operation.isCompleted) operation.complete();
    } on Object catch (error, stackTrace) {
      if (!operation.isCompleted) operation.completeError(error, stackTrace);
    }
  }

  await showAdaptiveActionSheet<void>(
    context: context,
    actions: [
      BottomSheetAction(
        makeLabel: (context) => Text(context.l10n.flipBoard),
        dismissOnPress: false,
        onPressedAsync: () async {
          if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
            Navigator.of(context).pop();
          }
          await run(onFlipBoard);
        },
      ),
      if (onAnalysis != null)
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.analysis),
          dismissOnPress: false,
          onPressedAsync: () async {
            if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
              Navigator.of(context).pop();
            }
            await run(onAnalysis);
          },
        ),
      if (onResign != null)
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.resign),
          dismissOnPress: false,
          onPressedAsync: () async {
            if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
              Navigator.of(context).pop();
            }
            await run(onResign);
          },
        ),
      BottomSheetAction(
        makeLabel: (context) => Text(context.l10n.mobileNewGame),
        dismissOnPress: false,
        onPressedAsync: () async {
          if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
            Navigator.of(context).pop();
          }
          await run(onNewGame);
        },
      ),
    ],
  );
  await operation.future;
}
