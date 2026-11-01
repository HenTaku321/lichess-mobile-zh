import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Continue from the displayed position, not the original game's live endpoint. A new local
/// route owns its game; returning leaves the analysis tree and its selected branch untouched.
Future<void> showXiangqiContinueFromHereMenu(
  BuildContext context,
  XiangqiPosition position, {
  XiangqiSide orientation = XiangqiSide.red,
}) => showAdaptiveActionSheet<void>(
  context: context,
  actions: [
    BottomSheetAction(
      makeLabel: (context) => Text(context.l10n.playAgainstComputer),
      onPressed: () => Navigator.of(
        context,
      ).push(XiangqiGameScreen.buildRoute(initialFen: position.toFen(), initialSide: orientation)),
    ),
    BottomSheetAction(
      makeLabel: (context) => Text(context.l10n.mobileOverTheBoard),
      onPressed: () =>
          Navigator.of(context)
              .push(XiangqiOverTheBoardScreen.buildRoute(initialFen: position.toFen())),
    ),
  ],
);
