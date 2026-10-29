import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:clock/clock.dart' as clock;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock_warning.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart' show XiangqiGameEnd;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/service/move_feedback.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_review_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_result_dialog.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// How often the clocks are redrawn.
///
/// Four times a second, which is a second's resolution with three redraws of slack: the reading is
/// counted locally from the last frame's `server_clock` (see
/// [XiangqiOnlineGameState.secondsLeftFor]), so the only thing this period decides is how late the
/// screen can be by, and nothing at all about whether the number is right.
const Duration _kClockTick = Duration(milliseconds: 100);

/// A game on xiangqi.com, on one screen, playing it or watching it.
///
/// One screen for both because they are one thing: the board, the two seats, the clocks and the move
/// list are the same whether this device is one of the two players or a spectator. What changes is
/// [XiangqiOnlineGameState.mySide], and with it three things — whether the board takes taps, whether
/// there is a button to resign, and which way the board faces. Everything else is drawn from one
/// game state that came off one socket, so a spectator and a player are looking at the same object
/// and cannot drift apart.
///
/// The clock is the one thing on the screen the server does not send: it sends a reading and a
/// timestamp once per move, and the seconds in between are counted here. See [_tick].
///
/// Nothing here invents protocol. Draw offers, takebacks and increments are absent rather than
/// disabled, because the shapes of those requests are not known and a guessed one is silently
/// dropped by the server — see [XiangqiOnlineGameController].
class const XiangqiOnlineGameScreen({required final String gameId}) extends ConsumerStatefulWidget {
  /// The route to this game. [gameId] is xiangqi.com's own id, which is what every event of the
  /// conversation is addressed by, so it is the only thing the screen needs to be given.
  static Route<void> buildRoute(String gameId) =>
      buildScreenRoute(screen: XiangqiOnlineGameScreen(gameId: gameId));

  @override
  ConsumerState<XiangqiOnlineGameScreen> createState() => _XiangqiOnlineGameScreenState();
}

class _XiangqiOnlineGameScreenState() extends ConsumerState<XiangqiOnlineGameScreen> {
  bool _isFlipped = false;

  /// The instant the clocks are counted from. Ticked by [_ticker], read by the two rows.
  late DateTime _now = clock.clock.now();

  Timer? _ticker;
  final Set<Timer> _feedbackTimers = {};
  Timer? _resultTimer;
  bool _resultShown = false;
  bool _loadedBefore = false;
  XiangqiLowTimeWarning _clockWarning = XiangqiLowTimeWarning();
  bool _active = true;

  Future<void> _playLowTime(int generation) async {
    try {
      if (!await ref.read(clockSoundProvider.future) || !mounted) return;
    } catch (_) {
      return;
    }
    if (generation != ref.read(xiangqiAccountGenerationProvider)) {
      return;
    }
    final state = ref.read(xiangqiOnlineGameControllerProvider(widget.gameId)).value;
    if (!_active ||
        state == null ||
        !state.isMyTurn ||
        state.isFinished ||
        !state.isAtLivePosition ||
        !state.isConnected ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    unawaited(ref.read(soundServiceProvider).play(Sound.lowTime));
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_kClockTick, _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final timer in _feedbackTimers) {
      timer.cancel();
    }
    _resultTimer?.cancel();
    super.dispose();
  }

  /// Keeps [_now] moving, so that the clocks run between the server's frames.
  ///
  /// Between two moves the only thing xiangqi.com sends is the Engine.IO heartbeat: there is no tick
  /// event and no per-second frame, so a clock drawn only when the state changed would stand still
  /// for as long as the opponent thinks — which is exactly when a clock matters. The count itself is
  /// arithmetic on the last frame, not a local timer, so this only decides when it is redrawn.
  ///
  /// A finished or untimed game has nothing to count, and is left alone rather than redrawing four
  /// times a second to print the same number.
  void _tick(Timer _) {
    if (!mounted) return;
    final state = ref.read(xiangqiOnlineGameControllerProvider(widget.gameId)).value;
    if (state == null || state.isFinished) return;
    final now = clock.clock.now();
    final time = state.mySide == null ? null : state.timeLeftFor(state.mySide!, now);
    if (time != null &&
        _clockWarning.shouldNotify(
          timeLeft: time,
          threshold: const Duration(seconds: 30),
          now: now,
          active:
              _active &&
              state.isMyTurn &&
              state.isConnected &&
              state.isAtLivePosition &&
              (ModalRoute.of(context)?.isCurrent ?? true),
        )) {
      unawaited(_playLowTime(ref.read(xiangqiAccountGenerationProvider)));
    }
    setState(() => _now = clock.clock.now());
  }

  @override
  Widget build(BuildContext context) {
    final provider = xiangqiOnlineGameControllerProvider(widget.gameId);
    ref.listen(xiangqiAccountGenerationProvider, (_, _) {
      _resultTimer?.cancel();
      for (final timer in _feedbackTimers) {
        timer.cancel();
      }
      _feedbackTimers.clear();
      _resultShown = false;
      _loadedBefore = false;
      _clockWarning = XiangqiLowTimeWarning();
    });
    ref.listen(xiangqiConfirmedMoveProvider(widget.gameId), (previous, next) {
      final update = next.value;
      if (update == null || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final isCapture = update.before.pieceAt(update.move.to) != null;
      final isCheck = rules.isCheck(update.after);
      void playFeedback() {
        if (!mounted || !_active || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        if (ref.read(provider).value?.isAtLivePosition != true) return;
        final service = ref.read(moveFeedbackServiceProvider);
        if (isCapture) {
          service.captureFeedback(null, check: isCheck);
        } else {
          service.moveFeedback(check: isCheck);
        }
      }

      final delay = update.viaDragAndDrop
          ? Duration.zero
          : ref.read(boardPreferencesProvider).pieceAnimationDuration ~/ 2;
      if (delay <= Duration.zero) {
        playFeedback();
      } else {
        late final Timer timer;
        timer = Timer(delay, () {
          _feedbackTimers.remove(timer);
          if (mounted) playFeedback();
        });
        _feedbackTimers.add(timer);
      }
    });
    final asyncState = ref.watch(provider);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    ref.listen(boardPreferencesProvider.select((prefs) => prefs.premoves), (_, enabled) {
      if (!enabled) ref.read(provider.notifier).cancelPremove();
    });

    // Announced once, when it arrives: a dialog drawn from the state would be re-shown on every
    // rebuild, and a spectator's game can end in a snapshot as easily as in an end frame.
    ref.listen<XiangqiGameEnd?>(provider.select((s) => s.value?.end), (previous, next) {
      if (next == null || next == previous || !context.mounted || _resultShown) return;
      final state = ref.read(provider).value;
      if (state == null) return;
      final generation = ref.read(xiangqiAccountGenerationProvider);
      _resultTimer?.cancel();
      _resultTimer = Timer(!_loadedBefore ? Duration.zero : const Duration(milliseconds: 400), () {
        if (!mounted ||
            !_active ||
            _resultShown ||
            !(ModalRoute.of(context)?.isCurrent ?? true) ||
            generation != ref.read(xiangqiAccountGenerationProvider) ||
            ref.read(provider).value?.end != state.end) {
          return;
        }
        _resultShown = true;
        showAdaptiveDialog<void>(
          context: context,
          builder: (context) => XiangqiOnlineResultDialog(state: state),
        );
      });
    });

    if (asyncState.value?.isLoaded == true) _loadedBefore = true;
    return Scaffold(
      appBar: AppBar(
        // The game's own name, translated like every other — see the offline screens' titles.
        title: AppBarTitleText(context.l10n.mobileXiangqi),
      ),
      body: SafeArea(
        child: switch (asyncState) {
          AsyncData(:final value) => _game(context, value, boardPrefs),
          AsyncError(:final error) => _Failed(
            message: error.toString(),
            onRetry: () => ref.invalidate(xiangqiOnlineGameControllerProvider(widget.gameId)),
          ),
          _ => const Center(child: CircularProgressIndicator.adaptive()),
        },
      ),
    );
  }

  Widget _game(BuildContext context, XiangqiOnlineGameState state, BoardPrefs boardPrefs) {
    // **The error is checked before the spinner, and that order is the whole of this method.** A
    // state that has failed to load is not a state that is still loading: the socket reports what
    // went wrong by setting [XiangqiOnlineGameState.error] and leaving `isLoaded` false, because
    // nothing was ever read. Reading `isLoaded` first would draw a spinner for a game that is never
    // coming, and the reader would have no way to tell that from a slow one.
    if (!state.isLoaded) {
      final error = state.error;
      if (error == null) return const Center(child: CircularProgressIndicator.adaptive());
      return _Failed(
        message: error,
        // Retrying is asking again, and the socket client is already reconnecting on its own with a
        // back-off behind it — this is the reader saying "now", not the app's only chance.
        onRetry: () => ref.invalidate(xiangqiOnlineGameControllerProvider(widget.gameId)),
      );
    }

    final controller = ref.read(xiangqiOnlineGameControllerProvider(widget.gameId).notifier);
    final l10n = context.l10n;
    final mySide = state.mySide;
    final isSpectator = mySide == null;

    // A spectator has no side to face, so the board faces red — the side the notation and the
    // starting positions are written from, and the side whose pieces are at the bottom of every
    // diagram of a xiangqi game.
    final orientation = _isFlipped
        ? (mySide ?? XiangqiSide.red).opposite
        : (mySide ?? XiangqiSide.red);
    final topSide = orientation.opposite;
    final boardStyle = XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors);

    return FocusDetector(
      onFocusGained: () => _active = true,
      onFocusLost: () {
        _active = false;
        _resultTimer?.cancel();
        for (final timer in _feedbackTimers) {
          timer.cancel();
        }
        _feedbackTimers.clear();
      },
      // Coming back to the screen is the moment to find out whether anything happened while it was
      // away — and for a spectator it is the only moment there is: nothing else tells a watcher that
      // the game has ended. See [XiangqiOnlineGameController.resync].
      onFocusRegained: () {
        if (!context.mounted) return;
        unawaited(controller.resync());
      },
      child: XiangqiGameLayout(
        board: BrightnessHueFilter(
          brightness: boardPrefs.brightness,
          hue: boardPrefs.hue,
          child: XiangqiBoard(
            position: state.position,
            orientation: orientation,
            selected: state.selected,
            premove: ref.watch(xiangqiPendingPremoveProvider(widget.gameId))?.move,
            isPremoveSelection: state.mySide != null && state.turn != state.mySide,
            // The dots under a picked-up piece are the player's own legal moves, and the setting
            // that hides them everywhere else hides them here too.
            moves: boardPrefs.showLegalMoves ? state.selectedMoves : const IListConst([]),
            lastMove: state.lastMove,
            // Watching is not playing: a spectator's board takes no taps and no drags at all, which
            // is a different thing from a player's board refusing a move in the controller — there
            // is nothing to refuse when there is nothing to tap.
            onTapSquare:
                isSpectator || !state.isConnected || !state.isAtLivePosition || state.isFinished
                ? null
                : (square) => controller.tapSquare(square, premoveEnabled: boardPrefs.premoves),
            onDragMove:
                isSpectator || !state.isConnected || !state.isAtLivePosition || state.isFinished
                ? null
                : (from, to) => controller.movePiece(from, to, premoveEnabled: boardPrefs.premoves),
            onCancelInteraction: controller.clearSelection,
            animationDuration: controller.animateUpdate
                ? boardPrefs.pieceAnimationDuration
                : Duration.zero,
            showCoordinates: boardPrefs.coordinates,
            showLastMove: boardPrefs.boardHighlights,
            showBorder: boardPrefs.showBorder,
            magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
            dragTargetKind: boardPrefs.dragTargetKind,
            settings: XiangqiBoardSettings.fromPreferences(boardPrefs),
            canStartDrag: (piece) =>
                state.isAtLivePosition &&
                !state.isFinished &&
                state.isConnected &&
                !controller.pendingMove &&
                (state.isMyTurn || boardPrefs.premoves) &&
                piece.side == mySide,
            style: boardStyle,
          ),
        ),
        topTable: XiangqiOnlinePlayerRow(
          side: topSide,
          player: topSide == XiangqiSide.red ? state.red : state.black,
          secondsLeft: state.secondsLeftFor(topSide, _now),
          timeLeft: state.timeLeftFor(topSide, _now),
          isTurn: !state.isFinished && state.turn == topSide,
          isMe: mySide == topSide,
          style: boardStyle,
        ),
        bottomTable: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            XiangqiOnlinePlayerRow(
              side: orientation,
              player: orientation == XiangqiSide.red ? state.red : state.black,
              secondsLeft: state.secondsLeftFor(orientation, _now),
              timeLeft: state.timeLeftFor(orientation, _now),
              isTurn: !state.isFinished && state.turn == orientation,
              isMe: mySide == orientation,
              style: boardStyle,
            ),
            // Watching, and why nothing is happening: a spectator is not told when a game ends any
            // more often than anyone else is, and this is the line that says whose board this is.
            if (isSpectator || state.error != null || !state.isConnected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  state.error ?? (!state.isConnected ? l10n.reconnecting : l10n.watch),
                  style: TextStyle(fontStyle: FontStyle.italic, color: textShade(context, 0.6)),
                ),
              ),
          ],
        ),
        // The line of play, in the game's own notation. Players and spectators can step back
        // through it; playing is only accepted again once the board is at the live end.
        moves: xiangqiGameNotation(state.positions, state.moves),
        currentMoveIndex: state.viewCursor,
        onSelectMove: (index) => _goTo(controller, state, index),
        userActionsBar: BottomBar(
          children: [
            HistoryNavigationButton(
              forward: false,
              onTap: state.viewCursor > 0
                  ? () => _goTo(controller, state, state.viewCursor - 1)
                  : null,
            ),
            HistoryNavigationButton(
              forward: true,
              onTap: state.viewCursor < state.positions.length - 1
                  ? () => _goTo(controller, state, state.viewCursor + 1)
                  : null,
              blink:
                  state.isConnected &&
                  !state.isFinished &&
                  !state.isAtLivePosition &&
                  state.mySide != null &&
                  state.turn == state.mySide,
            ),
            BottomBarButton(
              label: l10n.flipBoard,
              onTap: () => setState(() => _isFlipped = !_isFlipped),
              icon: CupertinoIcons.arrow_2_squarepath,
            ),
            // The game's own chat, which is the same room the site shows beside the board: the
            // `game` kind of a chat whose `room` is this game's id. A spectator reads it too — it
            // is the same conversation either way.
            BottomBarButton(
              label: l10n.mobileXiangqiChat,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                XiangqiChatRoomScreen.buildRoute(
                  roomKey: (kind: XiangqiChatKind.game, room: widget.gameId),
                  title: l10n.mobileXiangqiChatGame,
                ),
              ),
              icon: CupertinoIcons.chat_bubble_2,
            ),
            // A spectator has nobody to resign as, and a finished game has nothing to resign, so
            // the button is not there at all rather than there and inert.
            if (!isSpectator)
              BottomBarButton(
                label: l10n.resign,
                onTap: state.isFinished || !state.isConnected
                    ? null
                    : () => _confirmResign(context, controller),
                icon: CupertinoIcons.flag,
              ),
            // A game that is over can be gone through move by move. Offered to a spectator as well
            // as to a player: what a review is, is the game read back, and that is the same
            // question for the two of them.
            if (state.isFinished)
              BottomBarButton(
                label: l10n.mobileXiangqiReview,
                onTap: () => Navigator.of(
                  context,
                  rootNavigator: true,
                ).push(XiangqiReviewScreen.buildRoute(widget.gameId)),
                icon: CupertinoIcons.chart_bar_alt_fill,
              ),
            BottomBarButton(
              label: l10n.close,
              onTap: () => Navigator.of(context).maybePop(),
              icon: CupertinoIcons.xmark,
            ),
          ],
        ),
      ),
    );
  }

  void _goTo(XiangqiOnlineGameController controller, XiangqiOnlineGameState state, int target) {
    for (final timer in _feedbackTimers) {
      timer.cancel();
    }
    _feedbackTimers.clear();
    if ((target - state.viewCursor).abs() == 1 && state.moves.isNotEmpty) {
      final index = (target > state.viewCursor ? target - 1 : state.viewCursor - 1).clamp(
        0,
        state.moves.length - 1,
      );
      final capture = state.positions[index].pieceAt(state.moves[index].to) != null;
      ref.read(soundServiceProvider).play(capture ? Sound.capture : Sound.move);
    }
    controller.goTo(target);
  }

  /// Asks before resigning, and says nothing if the answer is no.
  ///
  /// The same confirmation the offline screen asks for the same irreversible act, in the same words.
  void _confirmResign(BuildContext context, XiangqiOnlineGameController controller) {
    if (!ref.read(boardPreferencesProvider).confirmResignAndDraw) {
      unawaited(controller.resign());
      return;
    }
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) => YesNoDialog(
        content: Text(context.l10n.mobileAreYouSure),
        onYes: () {
          Navigator.pop(context);
          unawaited(controller.resign());
        },
        onNo: () => Navigator.pop(context),
      ),
    );
  }
}

/// Something did not arrive, and there is a way to ask again.
///
/// The shape the other xiangqi screens use for the same moment, kept here rather than imported: the
/// three of them are a sentence and a button, and a shared widget for two lines would be a file to
/// find rather than a thing to read.
class const _Failed({required final String message, required final VoidCallback onRetry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Styles.bodySectionPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16.0),
            FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}

/// One of the two rows beside the board: which seat it is, who is in it, and what its clock reads.
///
/// A class rather than two built trees, because the two rows have to be the same thing on both sides
/// of the board: the only differences between them are which seat they are given, and which of the
/// two clocks is running.
///
/// The avatar is the side's own general, drawn by [XiangqiPieceAvatar] — the same piece the board
/// draws, so the mark by the name and the pieces in play cannot drift apart.
///
/// The clock is [secondsLeft] as the state counted it at the moment the screen last drew, or null
/// for an untimed game, which is a row with no clock rather than a row showing zero.
class const XiangqiOnlinePlayerRow({
  /// Which seat this row is.
  required final XiangqiSide side,

  /// Who is in it.
  required final XiangqiOnlinePlayer player,

  /// What this seat's clock reads, or null when the game is untimed.
  required final int? secondsLeft,
  final Duration? timeLeft,

  /// Whether it is this seat's move.
  required final bool isTurn,

  /// Whether this seat is the one this device is in.
  required final bool isMe,

  /// The board's own colours, so that the two avatars match the pieces they stand for.
  required final XiangqiBoardStyle style,

  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final seconds = secondsLeft;
    final name = player.isTaken
        ? player.name
        : side == XiangqiSide.red
        ? l10n.mobileXiangqiSideRed
        : l10n.mobileXiangqiSideBlack;

    return XiangqiPlayerRow(
      side: side,
      style: style,
      name: name,
      rating: player.rating?.toString(),
      isMe: isMe,
      isToMove: isTurn,
      clock: seconds == null
          ? null
          : Clock(
              timeLeft: timeLeft ?? Duration(seconds: seconds),
              active: isTurn,
              emergencyThreshold: const Duration(seconds: 30),
              clockTenths:
                  ref.watch(clockTenthsProvider).value ?? defaultAccountPreferences.clockTenths,
            ),
    );
  }
}

/// How an online game ended, in a sentence.
///
/// The app's own sentences, from the same localizations the offline screens use and for the same
/// reasons — see the offline `xiangqiResultLabel`. The two sides are named the same way
/// ([XiangqiSide.label]), so a game reads the same way whether it was played here or on
/// xiangqi.com.
///
/// The split is the one the rules force: mate and 困毙 are positions, so their loser is whoever is
/// to move in them, while a resignation and a flag are events and name their own side. The last arm
/// is unreachable rather than defensive — [XiangqiOnlineGameController] refuses to make an ending
/// out of one whose loser it cannot name — and exists to complete the switch.
String xiangqiOnlineResultLabel(BuildContext context, XiangqiOnlineGameState state) =>
    switch (state.end) {
      .checkmate => context.l10n.mobileXiangqiCheckmated(state.turn.label(context.l10n)),
      .stalemate => context.l10n.mobileXiangqiStalemateLoss(state.turn.label(context.l10n)),
      // The one draw sentence the app has. xiangqi.com has three ways of drawing a game and this is
      // the only one of them that was translated.
      .threefoldRepetition => context.l10n.mobileXiangqiThreefoldRepetition,
      .resign when state.resignedBy != null => context.l10n.mobileXiangqiResigned(
        state.resignedBy!.label(context.l10n),
      ),
      .timeout when state.flaggedSide != null => context.l10n.mobileXiangqiRanOutOfTime(
        state.flaggedSide!.label(context.l10n),
      ),
      _ => '',
    };

/// How an online game ended, and the way out of it.
///
/// Deliberately not the offline screen's own result dialog: that one is typed to the offline state,
/// which carries a player's side and an engine's opponent that a game on xiangqi.com has no
/// equivalent of. What the two share is the sentences, and those are shared properly — this calls
/// the same localizations.
class const XiangqiOnlineResultDialog({required final XiangqiOnlineGameState state, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final winner = state.winner;
    final mySide = state.mySide;

    return XiangqiResultDialog(
      activationDelay: const Duration(milliseconds: 1000),
      // "Victory" is only ever this device's own win: a spectator has no side and gets the neutral
      // title, which is what a draw gets as well.
      title: winner == null
          ? context.l10n.draw
          : mySide == winner
          ? context.l10n.victory
          : context.l10n.gameOver,
      score: winner == null
          ? '½ - ½'
          : winner == .red
          ? '1 - 0'
          : '0 - 1',
      explanation: xiangqiOnlineResultLabel(context, state),
      actionsBuilder: (context, enabled) => [
        TextButton(
          onPressed: enabled ? () => Navigator.of(context).pop() : null,
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
