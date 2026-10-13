import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:clock/clock.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart' show XiangqiGameEnd;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// How often the clocks are redrawn.
///
/// Four times a second, which is a second's resolution with three redraws of slack: the reading is
/// counted locally from the last frame's `server_clock` (see
/// [XiangqiOnlineGameState.secondsLeftFor]), so the only thing this period decides is how late the
/// screen can be by, and nothing at all about whether the number is right.
const Duration _kClockTick = Duration(milliseconds: 250);

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
  late DateTime _now = clock.now();

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_kClockTick, _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
    setState(() => _now = clock.now());
  }

  @override
  Widget build(BuildContext context) {
    final provider = xiangqiOnlineGameControllerProvider(widget.gameId);
    final asyncState = ref.watch(provider);
    final boardPrefs = ref.watch(boardPreferencesProvider);

    // Announced once, when it arrives: a dialog drawn from the state would be re-shown on every
    // rebuild, and a spectator's game can end in a snapshot as easily as in an end frame.
    ref.listen<XiangqiGameEnd?>(provider.select((s) => s.value?.end), (previous, next) {
      if (next == null || next == previous || !context.mounted) return;
      final state = ref.read(provider).value;
      if (state == null) return;
      showDialog<void>(
        context: context,
        builder: (context) => XiangqiOnlineResultDialog(state: state),
      );
    });

    return Scaffold(
      appBar: AppBar(
        // The game's own name, translated like every other — see the offline screens' titles.
        title: AppBarTitleText(context.l10n.mobileXiangqi),
      ),
      body: SafeArea(
        child: switch (asyncState) {
          AsyncData(:final value) => _game(context, value, boardPrefs),
          AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error.toString(), textAlign: TextAlign.center),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator.adaptive()),
        },
      ),
    );
  }

  Widget _game(BuildContext context, XiangqiOnlineGameState state, BoardPrefs boardPrefs) {
    if (!state.isLoaded) return const Center(child: CircularProgressIndicator.adaptive());

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
            // The dots under a picked-up piece are the player's own legal moves, and the setting
            // that hides them everywhere else hides them here too.
            moves: boardPrefs.showLegalMoves ? state.selectedMoves : const IListConst([]),
            lastMove: boardPrefs.boardHighlights ? state.lastMove : null,
            // Watching is not playing: a spectator's board takes no taps and no drags at all, which
            // is a different thing from a player's board refusing a move in the controller — there
            // is nothing to refuse when there is nothing to tap.
            onTapSquare: isSpectator ? null : controller.tapSquare,
            onDragMove: isSpectator
                ? null
                : (from, to) {
                    controller.tapSquare(from);
                    controller.tapSquare(to);
                  },
            animationDuration: boardPrefs.pieceAnimationDuration,
            showCoordinates: boardPrefs.coordinates,
            showLastMove: boardPrefs.boardHighlights,
            showBorder: boardPrefs.showBorder,
            magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
            dragTargetKind: boardPrefs.dragTargetKind,
            style: boardStyle,
          ),
        ),
        topTable: XiangqiOnlinePlayerRow(
          side: topSide,
          player: topSide == XiangqiSide.red ? state.red : state.black,
          secondsLeft: state.secondsLeftFor(topSide, _now),
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
              isTurn: !state.isFinished && state.turn == orientation,
              isMe: mySide == orientation,
              style: boardStyle,
            ),
            // Watching, and why nothing is happening: a spectator is not told when a game ends any
            // more often than anyone else is, and this is the line that says whose board this is.
            if (isSpectator || state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  state.error ?? l10n.watch,
                  style: TextStyle(fontStyle: FontStyle.italic, color: textShade(context, 0.6)),
                ),
              ),
          ],
        ),
        // The line of play, in the game's own notation, marked at the move just played. A list and
        // not a control: neither the player nor the spectator can step back through the game, so
        // there is nothing to select. See [XiangqiGameLayout]'s `onSelectMove`.
        moves: xiangqiGameNotation(state.positions, state.moves),
        currentMoveIndex: state.positions.length - 1,
        onSelectMove: null,
        userActionsBar: BottomBar(
          children: [
            BottomBarButton(
              label: l10n.flipBoard,
              onTap: () => setState(() => _isFlipped = !_isFlipped),
              icon: CupertinoIcons.arrow_2_squarepath,
            ),
            // A spectator has nobody to resign as, and a finished game has nothing to resign, so
            // the button is not there at all rather than there and inert.
            if (!isSpectator)
              BottomBarButton(
                label: l10n.resign,
                onTap: state.isFinished ? null : () => _confirmResign(context, controller),
                icon: CupertinoIcons.flag,
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

  /// Asks before resigning, and says nothing if the answer is no.
  ///
  /// The same confirmation the offline screen asks for the same irreversible act, in the same words.
  void _confirmResign(BuildContext context, XiangqiOnlineGameController controller) {
    showDialog<void>(
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

/// One of the two rows beside the board: which seat it is, who is in it, and what its clock reads.
///
/// A class rather than two built trees, because the two rows have to be the same thing on both sides
/// of the board: the only differences between them are which seat they are given, and which of the
/// two clocks is running.
///
/// The avatar carries the side's own general — 帅 for red and 将 for black, taken from
/// [XiangqiPiece.glyph] rather than written here, so the two characters on the two rows are the same
/// two the board draws its generals with.
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

  /// Whether it is this seat's move.
  required final bool isTurn,

  /// Whether this seat is the one this device is in.
  required final bool isMe,

  /// The board's own colours, so that the two avatars match the pieces they stand for.
  required final XiangqiBoardStyle style,

  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final seconds = secondsLeft;
    final ink = side == XiangqiSide.red ? style.redInk : style.blackInk;

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: ink,
          child: Text(
            XiangqiPiece(side, XiangqiPieceType.king).glyph,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                // An empty seat is still a row: the game is on the board before both players have
                // taken their seats, and the side is the honest thing to print until somebody sits.
                child: Text(
                  player.isTaken
                      ? player.name
                      : side == XiangqiSide.red
                      ? l10n.mobileXiangqiSideRed
                      : l10n.mobileXiangqiSideBlack,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isTurn ? null : textShade(context, 0.6),
                  ),
                ),
              ),
              if (player.rating != null) ...[
                const SizedBox(width: 4),
                Text('(${player.rating})', style: TextStyle(color: textShade(context, 0.6))),
              ],
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(Icons.person, size: 16, color: textShade(context, 0.5)),
              ],
            ],
          ),
        ),
        if (seconds != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              _clockText(seconds),
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: isTurn ? FontWeight.w700 : FontWeight.w400,
                color: isTurn ? null : textShade(context, 0.6),
              ),
            ),
          ),
      ],
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

    return AlertDialog.adaptive(
      // "Victory" is only ever this device's own win: a spectator has no side and gets the neutral
      // title, which is what a draw gets as well.
      title: Text(
        winner == null
            ? context.l10n.draw
            : mySide == winner
            ? context.l10n.victory
            : context.l10n.gameOver,
      ),
      content: Text(xiangqiOnlineResultLabel(context, state)),
      actions: [
        PlatformDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

/// A clock as a player reads one: whole minutes, and the seconds always two digits.
///
/// Not the chess screens' own clock widget, which is typed to a lichess `GameState` and its
/// increment handling from its constructor down, and none of that crosses over — xiangqi.com counts
/// down one number per side with no increment to add on. This is the same shape at the same
/// resolution: what is left, and nothing about how it got there.
String _clockText(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
