import 'dart:async';
import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/common/local_game_clock.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/lobby/game_setup_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_otb_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/service/move_feedback.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/non_linear_slider.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:material_ui/material_ui.dart';

/// A game of xiangqi played by two people at one device, over the board.
///
/// The same game the rest of the app plays, with the one thing the over-the-board arrangement has
/// that a game against the computer does not: a seat on both sides of the board, and a clock. Both
/// sides are a person's — see [XiangqiOpponent.human] — so nothing is ever searched for and the app
/// is a board and a clock rather than an opponent.
///
/// The screen is arranged exactly as the chess one is: the app's own [XiangqiBoard] and
/// [XiangqiGameLayout], a row for each player beside it with that player's clock, a move list in the
/// notation the game is read in, and the two settings the board is drawn to. The one thing the chess
/// screen has that this does not is a game to come back to: nothing is written down, so leaving the
/// screen leaves the game behind. That is the whole of this wave — persisted over-the-board games are
/// their own piece of work — and the setup sheet that opens on arrival is what a player gets instead.
///
/// What it does not have is the bar of engine buttons beside the board: no evaluation, no hint, no
/// opponent to think about. Neither side is the app's to move, so there is nothing for an engine to
/// say about the game that the two players cannot see for themselves.
class const XiangqiOverTheBoardScreen({
  /// The position to set a game up on, or null to open the sheet on the standard one.
  ///
  /// A FEN rather than a [XiangqiPosition], because this is the screen's edge and what a board
  /// editor or a deep link has to hand: it is parsed once, in the sheet, and the model below takes
  /// the position. Assumed well formed — its only source is [XiangqiPosition.toFen] — so a bad one
  /// throws rather than being quietly replaced by the opening.
  final String? initialFen,
}) extends StatelessWidget {
  static Route<void> buildRoute({String? initialFen}) =>
      buildScreenRoute(screen: XiangqiOverTheBoardScreen(initialFen: initialFen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The same title the chess screen of the same name carries, which is what makes the two equal:
      // they are one way of playing, offered for two games, and neither is a variant of the other.
      appBar: AppBar(title: Text(context.l10n.mobileOverTheBoard)),
      body: _Body(initialFen: initialFen),
    );
  }
}

class const _Body({final String? initialFen}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState() extends ConsumerState<_Body> {
  /// The side drawn at the bottom of the board.
  ///
  /// Red until the board is turned round. This is a way of looking at the game and not a fact about
  /// it — there is no player's side here to disagree with — so it is kept on the screen and nowhere
  /// else, and the game is not restarted by turning the board around.
  XiangqiSide _orientation = XiangqiSide.red;

  @override
  void initState() {
    super.initState();
    // The clock is asked for before the sheet is shown, so that the two things the sheet will do to
    // it — setting the time control, and starting the game — are done to the clock this screen is
    // already watching rather than to one that is created and thrown away.
    ref.read(xiangqiClockProvider);
    // The sheet opens on arrival either way; a position handed to the screen is what the game it
    // starts from becomes, and is the only thing it carries.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.initialFen != null) {
        _showConfigureSheet(context, initialFen: widget.initialFen);
        return;
      }
      final saved = await ref.read(xiangqiOtbGameStorageProvider).fetchGame();
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
        return;
      }
      _showConfigureSheet(context);
    });
  }

  Future<void> _saveGame() async {
    final state = ref.read(xiangqiGameControllerProvider);
    if (state.moves.isEmpty) return;
    final clock = ref.read(xiangqiClockProvider);
    await ref
        .read(xiangqiOtbGameStorageProvider)
        .save(
          SavedXiangqiGame(
            state: state.copyWith(isEngineThinking: false, selected: null),
            timeIncrement: state.timeIncrement,
            redTimeLeft: clock.redTimeLeft,
            blackTimeLeft: clock.blackTimeLeft,
          ),
        );
  }

  /// Shows the result half a second after the game ends.
  ///
  /// The delay is the chess screens' own, and for the same reason: the move that ended the game, or
  /// the flag that did, should be on the board and read before a dialog comes down over it.
  void _showResultDialog(XiangqiGameState gameState) {
    Timer(const Duration(milliseconds: 500), () {
      if (!context.mounted) return;
      showAdaptiveDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => _XiangqiOtbResultDialog(
          state: gameState,
          onNewGame: () {
            Navigator.pop(dialogContext);
            _showConfigureSheet(context);
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(xiangqiGameControllerProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);

    // The clock follows the game rather than the game following the clock, and the two are put
    // together here rather than in the controller: what a move means to a clock is a fact about this
    // screen — only this screen has one — and the controller is the same controller the untimed
    // computer game uses.
    //
    // A move and a takeback are told apart by the count and not by the turn, because a turn that
    // changes with no move behind it is exactly what a takeback is: the clock then goes back to the
    // side that has the move again, and without an increment, since no move was made to earn one.
    ref.listen(xiangqiGameControllerProvider, (previous, newState) {
      if (previous == null) return;
      final played = newState.moves.length - previous.moves.length;
      if (played > 0) {
        ref.read(xiangqiClockProvider.notifier).onMove(newSideToMove: newState.turn);
        unawaited(_saveGame());
        if (played == 1) {
          final move = newState.moves.last;
          final isCapture = previous.position.pieceAt(move.to) != null;
          final service = ref.read(moveFeedbackServiceProvider);
          if (isCapture) {
            service.captureFeedback(null, check: newState.isInCheck);
          } else {
            service.moveFeedback(check: newState.isInCheck);
          }
        }
      } else if (played < 0 && ref.read(xiangqiClockProvider).active) {
        ref
            .read(xiangqiClockProvider.notifier)
            .switchSide(newSideToMove: newState.turn, addIncrement: false);
      }
      if (previous.end == null && newState.end != null) {
        ref.read(xiangqiClockProvider.notifier).pause();
        _showResultDialog(newState);
      }
    });

    // A clock that has run out ends the game, and the clock is where the side comes from: what it
    // knows is whose time it was when it stopped being, which is the one thing about the flag the
    // position cannot be asked for afterwards. Only the transition is acted on — a clock that has
    // flagged stays flagged, and every later tick would otherwise end the same game again.
    ref.listen(xiangqiClockProvider.select((c) => c.flagSide), (previous, flagSide) {
      if (previous == null && flagSide != null) {
        ref.read(xiangqiGameControllerProvider.notifier).onFlag(flagSide);
      }
    });

    // The board is drawn from the side at the bottom of it, and each row is that end's player, so
    // that turning the board around turns the two of them with it: the row above the board is always
    // the side drawn at the top.
    final topSide = _orientation.opposite;

    return WakelockWidget(
      child: FocusDetector(
        // Time does not run while the app is away: the clock is this screen's, and the screen is not
        // playing the game while it is in the background. Nothing resumes it on the way back — the
        // pause button in the bar below, which is where pausing is done anyway, is also the way back.
        onForegroundLost: () {
          if (!context.mounted) return;
          unawaited(_saveGame());
          ref.read(xiangqiClockProvider.notifier).pause();
        },
        child: PopScope(
          onPopInvokedWithResult: (_, _) => unawaited(_saveGame()),
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
                        orientation: _orientation,
                        selected: gameState.selected,
                        // The legal moves and the last move are things the board draws, so the two
                        // settings that turn them off turn them off here as well as on the computer
                        // screen: they are the same board.
                        moves: boardPrefs.showLegalMoves
                            ? gameState.selectedMoves
                            : const IListConst([]),
                        lastMove: boardPrefs.boardHighlights ? gameState.lastMove : null,
                        onTapSquare: ref.read(xiangqiGameControllerProvider.notifier).tapSquare,
                        // A drag is the same two taps in the order they were made, as it is on the
                        // computer screen: the piece is picked up where it was let go of and put down
                        // where it was dropped.
                        onDragMove: (from, to) {
                          final controller = ref.read(xiangqiGameControllerProvider.notifier);
                          controller.tapSquare(from);
                          controller.tapSquare(to);
                        },
                        animationDuration: boardPrefs.pieceAnimationDuration,
                        showCoordinates: boardPrefs.coordinates,
                        showLastMove: boardPrefs.boardHighlights,
                        showBorder: boardPrefs.showBorder,
                        magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
                        dragTargetKind: boardPrefs.dragTargetKind,
                        style: XiangqiBoardStyle.fromChessboardColorScheme(
                          boardPrefs.boardTheme.colors,
                        ),
                      ),
                    ),
                    topTable: _OtbPlayer(side: topSide, clockKey: const ValueKey('topClock')),
                    bottomTable: _OtbPlayer(
                      side: _orientation,
                      clockKey: const ValueKey('bottomClock'),
                    ),
                    moves: xiangqiGameNotation(gameState.positions, gameState.moves),
                    currentMoveIndex: gameState.viewCursor,
                    onSelectMove: ref.read(xiangqiGameControllerProvider.notifier).goTo,
                    userActionsBar: _OtbBottomBar(
                      onFlipBoard: () {
                        setState(() {
                          _orientation = _orientation.opposite;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the two rows beside the board: the player drawn at the top of it, and the one below.
///
/// A row of this screen's own rather than the chess screens' `GamePlayer`, which is typed to a
/// dartchess `Game` from its constructor down and has no xiangqi to be given. What is left when the
/// material count, the link to a profile and the engine's hourglass are taken away is a name, a
/// clock, and which of the two is to move — and the name is this game's own, red or black rather
/// than white or black.
class const _OtbPlayer({required final XiangqiSide side, required final Key clockKey})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(xiangqiGameControllerProvider);
    final clock = ref.watch(xiangqiClockProvider);
    final clockTenths =
        ref.watch(clockTenthsProvider).value ?? defaultAccountPreferences.clockTenths;
    // A row is dimmed when it is not that side's move, which is the only place the turn is drawn:
    // neither side has anything else to be told — there is no "your turn" when both sides are at the
    // board.
    final isToMove = gameState.turn == side && !gameState.isFinished;
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final style = XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors);

    return XiangqiPlayerRow(
      side: side,
      style: style,
      name: side.label(context.l10n),
      isToMove: isToMove,
      avatarSize: 32,
      clock: clock.timeIncrement.isInfinite
          ? null
          : Clock(
              key: clockKey,
              timeLeft: Duration(milliseconds: max(0, clock.timeLeft(side)!.inMilliseconds)),
              active: clock.activeClock == side,
              emergencyThreshold: Duration(
                seconds: (clock.timeIncrement.time * 0.125).clamp(10, 60).toInt(),
              ),
              clockTenths: clockTenths,
            ),
    );
  }
}

/// What the bar under the board offers: the menu, the clock, and taking a move back.
///
/// There is no resign and no offer of a draw, which the chess bar has: both are one player telling
/// the other something, and the two of them are sitting at the same board already.
class const _OtbBottomBar({required final VoidCallback onFlipBoard}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(xiangqiGameControllerProvider);
    final clock = ref.watch(xiangqiClockProvider);

    return BottomBar(
      children: [
        BottomBarButton(
          label: context.l10n.menu,
          onTap: () => _showMenu(context, ref),
          icon: Icons.menu,
        ),
        if (!clock.timeIncrement.isInfinite)
          BottomBarButton(
            label: clock.active ? context.l10n.pause : context.l10n.resume,
            onTap: gameState.isFinished
                ? null
                : () {
                    if (clock.active) {
                      ref.read(xiangqiClockProvider.notifier).pause();
                    } else {
                      // Whoever has the move starts their time with the button: a clock can be
                      // paused before the first move as well as in the middle of a game.
                      ref.read(xiangqiClockProvider.notifier).resume(gameState.turn);
                    }
                  },
            icon: clock.active ? CupertinoIcons.pause : CupertinoIcons.play,
          ),
        BottomBarButton(
          label: context.l10n.mobilePreviousMove,
          onTap: gameState.viewCursor > 0
              ? ref.read(xiangqiGameControllerProvider.notifier).goBackward
              : null,
          icon: CupertinoIcons.chevron_back,
        ),
        BottomBarButton(
          label: context.l10n.next,
          onTap: gameState.viewCursor < gameState.positions.length - 1
              ? ref.read(xiangqiGameControllerProvider.notifier).goForward
              : null,
          icon: CupertinoIcons.chevron_forward,
        ),
        BottomBarButton(
          label: context.l10n.takeback,
          // The clock is not touched here: taking a move back changes the game, and the game is
          // what the clock follows — see the listener in [_BodyState.build].
          onTap: gameState.canUndo ? ref.read(xiangqiGameControllerProvider.notifier).undo : null,
          icon: Icons.undo,
        ),
      ],
    );
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) {
    return showAdaptiveActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.mobileNewGame),
          onPressed: () => _showConfigureSheet(context),
        ),
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.flipBoard),
          onPressed: onFlipBoard,
        ),
      ],
    );
  }
}

/// How a game between two people ended.
///
/// The sentence is the computer screen's own — see [xiangqiResultLabel] — and the title is the one
/// thing that cannot be: that dialog says "Victory" or "Game Over" depending on which side the
/// player had, and there is no player here to have one. What is left is a result and no winner of
/// the app's, which is what "Game Over" and "Draw" say.
class const _XiangqiOtbResultDialog({
  required final XiangqiGameState state,
  required final VoidCallback onNewGame,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(state.winner == null ? context.l10n.draw : context.l10n.gameOver),
      content: Text(xiangqiResultLabel(context, state)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.close)),
        TextButton(onPressed: onNewGame, child: Text(context.l10n.mobileNewGame)),
      ],
    );
  }
}

/// Asks how much time each side has, and starts the game.
///
/// The time control is the whole of the choice. There is no side to pick, because both sides are
/// played at this board, and no opponent to set up, because the app is not one. The picker is the
/// app's own [TimeControlType] and the app's own two sliders, with the chess over-the-board sheet's
/// strings, because it is the same question about the same kind of game; the sheet is not shared with
/// it because nothing else is: the chess one also carries a variant and a position, and writes the
/// choices down as a preference that outlives the game, neither of which this has.
///
/// [initialFen] is the position the game is to start from, and like the computer screen's own sheet
/// it is only ever given when the screen was opened with one: the timing is still the whole of what
/// the sheet asks, this is only what the game it starts is set up on.
void _showConfigureSheet(BuildContext context, {String? initialFen}) {
  showModalBottomSheet<void>(
    context: context,
    isDismissible: true,
    isScrollControlled: true,
    builder: (context) => _ConfigureXiangqiOtbSheet(initialFen: initialFen),
  );
}

class const _ConfigureXiangqiOtbSheet({final String? initialFen}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ConfigureXiangqiOtbSheet> createState() => _ConfigureXiangqiOtbSheetState();
}

class _ConfigureXiangqiOtbSheetState() extends ConsumerState<_ConfigureXiangqiOtbSheet> {
  TimeControlType _timeControlType = TimeControlType.clock;

  /// The timed control, kept while the untimed one is chosen so that leaving and coming back to the
  /// clock does not mean setting it up again. Nothing is written down: this is the sheet's own state
  /// and it dies with the sheet, which is the whole of the difference from the chess sheet, whose
  /// choices are a preference.
  TimeIncrement _timeIncrement = XiangqiClock.defaultTimeIncrement;

  bool get _hasClock => _timeControlType == TimeControlType.clock;

  TimeIncrement get _chosenIncrement => _hasClock ? _timeIncrement : const TimeIncrement.infinite();

  @override
  Widget build(BuildContext context) {
    return BottomSheetScrollableContainer(
      children: [
        ListSection(
          materialFilledCard: true,
          children: [
            SettingsListTile(
              settingsLabel: Text(context.l10n.timeControl),
              settingsValue: _timeControlType.label(context.l10n),
              onTap: () {
                showChoicePicker<TimeControlType>(
                  context,
                  title: Text(context.l10n.timeControl),
                  choices: TimeControlType.values,
                  selectedItem: _timeControlType,
                  labelBuilder: (control) => Text(control.label(context.l10n)),
                  onSelectedItemChanged: (control) => setState(() => _timeControlType = control),
                );
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _hasClock
                  ? Column(
                      children: [
                        ListTile(
                          title: Text.rich(
                            TextSpan(
                              text: '${context.l10n.minutesPerSide}: ',
                              children: [
                                TextSpan(
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                  text: clockLabelInMinutes(_timeIncrement.time),
                                ),
                              ],
                            ),
                          ),
                          subtitle: NonLinearSlider(
                            value: _timeIncrement.time,
                            values: kAvailableTimesInSeconds,
                            labelBuilder: clockLabelInMinutes,
                            onChange: (num value) => setState(
                              () => _timeIncrement = TimeIncrement(
                                value.toInt(),
                                _timeIncrement.increment,
                              ),
                            ),
                            onChangeEnd: (num value) => setState(
                              () => _timeIncrement = TimeIncrement(
                                value.toInt(),
                                _timeIncrement.increment,
                              ),
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text.rich(
                            TextSpan(
                              text: '${context.l10n.incrementInSeconds}: ',
                              children: [
                                TextSpan(
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                  text: '${_timeIncrement.increment}',
                                ),
                              ],
                            ),
                          ),
                          subtitle: NonLinearSlider(
                            value: _timeIncrement.increment,
                            values: kAvailableIncrementsInSeconds,
                            onChange: (num value) => setState(
                              () => _timeIncrement = TimeIncrement(
                                _timeIncrement.time,
                                value.toInt(),
                              ),
                            ),
                            onChangeEnd: (num value) => setState(
                              () => _timeIncrement = TimeIncrement(
                                _timeIncrement.time,
                                value.toInt(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        Padding(
          padding: Styles.horizontalBodyPadding,
          child: FilledButton(
            onPressed: () {
              final timeIncrement = _chosenIncrement;
              ref.read(xiangqiClockProvider.notifier).setupClock(timeIncrement);
              // Red, because red moves first and somebody has to be drawn at the bottom: the side is
              // inert over the board — see [XiangqiOpponent.human] — and the board is turned round
              // from the menu rather than chosen here. A position handed to the screen is what the
              // game starts from; without one it is the standard opening.
              ref
                  .read(xiangqiGameControllerProvider.notifier)
                  .startNewGame(
                    side: XiangqiSide.red,
                    difficulty: XiangqiDifficulty.defaultLevel,
                    opponent: XiangqiOpponent.human,
                    initialPosition: widget.initialFen == null
                        ? null
                        : XiangqiPosition.fromFen(widget.initialFen!),
                  );
              Navigator.pop(context);
            },
            child: Text(context.l10n.play, style: Styles.bold),
          ),
        ),
      ],
    );
  }
}
