import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
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
/// What the screen offers is what the chess screens offer around their own board: a move list, an
/// evaluation bar, a hint, the board's appearance settings, and the move written down in the
/// notation the game is read in. The one thing it does not have is a way back through the game: the
/// controller keeps the moves and takes the last one back, but it has no cursor to step to an
/// earlier position, so the move list is a list and not a control — see the `onSelectMove` argument
/// of [XiangqiGameLayout].
///
/// Nothing outlives the screen. A chess game against the computer is saved and picked up again on
/// the next visit; this one starts on the initial position every time, which is what a game played
/// in one sitting needs and all that this phase asks for.
class const XiangqiGameScreen() extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiGameScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // The game's own name, translated like every other: 象棋 is what the board calls itself, but
      // the app speaks of it in the reader's language. See `mobileXiangqi`.
      appBar: AppBar(
        title: AppBarTitleText(context.l10n.mobileXiangqi),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: context.l10n.settingsSettings,
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (_) =>
                    _XiangqiGameSettingsSheet(onNewGame: () => _showNewGameSheet(context, ref)),
              );
            },
          ),
        ],
      ),
      body: const _Body(),
    );
  }
}

/// Asks which side to take and how hard the computer should play, then starts over.
///
/// The sheet opens on the game in progress rather than on a default, so that opening it to look
/// does not quietly mean something else by the time it is dismissed.
void _showNewGameSheet(BuildContext context, WidgetRef ref) {
  final gameState = ref.read(xiangqiGameControllerProvider);
  showModalBottomSheet<void>(
    context: context,
    builder: (context) =>
        _NewGameSheet(side: gameState.playerSide, difficulty: gameState.difficulty),
  );
}

/// Whether the board is drawn from the player's side or turned around.
///
/// A screen of its own rather than a field of the game, because it is a way of looking at the board
/// and not a fact about the game: turning the board around must not change which side the player is,
/// or the game would be handed to the other side by a glance.
final _isBoardFlippedProvider = NotifierProvider.autoDispose<_IsBoardFlippedNotifier, bool>(
  _IsBoardFlippedNotifier.new,
  name: 'IsBoardFlippedProvider',
);

class _IsBoardFlippedNotifier() extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void toggle() {
    state = !state;
  }
}

/// How hard the computer plays, as the app's own words for it.
///
/// The three names are the view's to say and not the model's — see [XiangqiDifficulty] — and this is
/// the one place any of them is turned into text.
String _difficultyLabel(BuildContext context, XiangqiDifficulty difficulty) => switch (difficulty) {
  .easy => context.l10n.mobileXiangqiEasy,
  .medium => context.l10n.mobileXiangqiMedium,
  .hard => context.l10n.mobileXiangqiHard,
};

class const _Body() extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState() extends ConsumerState<_Body> {
  /// The position the hint on the board was asked for, or null when none was.
  ///
  /// The hint the engine found is only ever about one position, and the game moves on from it the
  /// moment either side plays: holding the position beside it is what makes the hint disappear then,
  /// rather than hanging over a board it no longer says anything about.
  XiangqiPosition? _hintPosition;

  /// The position the evaluation running in the engine was started for.
  ///
  /// The analysis provider is watched rather than read, so it lives exactly as long as this screen
  /// does; this is what keeps a rebuild from asking for the same position twice and dropping the
  /// search that is already running on it.
  XiangqiPosition? _evaluatedPosition;

  @override
  void initState() {
    super.initState();
    // `ref.listen` never fires for the value that is already there, and the game this screen opens
    // on is exactly that value: the first evaluation has to be asked for rather than waited for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncEvaluation(ref.read(xiangqiGameControllerProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(xiangqiGameControllerProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final analysisState = ref.watch(xiangqiEngineAnalysisProvider);
    final evalEnabled = ref.watch(engineEvaluationPreferencesProvider.select((p) => p.isEnabled));
    final isBoardFlipped = ref.watch(_isBoardFlippedProvider);

    ref.listen(xiangqiGameControllerProvider, (previous, newState) {
      // A game that has just ended says so, half a second late so that the move that ended it is on
      // the board and read before the dialog comes down over it.
      if (previous?.end == null && newState.end != null) {
        Timer(const Duration(milliseconds: 500), () {
          if (!context.mounted) return;
          showAdaptiveDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (dialogContext) => XiangqiGameResultDialog(
              state: newState,
              onNewGame: () {
                Navigator.pop(dialogContext);
                _showNewGameSheet(context, ref);
              },
            ),
          );
        });
      }
      _syncEvaluation(newState);
    });

    final controller = ref.read(xiangqiGameControllerProvider.notifier);
    final orientation = isBoardFlipped ? gameState.playerSide.opposite : gameState.playerSide;
    final hintMove = _hintPosition == gameState.position ? analysisState.hint?.move : null;
    // The same preference the chess game against the computer reads, because it is the same thing:
    // a game against the computer, with the pieces taken off the board.
    final blindfoldMode = ref.watch(
      offlineComputerGamePreferencesProvider.select((p) => p.blindfoldMode),
    );

    // The engine is the app's own shared one, and leaving the screen does not mean the player wants
    // it searching: losing focus stops the evaluation, exactly as the chess screen's own detector
    // does, and regaining it asks for the evaluation again rather than leaving the bar stale.
    //
    // The detector reports a widget that has gone invisible on its way out as well as on its way
    // in, so both callbacks check the context is still mounted before reading anything through the
    // ref: a read on a state that is being torn down is refused outright.
    Widget content = FocusDetector(
      onFocusLost: () {
        if (!context.mounted) return;
        _evaluatedPosition = null;
        if (ref.read(xiangqiEngineAnalysisProvider).isBusy) {
          ref.read(xiangqiEngineAnalysisProvider.notifier).stopEvaluation();
        }
      },
      onFocusRegained: () {
        if (!context.mounted) return;
        _syncEvaluation(ref.read(xiangqiGameControllerProvider));
      },
      child: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: XiangqiGameLayout(
                board: BrightnessHueFilter(
                  brightness: boardPrefs.brightness,
                  hue: boardPrefs.hue,
                  child: XiangqiBoard(
                    position: gameState.position,
                    orientation: orientation,
                    selected: gameState.selected,
                    // The legal moves are the board's own setting, and the last move is the
                    // highlights one: both are things the board draws, so both are taken away by
                    // turning them off.
                    moves: boardPrefs.showLegalMoves
                        ? gameState.selectedMoves
                        : const IListConst([]),
                    lastMove: boardPrefs.boardHighlights ? gameState.lastMove : null,
                    onTapSquare: controller.tapSquare,
                    // A drag is the same two taps it would have been, in the order they were made:
                    // the piece is picked up where it was let go of, and put down where it was
                    // dropped. A drag that cannot be played that way moves nothing, because the
                    // second tap finds the first one's piece with nowhere to go and does what a tap
                    // on an empty square does.
                    onDragMove: (from, to) {
                      controller.tapSquare(from);
                      controller.tapSquare(to);
                    },
                    animationDuration: boardPrefs.pieceAnimationDuration,
                    showCoordinates: boardPrefs.coordinates,
                    showLastMove: boardPrefs.boardHighlights,
                    showBorder: boardPrefs.showBorder,
                    hint: hintMove,
                    blindfoldMode: blindfoldMode,
                    // The two drag settings the sheet above offers: a dragged piece is magnified or
                    // not, and the square it is over is marked the way the player asked for.
                    magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
                    dragTargetKind: boardPrefs.dragTargetKind,
                    // The board is a citizen of the app's own theming, not a board of its own: it
                    // wears the colours of whichever chessboard theme the player has picked. See
                    // [XiangqiBoardStyle.fromChessboardColorScheme] for the mapping, and what it
                    // cannot take.
                    style: XiangqiBoardStyle.fromChessboardColorScheme(
                      boardPrefs.boardTheme.colors,
                    ),
                  ),
                ),
                topTable: _PlayerRow(
                  icon: Icons.smart_toy,
                  // The engine's own name, which is a proper name and the same in every language:
                  // it is the program that is playing, not a description of it. How hard it is
                  // playing is a setting, and the sheet is where a setting is read.
                  name: 'Pikafish',
                  thinking: gameState.isEngineThinking,
                  status: '',
                ),
                bottomTable: _PlayerRow(
                  icon: Icons.person,
                  thinking: false,
                  status: _statusText(context, gameState),
                ),
                evalGauge: evalEnabled
                    ? XiangqiEvalGauge(
                        // A bar with nothing to report yet is drawn level rather than left out:
                        // the engine is about to answer, and a bar that came and went on every
                        // move would flicker.
                        redWinProbability: analysisState.evaluation?.redWinProbability ?? 0.5,
                        orientation: orientation,
                        evaluation: analysisState.evaluation,
                      )
                    : null,
                moves: xiangqiGameNotation(gameState.positions, gameState.moves),
                // The game's own counting, which is what the list marks: the controller has no
                // cursor to point at an earlier move, so the move it marks is always the one just
                // played.
                currentMoveIndex: gameState.moves.length,
                // Nothing to step to — see [XiangqiGameController]: a move can be taken back, but
                // there is no way to walk the game back and forth, so the list is a list and not a
                // control.
                onSelectMove: null,
                userActionsBar: BottomBar(
                  children: [
                    BottomBarButton(
                      label: context.l10n.mobileNewGame,
                      onTap: () => _showNewGameSheet(context, ref),
                      icon: CupertinoIcons.add,
                    ),
                    BottomBarButton(
                      label: context.l10n.takeback,
                      onTap: gameState.canUndo ? controller.undo : null,
                      icon: CupertinoIcons.arrow_uturn_left,
                    ),
                    BottomBarButton(
                      label: context.l10n.getAHint,
                      onTap: _canGetHint(gameState, analysisState)
                          ? () => _requestHint(gameState)
                          : null,
                      icon: CupertinoIcons.lightbulb,
                      highlighted: hintMove != null,
                    ),
                    BottomBarButton(
                      label: context.l10n.resign,
                      onTap: gameState.isFinished ? null : _confirmResign,
                      icon: CupertinoIcons.flag,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Immersive mode is the setting that hides the system bars, so it wraps the screen only when it
    // is on: the widget both hides and shows them, and a switch that is off must not be answered
    // with a focus change that shows them again. The wakelock is outside it and unconditional —
    // a board that goes to sleep mid-game is a board nobody is playing.
    if (boardPrefs.immersiveModeWhilePlaying ?? false) {
      content = ImmersiveModeWidget(child: content);
    }

    return WakelockWidget(child: content);
  }

  /// Starts or stops the evaluation so that it runs exactly when there is something to show and
  /// nobody else is using the engine.
  ///
  /// The engine is shared with the opponent and runs one search at a time, so the bar is only ever
  /// fed while the computer is not thinking: asking at any other moment would stop the opponent's
  /// search and lose it its move. The analysis provider says the same thing from its own side — see
  /// [xiangqiEngineAnalysisProvider] — and this is the caller's half of that contract.
  ///
  /// Nothing is evaluated once the game is over: the bar is about a game in progress, and the last
  /// thing a finished one needs is a search started under a result dialog.
  void _syncEvaluation(XiangqiGameState gameState) {
    final shouldEvaluate =
        ref.read(engineEvaluationPreferencesProvider).isEnabled &&
        !gameState.isEngineThinking &&
        gameState.isPlayerTurn &&
        !gameState.isFinished;

    if (!shouldEvaluate) {
      _evaluatedPosition = null;
      if (ref.read(xiangqiEngineAnalysisProvider).isBusy) {
        ref.read(xiangqiEngineAnalysisProvider.notifier).stopEvaluation();
      }
      return;
    }

    if (_evaluatedPosition == gameState.position) return;
    _evaluatedPosition = gameState.position;
    ref.read(xiangqiEngineAnalysisProvider.notifier).startEvaluation(gameState.position);
  }

  /// Whether a hint may be asked for now.
  ///
  /// The same conditions the evaluation is held to, and the same reason: the engine is one engine
  /// and it is not the player's while the computer is thinking. A hint whose position has gone is
  /// no hint, so the search is not restarted when the board moves on — the old one is left to be
  /// superseded.
  bool _canGetHint(XiangqiGameState gameState, XiangqiEngineAnalysisState analysisState) {
    return !gameState.isFinished &&
        !gameState.isEngineThinking &&
        gameState.isPlayerTurn &&
        !analysisState.isBusy;
  }

  void _requestHint(XiangqiGameState gameState) {
    _hintPosition = gameState.position;
    unawaited(ref.read(xiangqiEngineAnalysisProvider.notifier).requestHint(gameState.position));
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

/// One of the two rows beside the board: the computer above it, and the player below.
///
/// Neither row has a clock or a material count to show — a xiangqi game here is played untimed, and
/// the pieces that have been taken are on the board rather than in a tally. What is left is the name
/// of whoever is to move and what the game is doing, which is what the line under the board used to
/// say on its own.
class const _PlayerRow({
  required final IconData icon,

  /// The name to print, or null for a row that has none of its own — the player's.
  final String? name,

  /// Whether to show the hourglass that says the computer has the move and is thinking about it.
  final bool thinking = false,

  /// The line under the name: what the game is doing, in one sentence or none.
  final String status = '',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = this.name;

    return Row(
      children: [
        Icon(icon, size: 32, color: textShade(context, 0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (name != null) Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (thinking) ...const [SizedBox(width: 8), Icon(Icons.hourglass_top, size: 16)],
                ],
              ),
              if (status.isNotEmpty)
                Text(
                  status,
                  style: TextStyle(fontStyle: FontStyle.italic, color: textShade(context, 0.7)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the player's own row says.
///
/// The most important thing that is true, and only one of them: how the game ended if it has, and
/// otherwise what is going on in it. Nothing is said while the computer has the move but has not
/// started thinking — that is a moment rather than a state, and the board is about to move.
String _statusText(BuildContext context, XiangqiGameState state) {
  if (state.end != null) return _resultLabel(context, state);
  if (state.isEngineThinking) return context.l10n.computerThinking;
  if (state.isPlayerTurn) return context.l10n.yourTurn;
  return '';
}

/// How the game ended, in a sentence — the one thing the dialog's title cannot say.
///
/// The side that is mated or stuck is the side to move, because that is the only question the rules
/// ask: a game is mate because the position to move is mate, not because of how the game arrived
/// there, so there is no loser here to be passed in or worked out separately.
///
/// The sentences are the app's own translated ones, and the side is named by the same localizations
/// — see [XiangqiSide.label] — so both read in the player's language.
String _resultLabel(BuildContext context, XiangqiGameState state) => switch (state.end) {
  .checkmate => context.l10n.mobileXiangqiCheckmated(state.turn.label(context.l10n)),
  // 困毙, and the whole of the difference from chess: a side with no legal move has lost the game,
  // where the same position in chess is a draw.
  .stalemate => context.l10n.mobileXiangqiStalemateLoss(state.turn.label(context.l10n)),
  .threefoldRepetition => context.l10n.mobileXiangqiThreefoldRepetition,
  .resign => context.l10n.mobileXiangqiResigned(state.resignedBy!.label(context.l10n)),
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
      content: Text(_resultLabel(context, state)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.close)),
        TextButton(onPressed: onNewGame, child: Text(context.l10n.mobileNewGame)),
      ],
    );
  }
}

/// The board's appearance and the game's own settings, in the one sheet.
///
/// The appearance switches are the app's own — the same ones the board settings screen offers, wired
/// to the same preferences, so that turning the coordinates off here and there are the same act. The
/// tile that is *not* offered is the board's coordinates' explanatory line: the app has one string
/// for it, "Board coordinates (A-H, 1-8)", which is eight files by eight ranks and wrong about this
/// board twice over, so the tile is left without a subtitle rather than given a lie.
///
/// The three things that are this game's own are the opponent — which here is only ever Pikafish at
/// one of three difficulties — the way the board is turned, and the way to start another game.
class const _XiangqiGameSettingsSheet({required final VoidCallback onNewGame})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_XiangqiGameSettingsSheet> createState() => _XiangqiGameSettingsSheetState();
}

class _XiangqiGameSettingsSheetState() extends ConsumerState<_XiangqiGameSettingsSheet> {
  // The sliders are the one setting that is not written on every pixel of the drag: the value is
  // kept here and handed over when the finger comes off, so that a preference is not written to the
  // disk sixty times over one gesture. Read once, like the settings screen does.
  late double _brightness = ref.read(boardPreferencesProvider).brightness;
  late double _hue = ref.read(boardPreferencesProvider).hue;

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final gameState = ref.watch(xiangqiGameControllerProvider);
    final isBoardFlipped = ref.watch(_isBoardFlippedProvider);
    final notifier = ref.read(boardPreferencesProvider.notifier);
    // The sheet's own switch, reading the same preference the board below it is built from.
    final blindfoldMode = ref.watch(
      offlineComputerGamePreferencesProvider.select((p) => p.blindfoldMode),
    );

    return BottomSheetScrollableContainer(
      children: [
        ListSection(
          materialFilledCard: true,
          children: [
            SettingsListTile(
              icon: const Icon(Icons.smart_toy),
              settingsLabel: Text(context.l10n.opponent),
              settingsValue: _difficultyLabel(context, gameState.difficulty),
              // Three labels and no numbers: what the levels really are is a search limit — see
              // [XiangqiDifficulty] — and a player choosing between them is choosing how long the
              // computer may think, not what it thinks with.
              explanation: context.l10n.mobileXiangqiDifficultyExplanation,
              onTap: () {
                showChoicePicker<XiangqiDifficulty>(
                  context,
                  title: Text(context.l10n.opponent),
                  choices: XiangqiDifficulty.values,
                  selectedItem: gameState.difficulty,
                  labelBuilder: (difficulty) => Text(_difficultyLabel(context, difficulty)),
                  // A difficulty is not a setting that can be changed under a game in progress:
                  // what the level is, is how long the engine may think about the moves it is
                  // being asked for now, so choosing one starts the game over at it. The side is
                  // carried over, because choosing how hard to play is not choosing a side.
                  onSelectedItemChanged: (difficulty) {
                    ref
                        .read(xiangqiGameControllerProvider.notifier)
                        .startNewGame(side: gameState.playerSide, difficulty: difficulty);
                  },
                );
              },
            ),
            SwitchSettingTile(
              title: Text(context.l10n.flipBoard),
              value: isBoardFlipped,
              onChanged: (_) => ref.read(_isBoardFlippedProvider.notifier).toggle(),
            ),
          ],
        ),
        ListSection(
          header: Text(context.l10n.settingsSettings),
          materialFilledCard: true,
          // The border tile and the two sliders carry icons and the switches do not, so the
          // section's dividers are indented as for tiles with a leading widget — the same shape the
          // theme settings screen's appearance section has. See `theme_settings_screen.dart`.
          hasLeading: true,
          children: [
            SwitchSettingTile(
              title: Text(context.l10n.preferencesPieceAnimation),
              value: boardPrefs.pieceAnimation,
              onChanged: (value) {
                notifier.togglePieceAnimation();
              },
            ),
            SwitchSettingTile(
              title: Text(context.l10n.preferencesPieceDestinations),
              value: boardPrefs.showLegalMoves,
              onChanged: (value) {
                notifier.toggleShowLegalMoves();
              },
            ),
            SwitchSettingTile(
              title: Text(context.l10n.preferencesBoardHighlights),
              value: boardPrefs.boardHighlights,
              onChanged: (value) {
                notifier.toggleBoardHighlights();
              },
            ),
            // The board's own count, nine files by ten ranks, and not the chess board's: the
            // shared setting is named for an eight by eight grid, which is the one thing about it
            // that is not the same on both boards. Like the difficulty labels, the range is the
            // part a reader would be misled by, so it is the part that is the game's own.
            SwitchSettingTile(
              title: Text(context.l10n.mobileXiangqiBoardCoordinates),
              value: boardPrefs.coordinates,
              onChanged: (value) {
                notifier.toggleCoordinates();
              },
            ),
            SwitchSettingTile(
              title: Text(context.l10n.mobilePrefMagnifyDraggedPiece),
              value: boardPrefs.magnifyDraggedPiece,
              onChanged: (value) {
                notifier.toggleMagnifyDraggedPiece();
              },
            ),
            SettingsListTile(
              settingsLabel: Text(context.l10n.mobileSettingsDraggedPieceTarget),
              settingsValue: dragTargetKindLabel(context.l10n, boardPrefs.dragTargetKind),
              onTap: () {
                showChoicePicker<DragTargetKind>(
                  context,
                  title: Text(context.l10n.mobileSettingsDraggedPieceTarget),
                  choices: DragTargetKind.values,
                  selectedItem: boardPrefs.dragTargetKind,
                  labelBuilder: (kind) => Text(dragTargetKindLabel(context.l10n, kind)),
                  onSelectedItemChanged: (DragTargetKind? value) {
                    notifier.setDragTargetKind(value ?? DragTargetKind.circle);
                  },
                );
              },
            ),
            SwitchSettingTile(
              leading: const Icon(Icons.border_outer),
              title: Text(context.l10n.mobileSettingsShowBorder),
              value: boardPrefs.showBorder,
              onChanged: (value) {
                notifier.toggleBorder();
              },
            ),
            if (!isShortVerticalScreen(context))
              SwitchSettingTile(
                title: Text(context.l10n.preferencesMoveListWhilePlaying),
                value: boardPrefs.moveListDisplay,
                onChanged: (value) {
                  notifier.toggleMoveListDisplay();
                },
              ),
            if (Theme.of(context).platform == TargetPlatform.android)
              SwitchSettingTile(
                title: Text(context.l10n.mobileSettingsImmersiveMode),
                subtitle: Text(context.l10n.mobileSettingsImmersiveModeSubtitle, maxLines: 5),
                value: boardPrefs.immersiveModeWhilePlaying ?? false,
                onChanged: (value) {
                  notifier.toggleImmersiveModeWhilePlaying();
                },
              ),
            if (isTabletOrLarger(context))
              SettingsListTile(
                settingsLabel: Text(context.l10n.mobileBoardPositionLandscape),
                settingsValue: boardPrefs.landscapeBoardPosition.label(context.l10n),
                onTap: () {
                  showChoicePicker<LandscapeBoardPosition>(
                    context,
                    title: Text(context.l10n.mobileBoardPositionLandscape),
                    choices: LandscapeBoardPosition.values,
                    selectedItem: boardPrefs.landscapeBoardPosition,
                    labelBuilder: (position) => Text(position.label(context.l10n)),
                    onSelectedItemChanged: (LandscapeBoardPosition? position) => ref
                        .read(boardPreferencesProvider.notifier)
                        .setLandscapeBoardPosition(position ?? LandscapeBoardPosition.left),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.brightness_6),
              title: Slider.adaptive(
                min: 0.2,
                max: 1.4,
                value: _brightness,
                onChanged: (value) {
                  setState(() {
                    _brightness = value;
                  });
                },
                onChangeEnd: (value) {
                  notifier.adjustColors(brightness: _brightness);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.invert_colors),
              title: Slider.adaptive(
                min: 0.0,
                max: 360.0,
                value: _hue,
                onChanged: (value) {
                  setState(() {
                    _hue = value;
                  });
                },
                onChangeEnd: (value) {
                  notifier.adjustColors(hue: _hue);
                },
              ),
            ),
          ],
        ),
        ListSection(
          header: Text(context.l10n.preferencesGameBehavior),
          materialFilledCard: true,
          children: [
            SwitchSettingTile(
              title: Text(context.l10n.mobileSettingsTouchFeedback),
              subtitle: Text(context.l10n.mobileSettingsTouchFeedbackSubtitle, maxLines: 5),
              value: boardPrefs.hapticFeedback,
              onChanged: (value) {
                notifier.toggleHapticFeedback();
              },
            ),
            SwitchSettingTile(
              title: Text(context.l10n.preferencesBlindfold),
              value: blindfoldMode,
              onChanged: (value) {
                ref.read(offlineComputerGamePreferencesProvider.notifier).toggleBlindfoldMode();
              },
            ),
          ],
        ),
        Padding(
          padding: Styles.horizontalBodyPadding,
          child: FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onNewGame();
            },
            child: Text(context.l10n.mobileNewGame, style: Styles.bold),
          ),
        ),
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
              settingsValue: _side.label(context.l10n),
              // 让先 is not a setting of its own, because it is not a separate thing: red moves
              // first, so a player who takes black has handed the opening move to the computer. The
              // line is there to say so at the moment the choice is made.
              explanation: _side == .black ? context.l10n.mobileXiangqiRedMovesFirst : null,
              onTap: () {
                showChoicePicker<XiangqiSide>(
                  context,
                  title: Text(context.l10n.side),
                  choices: XiangqiSide.values,
                  selectedItem: _side,
                  labelBuilder: (side) => Text(side.label(context.l10n)),
                  onSelectedItemChanged: (side) => setState(() => _side = side),
                );
              },
            ),
            SettingsListTile(
              // The computer is the whole of the opponent here, so the word for the row is the one
              // the chess screens use for theirs. See `_OfflineComputerGameScreen`.
              settingsLabel: Text(context.l10n.opponent),
              settingsValue: _difficultyLabel(context, _difficulty),
              explanation: context.l10n.mobileXiangqiDifficultyExplanation,
              onTap: () {
                showChoicePicker<XiangqiDifficulty>(
                  context,
                  title: Text(context.l10n.opponent),
                  choices: XiangqiDifficulty.values,
                  selectedItem: _difficulty,
                  labelBuilder: (difficulty) => Text(_difficultyLabel(context, difficulty)),
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
