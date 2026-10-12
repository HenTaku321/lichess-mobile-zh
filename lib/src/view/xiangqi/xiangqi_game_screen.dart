import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// A game of xiangqi against the app's Pikafish, on a board the app draws itself.
///
/// A screen of its own rather than a variant of the chess screens beside it, because the game is not
/// a variant of chess: nine files by ten ranks, a cannon that captures only over a screen, a general
/// that may not leave its palace, a soldier that steps sideways once it has crossed the river. None
/// of that is expressible in `dartchess`, and the board the app plays chess on cannot be talked into
/// it either — `chessground` is eight by eight down to its `File` and `Rank`, with one square size
/// for its whole geometry. So this is the second board in the app: [XiangqiBoard] to draw and read
/// it, the rules under `model/xiangqi` for what may be played, and Pikafish for an opponent.
///
/// Nothing outlives the screen. A chess game against the computer is saved and picked up again on
/// the next visit; this one starts on the initial position every time, which is what a game played
/// in one sitting needs and all that this phase asks for.
class const XiangqiGameScreen() extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiGameScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // Left untranslated on purpose, as a proper name: the game is called xiangqi in the app's own
      // language, and on the board it calls itself 象棋 — the word is printed in its river.
      appBar: AppBar(title: const AppBarTitleText('Xiangqi')),
      body: const _Body(),
    );
  }
}

class const _Body() extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState() extends ConsumerState<_Body> {
  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(xiangqiGameControllerProvider);

    ref.listen(xiangqiGameControllerProvider, (previous, newState) {
      // A game that has just ended says so, half a second late so that the move that ended it is on
      // the board and read before the dialog comes down over it.
      if (previous?.end == null && newState.end != null) {
        Timer(const Duration(milliseconds: 500), () {
          if (!context.mounted) return;
          showAdaptiveDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (context) => XiangqiGameResultDialog(
              state: newState,
              onNewGame: () {
                Navigator.pop(context);
                _showNewGameSheet();
              },
            ),
          );
        });
      }
    });

    final controller = ref.read(xiangqiGameControllerProvider.notifier);

    return WakelockWidget(
      child: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: XiangqiBoard(
                  position: gameState.position,
                  // The player's side is the bottom of the board, so taking black turns the whole
                  // board around.
                  orientation: gameState.playerSide,
                  selected: gameState.selected,
                  moves: gameState.selectedMoves,
                  lastMove: gameState.lastMove,
                  onTapSquare: controller.tapSquare,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _statusText(context, gameState),
              style: TextStyle(fontStyle: FontStyle.italic, color: textShade(context, 0.7)),
            ),
          ),
          BottomBar(
            children: [
              BottomBarButton(
                label: context.l10n.mobileNewGame,
                onTap: _showNewGameSheet,
                icon: CupertinoIcons.add,
              ),
              BottomBarButton(
                label: context.l10n.takeback,
                onTap: gameState.canUndo ? controller.undo : null,
                icon: CupertinoIcons.arrow_uturn_left,
              ),
              BottomBarButton(
                label: context.l10n.resign,
                onTap: gameState.isFinished ? null : _confirmResign,
                icon: CupertinoIcons.flag,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Asks which side to take and how hard the computer should play, then starts over.
  ///
  /// The sheet opens on the game in progress rather than on a default, so that opening it to look
  /// does not quietly mean something else by the time it is dismissed.
  void _showNewGameSheet() {
    final gameState = ref.read(xiangqiGameControllerProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) =>
          _NewGameSheet(side: gameState.playerSide, difficulty: gameState.difficulty),
    );
  }

  void _confirmResign() {
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) => YesNoDialog(
        title: Text(context.l10n.resign),
        content: Text(context.l10n.mobileAreYouSure),
        onYes: () {
          Navigator.pop(context);
          ref.read(xiangqiGameControllerProvider.notifier).resign();
        },
        onNo: () => Navigator.pop(context),
      ),
    );
  }
}

/// What the line under the board says.
///
/// The most important thing that is true, and only one of them: how the game ended if it has, and
/// otherwise what is going on in it. Nothing is said while the computer has the move but has not
/// started thinking — that is a moment rather than a state, and the board is about to move.
String _statusText(BuildContext context, XiangqiGameState state) {
  if (state.end != null) return _resultLabel(state);
  if (state.isEngineThinking) return context.l10n.computerThinking;
  if (state.isPlayerTurn) return context.l10n.yourTurn;
  return '';
}

/// How the game ended, in a sentence — the one thing the dialog's title cannot say.
///
/// The side that is mated or stuck is the side to move, because that is the only question the rules
/// ask: a game is mate because the position to move is mate, not because of how the game arrived
/// there, so there is no loser here to be passed in or worked out separately.
String _resultLabel(XiangqiGameState state) => switch (state.end) {
  .checkmate => '${state.turn.label} is checkmated.',
  // 困毙, and the whole of the difference from chess: a side with no legal move has lost the game,
  // where the same position in chess is a draw.
  .stalemate => '困毙: ${state.turn.label} has no move to make, and that is a loss.',
  .threefoldRepetition => 'The same position came back three times, so the game is drawn.',
  .resign => '${state.resignedBy!.label} resigned.',
  // Only ever asked about a game that has ended, and those are all the ways one does.
  null => '',
};

/// How a finished game ended, and the way to start another.
class const XiangqiGameResultDialog({
  required final XiangqiGameState state,
  required final VoidCallback onNewGame,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final winner = state.winner;

    return AlertDialog.adaptive(
      title: Text(
        winner == null
            ? context.l10n.draw
            : winner == state.playerSide
            ? context.l10n.victory
            : context.l10n.gameOver,
      ),
      content: Text(_resultLabel(state)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.close)),
        TextButton(onPressed: onNewGame, child: Text(context.l10n.mobileNewGame)),
      ],
    );
  }
}

/// The sheet a game is set up in: which side to take, and how hard the computer plays.
class const _NewGameSheet({
  required final XiangqiSide side,
  required final XiangqiDifficulty difficulty,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState() extends ConsumerState<_NewGameSheet> {
  late XiangqiSide _side = widget.side;
  late XiangqiDifficulty _difficulty = widget.difficulty;

  @override
  Widget build(BuildContext context) {
    return BottomSheetScrollableContainer(
      children: [
        ListSection(
          materialFilledCard: true,
          children: [
            SettingsListTile(
              settingsLabel: Text(context.l10n.side),
              settingsValue: _side.label,
              // 让先 is not a setting of its own, because it is not a separate thing: red moves
              // first, so a player who takes black has handed the opening move to the computer. The
              // line is there to say so at the moment the choice is made.
              explanation: _side == .black
                  ? 'Red moves first, so the computer opens the game.'
                  : null,
              onTap: () {
                showChoicePicker<XiangqiSide>(
                  context,
                  title: Text(context.l10n.side),
                  choices: XiangqiSide.values,
                  selectedItem: _side,
                  labelBuilder: (side) => Text(side.label),
                  onSelectedItemChanged: (side) => setState(() => _side = side),
                );
              },
            ),
            SettingsListTile(
              settingsLabel: const Text('Difficulty'),
              settingsValue: _difficulty.label,
              // Three labels and no numbers: what the levels really are is a search limit — see
              // [XiangqiDifficulty] — and a player choosing between them is choosing how long the
              // computer may think, not what it thinks with.
              explanation: 'How long the computer is allowed to think.',
              onTap: () {
                showChoicePicker<XiangqiDifficulty>(
                  context,
                  title: const Text('Difficulty'),
                  choices: XiangqiDifficulty.values,
                  selectedItem: _difficulty,
                  labelBuilder: (difficulty) => Text(difficulty.label),
                  onSelectedItemChanged: (difficulty) => setState(() => _difficulty = difficulty),
                );
              },
            ),
          ],
        ),
        Padding(
          padding: Styles.horizontalBodyPadding,
          child: FilledButton(
            onPressed: () {
              ref
                  .read(xiangqiGameControllerProvider.notifier)
                  .startNewGame(side: _side, difficulty: _difficulty);
              Navigator.pop(context);
            },
            child: Text(context.l10n.play, style: Styles.bold),
          ),
        ),
      ],
    );
  }
}
