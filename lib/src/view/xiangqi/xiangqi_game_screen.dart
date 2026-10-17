import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart' show MoveVerdict;
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
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
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_difficulty_tile.dart';
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
class const XiangqiGameScreen({
  /// The position to set a game up on, or null to open the sheet on the standard one.
  ///
  /// A FEN rather than a [XiangqiPosition], because this is the screen's edge and what a board
  /// editor or a deep link has to hand: it is parsed once, in the sheet, and the model below takes
  /// the position. Assumed well formed — its only source is [XiangqiPosition.toFen] — so a bad one
  /// throws rather than being quietly replaced by the opening.
  final String? initialFen,

  /// A setup chosen on another screen, used when the computer game picker starts this screen.
  final XiangqiSide? initialSide,
  final XiangqiDifficulty? initialDifficulty,
  final TimeIncrement? initialTimeIncrement,
  final bool initialPracticeMode = false,
}) extends ConsumerWidget {
  static Route<void> buildRoute({
    String? initialFen,
    XiangqiSide? initialSide,
    XiangqiDifficulty? initialDifficulty,
    TimeIncrement? initialTimeIncrement,
    bool initialPracticeMode = false,
  }) => buildScreenRoute(
    screen: XiangqiGameScreen(
      initialFen: initialFen,
      initialSide: initialSide,
      initialDifficulty: initialDifficulty,
      initialTimeIncrement: initialTimeIncrement,
      initialPracticeMode: initialPracticeMode,
    ),
  );

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
      body: _Body(
        initialFen: initialFen,
        initialSide: initialSide,
        initialDifficulty: initialDifficulty,
        initialTimeIncrement: initialTimeIncrement,
        initialPracticeMode: initialPracticeMode,
      ),
    );
  }
}

/// Asks which side to take and how hard the computer should play, then starts over.
///
/// The sheet opens on the game in progress rather than on a default, so that opening it to look
/// does not quietly mean something else by the time it is dismissed.
///
/// [initialFen] is the position the game is to start from, and is only ever given when the screen
/// was opened with one: the sheet then becomes the way that position is turned into a game. Every
/// later visit — the settings sheet, the result dialog, the bar's own button — leaves it out, and
/// starts over from the standard opening.
void _showNewGameSheet(BuildContext context, WidgetRef ref, {String? initialFen}) {
  final gameState = ref.read(xiangqiGameControllerProvider);
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => _NewGameSheet(
      side: gameState.playerSide,
      difficulty: gameState.difficulty,
      initialFen: initialFen,
    ),
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

class const _Body({
  final String? initialFen,
  required final XiangqiSide? initialSide,
  required final XiangqiDifficulty? initialDifficulty,
  required final TimeIncrement? initialTimeIncrement,
  required final bool initialPracticeMode,
}) extends ConsumerStatefulWidget {
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
    // A position handed to the screen is a game to be set up on it, not a game to be resumed: the
    // sheet comes up by itself so the player picks a side and a level against the given board, and
    // nothing is evaluated until that game exists. See the chess screen's own `_BodyState.initState`,
    // which treats an initial FEN the same way.
    //
    // Without one, the screen opens on a game already in progress and the evaluation is asked for
    // rather than waited for: `ref.listen` never fires for the value that is already there, and that
    // game is exactly that value.
    final setupSide = widget.initialSide;
    final setupDifficulty = widget.initialDifficulty;
    if (setupSide != null && setupDifficulty != null) {
      final timeIncrement = widget.initialTimeIncrement ?? XiangqiClock.defaultTimeIncrement;
      ref
          .read(xiangqiGameControllerProvider.notifier)
          .startNewGame(
            side: setupSide,
            difficulty: setupDifficulty,
            timeIncrement: timeIncrement,
            practiceMode: widget.initialPracticeMode,
          );
      ref.read(xiangqiClockProvider.notifier).setupClock(timeIncrement);
      unawaited(ref.read(xiangqiGameStorageProvider).delete());
      if (!timeIncrement.isInfinite) {
        ref.read(xiangqiClockProvider.notifier).resume(setupSide);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncEvaluation(ref.read(xiangqiGameControllerProvider));
      });
      return;
    }

    final initialFen = widget.initialFen;
    if (initialFen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNewGameSheet(context, ref, initialFen: initialFen);
      });
      return;
    }
    unawaited(_restoreOrStart());
  }

  Future<void> _restoreOrStart() async {
    final saved = await ref.read(xiangqiGameStorageProvider).fetchGame();
    if (!mounted) return;
    if (saved != null && saved.state.moves.isNotEmpty && !saved.state.isFinished) {
      ref
          .read(xiangqiGameControllerProvider.notifier)
          .restoreGame(
            game: saved.state,
            timeIncrement: saved.timeIncrement,
            redTimeLeft: saved.redTimeLeft,
            blackTimeLeft: saved.blackTimeLeft,
          );
      _syncEvaluation(ref.read(xiangqiGameControllerProvider));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showNewGameSheet(context, ref);
    });
  }

  Future<void> _saveGame(XiangqiGameState gameState) async {
    if (gameState.moves.isEmpty) return;
    final clock = ref.read(xiangqiClockProvider);
    await ref
        .read(xiangqiGameStorageProvider)
        .save(
          SavedXiangqiGame(
            state: gameState.copyWith(isEngineThinking: false, selected: null),
            timeIncrement: gameState.timeIncrement,
            redTimeLeft: clock.redTimeLeft,
            blackTimeLeft: clock.blackTimeLeft,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(xiangqiGameControllerProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final analysisState = ref.watch(xiangqiEngineAnalysisProvider);
    final evalEnabled = ref.watch(engineEvaluationPreferencesProvider.select((p) => p.isEnabled));
    final isBoardFlipped = ref.watch(_isBoardFlippedProvider);
    final clock = ref.watch(xiangqiClockProvider);
    final clockTenths =
        ref.watch(clockTenthsProvider).value ?? defaultAccountPreferences.clockTenths;

    ref.listen(xiangqiClockProvider.select((c) => c.flagSide), (previous, flagged) {
      if (previous == null && flagged != null) {
        ref.read(xiangqiGameControllerProvider.notifier).onFlag(flagged);
      }
    });

    ref.listen(xiangqiGameControllerProvider, (previous, newState) {
      if (previous != null) {
        final played = newState.moves.length - previous.moves.length;
        if (played > 0) {
          ref.read(xiangqiClockProvider.notifier).onMove(newSideToMove: newState.turn);
        } else if (played < 0 && ref.read(xiangqiClockProvider).active) {
          ref
              .read(xiangqiClockProvider.notifier)
              .switchSide(newSideToMove: newState.turn, addIncrement: false);
        }
      }
      // A game that has just ended says so, half a second late so that the move that ended it is on
      // the board and read before the dialog comes down over it.
      if (previous?.end == null && newState.end != null) {
        ref.read(xiangqiClockProvider.notifier).pause();
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
      if (!newState.practiceMode) _syncEvaluation(newState);
      unawaited(_saveGame(newState));
    });

    final controller = ref.read(xiangqiGameControllerProvider.notifier);
    final orientation = isBoardFlipped ? gameState.playerSide.opposite : gameState.playerSide;
    final authUser = ref.watch(authControllerProvider);
    final playerName = authUser?.user.name ?? orientation.label(context.l10n);
    final hintMove = _hintPosition == gameState.position ? analysisState.hint?.move : null;
    final arrows = IList<XiangqiBoardArrow>([
      if (hintMove != null) XiangqiBoardArrow(move: hintMove),
      if (!gameState.isEvaluatingMove && gameState.practiceComment?.bestMove != null)
        XiangqiBoardArrow(
          move: gameState.practiceComment!.bestMove!,
          color: Colors.orange,
          opacity: 0.65,
        ),
    ]);
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
        unawaited(_saveGame(ref.read(xiangqiGameControllerProvider)));
        ref.read(xiangqiClockProvider.notifier).pause();
        _evaluatedPosition = null;
        if (ref.read(xiangqiEngineAnalysisProvider).isBusy) {
          ref.read(xiangqiEngineAnalysisProvider.notifier).stopEvaluation();
        }
      },
      onFocusRegained: () {
        if (!context.mounted) return;
        final state = ref.read(xiangqiGameControllerProvider);
        if (!state.isFinished && !state.timeIncrement.isInfinite) {
          ref.read(xiangqiClockProvider.notifier).resume(state.turn);
        }
        _syncEvaluation(state);
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
                    arrows: arrows,
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
                  side: orientation.opposite,
                  clock: gameState.timeIncrement.isInfinite
                      ? null
                      : Clock(
                          timeLeft: clock.timeLeft(orientation.opposite) ?? Duration.zero,
                          active: clock.activeClock == orientation.opposite,
                          emergencyThreshold: const Duration(seconds: 20),
                          clockTenths: clockTenths,
                        ),
                  style: XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors),
                  // The engine's own name, which is a proper name and the same in every language:
                  // it is the program that is playing, not a description of it. How hard it is
                  // playing is a setting, and the sheet is where a setting is read.
                  name: 'Pikafish',
                  isBot: true,
                  thinking: gameState.isEngineThinking,
                  status: '',
                ),
                bottomTable: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PlayerRow(
                      side: orientation,
                      clock: gameState.timeIncrement.isInfinite
                          ? null
                          : Clock(
                              timeLeft: clock.timeLeft(orientation) ?? Duration.zero,
                              active: clock.activeClock == orientation,
                              emergencyThreshold: const Duration(seconds: 20),
                              clockTenths: clockTenths,
                            ),
                      style: XiangqiBoardStyle.fromChessboardColorScheme(
                        boardPrefs.boardTheme.colors,
                      ),
                      name: playerName,
                      thinking: false,
                      status: _statusText(context, gameState),
                    ),
                    if (gameState.practiceMode) _PracticeFeedback(state: gameState),
                  ],
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

/// The size a player's name is printed at: the chess screens' own `playerFontSize`, so that the
/// two games' player rows read at the same size.
const double _kPlayerNameFontSize = 15.0;

/// One of the two rows beside the board: the computer above it, and the player below.
///
/// Neither row has a clock or a material count to show — a xiangqi game here is played untimed, and
/// the pieces that have been taken are on the board rather than in a tally. What is left is the name
/// of whoever is to move and what the game is doing, which is what the line under the board used to
/// say on its own.
class const _PlayerRow({
  /// The side the row's seat plays, which is the side its avatar's general is.
  required final XiangqiSide side,

  /// The board's own colours, so the avatar is the same piece the board is playing with.
  required final XiangqiBoardStyle style,

  /// The name to print, or null for a row that has none of its own.
  final String? name,

  /// Whether this player is an engine / bot.
  final bool isBot = false,

  /// Whether to show the hourglass that says the computer has the move and is thinking about it.
  final bool thinking = false,

  /// The line under the name: what the game is doing, in one sentence or none.
  final String status = '',

  /// An optional clock at the end of the row.
  final Widget? clock,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = this.name;

    return Row(
      children: [
        XiangqiPieceAvatar(side: side, size: 36, style: style),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (name != null)
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: _kPlayerNameFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (isBot) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.lichessColors.fancy,
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                      ),
                      child: Text(
                        context.l10n.computer,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
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
        if (clock != null) ...[const SizedBox(width: 8.0), clock!],
      ],
    );
  }
}

class const _PracticeFeedback({required final XiangqiGameState state}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (state.isEvaluatingMove) {
      return Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 14.0,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(width: 8.0),
            Text(context.l10n.mobileXiangqiEvaluatingMove),
          ],
        ),
      );
    }
    final comment = state.practiceComment;
    if (comment == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _verdictLabel(context, comment.verdict),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (comment.bestMove != null) ...[
            const SizedBox(width: 8.0),
            Text(context.l10n.mobileXiangqiReviewBestMoveWas(comment.bestMove!.iccs)),
          ],
        ],
      ),
    );
  }

  String _verdictLabel(BuildContext context, MoveVerdict verdict) => switch (verdict) {
    .goodMove || .notBest => context.l10n.mobileXiangqiReviewGood,
    .inaccuracy => context.l10n.mobileXiangqiReviewInaccuracy,
    .mistake => context.l10n.mobileXiangqiReviewMistake,
    .blunder => context.l10n.mobileXiangqiReviewBlunder,
  };
}

/// What the player's own row says.
///
/// The most important thing that is true, and only one of them: how the game ended if it has, and
/// otherwise what is going on in it. Nothing is said while the computer has the move but has not
/// started thinking — that is a moment rather than a state, and the board is about to move.
String _statusText(BuildContext context, XiangqiGameState state) {
  if (state.end != null) return xiangqiResultLabel(context, state);
  if (state.isEngineThinking) return context.l10n.computerThinking;
  if (state.isPlayerTurn) return context.l10n.yourTurn;
  return '';
}

/// How the game ended, in a sentence — the one thing the dialog's title cannot say.
///
/// The side that is mated or stuck is the side to move, because that is the only question the rules
/// ask: a game is mate because the position to move is mate, not because of how the game arrived
/// there, so there is no loser here to be passed in or worked out separately. A resignation and a
/// flag are the other way round — they are events rather than positions — so the side that gave up
/// and the side that ran out of time are both carried on the state.
///
/// The sentences are the app's own translated ones, and the side is named by the same localizations
/// — see [XiangqiSide.label] — so both read in the player's language.
///
/// Public because the over-the-board screen shows the same sentences for the same reasons, and a
/// second copy of this switch would be a second thing to keep in step with [XiangqiGameEnd].
String xiangqiResultLabel(BuildContext context, XiangqiGameState state) => switch (state.end) {
  .checkmate => context.l10n.mobileXiangqiCheckmated(state.turn.label(context.l10n)),
  // 困毙, and the whole of the difference from chess: a side with no legal move has lost the game,
  // where the same position in chess is a draw.
  .stalemate => context.l10n.mobileXiangqiStalemateLoss(state.turn.label(context.l10n)),
  .threefoldRepetition => context.l10n.mobileXiangqiThreefoldRepetition,
  .resign => context.l10n.mobileXiangqiResigned(state.resignedBy!.label(context.l10n)),
  // Losing on time is losing, exactly as a resignation is, and the side named is the side that
  // flagged — the one recorded on the state, not the side to move. A move and a flag can land in
  // the same frame, and by the time this is read the turn may already have changed hands.
  .timeout => context.l10n.mobileXiangqiRanOutOfTime(state.flaggedSide!.label(context.l10n)),
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
      content: Text(xiangqiResultLabel(context, state)),
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
/// one of its levels — the way the board is turned, and the way to start another game.
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
            // A difficulty is not a setting that can be changed under a game in progress: what the
            // level is, is how long the engine may think about the moves it is being asked for now,
            // so choosing one starts the game over at it. The side is carried over, because choosing
            // how hard to play is not choosing a side.
            XiangqiDifficultyTile(
              difficulty: gameState.difficulty,
              onChanged: (difficulty) {
                ref
                    .read(xiangqiGameControllerProvider.notifier)
                    .startNewGame(side: gameState.playerSide, difficulty: difficulty);
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
///
/// [initialFen] is a position to set up on, and is only ever given when the screen was opened with
/// one; the sheet then opens on [XiangqiPosition.turn] as the player's own side and draws the
/// position above the controls, so that what is being set up is read rather than imagined.
class const _NewGameSheet({
  required final XiangqiSide side,
  required final XiangqiDifficulty difficulty,
  final String? initialFen,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState() extends ConsumerState<_NewGameSheet> {
  /// The position the game is to start from, or null for the standard opening.
  ///
  /// Parsed once here rather than in [build], and likewise for the side below: the FEN is assumed
  /// well formed, so a good one parses the same way every frame.
  late final XiangqiPosition? _initialPosition = widget.initialFen == null
      ? null
      : XiangqiPosition.fromFen(widget.initialFen!);

  /// The side the player takes, which opens on the side to move in a given position — the player
  /// meant to move first — and otherwise on the side the game in progress has. See the chess sheet's
  /// `SideChoice.nextToPlay`, which this is the same question as.
  late XiangqiSide _side = _initialPosition?.turn ?? widget.side;
  late XiangqiDifficulty _difficulty = widget.difficulty;
  TimeIncrement _timeIncrement = const TimeIncrement.infinite();
  bool _practiceMode = false;

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
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
              settingsLabel: Text(context.l10n.timeControl),
              settingsValue: _timeIncrement.isInfinite
                  ? context.l10n.unlimited
                  : '${_timeIncrement.time ~/ 60}+${_timeIncrement.increment}',
              onTap: () {
                showChoicePicker<TimeIncrement>(
                  context,
                  title: Text(context.l10n.timeControl),
                  choices: const [
                    TimeIncrement.infinite(),
                    TimeIncrement(180, 2),
                    TimeIncrement(300, 3),
                    TimeIncrement(600, 0),
                    TimeIncrement(900, 10),
                  ],
                  selectedItem: _timeIncrement,
                  labelBuilder: (value) => Text(
                    value.isInfinite
                        ? context.l10n.unlimited
                        : '${value.time ~/ 60}+${value.increment}',
                  ),
                  onSelectedItemChanged: (value) => setState(() => _timeIncrement = value),
                );
              },
            ),
            // The position being set up, drawn below the side it is drawn for. Read only and with no
            // callbacks, so a touch on it does nothing. Its box follows the same coordinate margin
            // the live board does, rather than leaving the preview letterboxed.
            if (_initialPosition != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: SizedBox(
                    width: 135.0,
                    height: 135.0 * (boardPrefs.coordinates ? 11 / 10 : 10 / 9),
                    child: XiangqiBoard(
                      position: _initialPosition,
                      showCoordinates: boardPrefs.coordinates,
                      showBorder: boardPrefs.showBorder,
                      style: XiangqiBoardStyle.fromChessboardColorScheme(
                        boardPrefs.boardTheme.colors,
                      ),
                    ),
                  ),
                ),
              ),
            // The computer is the whole of the opponent here, so the control for it is the app's own
            // level control for one. See [_XiangqiLevelTile].
            XiangqiDifficultyTile(
              difficulty: _difficulty,
              onChanged: (difficulty) => setState(() => _difficulty = difficulty),
            ),
            SwitchSettingTile(
              title: Text(context.l10n.mobilePracticeMode),
              subtitle: Text(context.l10n.mobileGetFeedbackOnMoves),
              value: _practiceMode,
              onChanged: (value) => setState(() => _practiceMode = value),
            ),
          ],
        ),
        Padding(
          padding: Styles.horizontalBodyPadding,
          child: FilledButton(
            onPressed: () {
              final effectiveIncrement = _practiceMode
                  ? const TimeIncrement.infinite()
                  : _timeIncrement;
              ref
                  .read(xiangqiGameControllerProvider.notifier)
                  .startNewGame(
                    side: _side,
                    difficulty: _difficulty,
                    initialPosition: _initialPosition,
                    timeIncrement: effectiveIncrement,
                    practiceMode: _practiceMode,
                  );
              ref.read(offlineComputerGamePreferencesProvider.notifier).setLastGameWasXiangqi(true);
              if (!effectiveIncrement.isInfinite) {
                ref.read(xiangqiClockProvider.notifier).resume(_initialPosition?.turn ?? _side);
              }
              unawaited(ref.read(xiangqiGameStorageProvider).delete());
              Navigator.pop(context);
            },
            child: Text(context.l10n.play, style: Styles.bold),
          ),
        ),
      ],
    );
  }
}
