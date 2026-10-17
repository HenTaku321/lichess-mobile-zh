import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart' show Variant;
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_export.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/service/move_feedback.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_board_editor_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:material_ui/material_ui.dart';

/// How tall one engine line is drawn, and how large its text is.
///
/// The chess analysis's own two numbers — `kEngineLineHeight` and `kEngineLineFontSize` in
/// `engine_lines.dart` — because a line of an engine's reading is the same thing on either board and
/// looks wrong at any other size beside the move list it is read with.
const double _kEngineLineHeight = 24.0;
const double _kEngineLineFontSize = 11.0;

/// The colours of the first, second and third engine arrows.
///
/// The first is the board's own hint blue; the others are distinct enough to tell two lines apart
/// without turning the position into a rainbow. They are deliberately not board-theme colours: an
/// arrow is the engine speaking, not part of the wood.
const _analysisArrowColors = [Color(0xFF0099C8), Color(0xFFE69826), Color(0xFF7B61FF)];

/// A board to take a xiangqi position apart on.
///
/// The mirror of the chess analysis board: a board to move pieces on, the line those moves make in
/// the game's own notation, a bar of the engine's verdict, and the engine's own lines under them.
/// Every one of those is a feature the chess screen has, put together the same way and from the same
/// kind of parts — a layout that measures the board, a board that reports taps, a move list that can
/// be stepped through. Nothing here is a xiangqi-only idea and nothing here is missing that the
/// chess board has, except the parts of that screen that are lichess's server answering: the opening
/// explorer, the server-side analysis, and the move times, none of which have anything to say about
/// a game lichess does not play.
///
/// What it is not is a game. There is no opponent, no clock and no result: the position is the
/// player's to move pieces in, and the engine is there to say what it thinks rather than to answer
/// with a move of its own. It also survives being left and come back to — see
/// [xiangqiAnalysisControllerProvider] — which is the one way it is more like the chess analysis
/// board than the xiangqi game screen beside it is.
class const XiangqiAnalysisScreen({
  /// The position to open the board on, or null to open on whatever the last session left.
  ///
  /// A FEN rather than a [XiangqiPosition], because this is the screen's edge and what a board
  /// editor or a deep link has to hand: it goes to the controller's own `setFen`, which parses it.
  /// Assumed well formed — its only source is [XiangqiPosition.toFen] — so a bad one throws rather
  /// than being quietly replaced by the opening.
  final String? initialFen,
}) extends ConsumerWidget {
  static Route<void> buildRoute({String? initialFen}) =>
      buildScreenRoute(screen: XiangqiAnalysisScreen(initialFen: initialFen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // The game it analyses, then what the screen is: the same shape the chess analysis board's
      // title takes when it is analysing a variant, and out of the app's own two names rather than
      // one of this screen's making.
      appBar: AppBar(
        title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.analysis}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.l10n.boardEditor,
            // What is on the board, handed over as a FEN, which is the one thing an editor and an
            // analysis board both speak. This is the way in that opens on the position being looked
            // at; the More tab's row opens the same editor on the starting position, and the chess
            // analysis board reaches its own editor through its menu.
            //
            // Read rather than watched: the app bar is the screen's and the position is the
            // controller's, which the body watches, and this only has to be right at the moment the
            // button is pressed. It is a position and nothing else, so the board opens red at the
            // bottom whatever way up this screen's own board is drawn — which way up a board is drawn
            // is the screen's business and is not a fact about the position.
            onPressed: () => Navigator.of(context).push(
              XiangqiBoardEditorScreen.buildRoute(
                initialFen: ref.read(xiangqiAnalysisControllerProvider).position.toFen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: context.l10n.reset,
            // Reset puts the board back to the starting position and throws the line away, which is
            // why it sits up here and not in the bar with taking a move back: it is not a step
            // through the line, it is the end of it.
            onPressed: () => ref.read(xiangqiAnalysisControllerProvider.notifier).reset(),
          ),
        ],
      ),
      body: _Body(initialFen: initialFen),
    );
  }
}

class const _Body({final String? initialFen}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState() extends ConsumerState<_Body> {
  /// Which way up the board is drawn.
  ///
  /// A way of looking at the board and not a fact about the position, exactly as it is in the game
  /// screens: there is no player here to have a side, red moves first and sits at the bottom by
  /// default, and turning it around is a glance rather than a move. Kept here rather than in a
  /// provider because nothing outside this screen has any business with it.
  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    // The engine is started by hand rather than watched into life: `ref.listen` never fires for the
    // value that is already there, and a screen opened with the evaluation on is exactly that value.
    // After the first frame, because the provider is read and written through the ref.
    //
    // A position handed to the screen is put on the board before the engine is started, not after:
    // the engine is asked to search the position that is on the board, and starting it first would
    // begin a search on the session the screen opened on — one that the very next line throws away.
    // Waiting for the frame also lets the controller's own [build] finish, session restore and all,
    // so this is the last word on what the board holds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialFen = widget.initialFen;
      if (initialFen != null) {
        ref.read(xiangqiAnalysisControllerProvider.notifier).setFen(initialFen);
      }
      _syncEngine();
    });
  }

  /// Starts or stops the engine so that it runs exactly when the evaluation is turned on.
  ///
  /// The one setting that decides, and the same one the game screens read: an analysis board whose
  /// engine could be turned on in one place and off in another would be two answers to one question.
  /// See [EngineEvaluationPreferences].
  void _syncEngine() {
    final controller = ref.read(xiangqiAnalysisControllerProvider.notifier);
    if (ref.read(engineEvaluationPreferencesProvider).isEnabled) {
      controller.startEngine();
    } else {
      controller.stopEngine();
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(xiangqiAnalysisControllerProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final evalEnabled = ref.watch(engineEvaluationPreferencesProvider.select((p) => p.isEnabled));
    final numEvalLines = ref.watch(
      engineEvaluationPreferencesProvider.select((p) => p.numEvalLines),
    );
    final shownLines = analysisState.lines.take(numEvalLines).toList();
    final arrows = IList<XiangqiBoardArrow>([
      for (var index = 0; index < shownLines.length; index++)
        if (shownLines[index].moves.isNotEmpty)
          XiangqiBoardArrow(
            move: shownLines[index].moves.first,
            color: _analysisArrowColors[index % _analysisArrowColors.length],
            opacity: index == 0 ? 0.9 : 0.62,
          ),
    ]);
    final controller = ref.read(xiangqiAnalysisControllerProvider.notifier);

    ref.listen(xiangqiAnalysisControllerProvider, (previous, next) {
      if (previous == null ||
          previous.cursor == next.cursor && previous.moves.length == next.moves.length) {
        return;
      }
      final moveIndex = next.cursor > 0 ? next.cursor - 1 : 0;
      if (moveIndex >= next.moves.length || moveIndex >= next.positions.length) return;
      final before = next.positions[moveIndex];
      final move = next.moves[moveIndex];
      final isCapture = before.pieceAt(move.to) != null;
      if (previous.moves.length < next.moves.length) {
        final feedback = ref.read(moveFeedbackServiceProvider);
        if (isCapture) {
          feedback.captureFeedback(null, check: rules.isCheck(next.position));
        } else {
          feedback.moveFeedback(check: rules.isCheck(next.position));
        }
      } else {
        final sound = ref.read(soundServiceProvider);
        if (isCapture) {
          sound.playCaptureSound(Variant.standard);
        } else {
          sound.play(Sound.move);
        }
      }
    });

    ref.listen(engineEvaluationPreferencesProvider.select((p) => p.isEnabled), (_, _) {
      _syncEngine();
    });

    final orientation = _isFlipped ? XiangqiSide.black : XiangqiSide.red;

    // The engine is the app's shared one, and leaving the screen does not mean the player wants it
    // searching: losing focus stops it, exactly as the game screens' own detectors do, and
    // regaining it starts it again rather than leaving an analysis that has quietly stopped.
    //
    // The detector reports a widget that has gone invisible on its way out as well as on its way in,
    // so both callbacks check the context is still mounted before reading anything through the ref:
    // a read on a state that is being torn down is refused outright.
    return FocusDetector(
      onFocusLost: () {
        if (!context.mounted) return;
        ref.read(xiangqiAnalysisControllerProvider.notifier).stopEngine();
      },
      onFocusRegained: () {
        if (!context.mounted) return;
        _syncEngine();
      },
      child: SafeArea(
        child: XiangqiGameLayout(
          board: BrightnessHueFilter(
            brightness: boardPrefs.brightness,
            hue: boardPrefs.hue,
            child: XiangqiBoard(
              position: analysisState.position,
              orientation: orientation,
              selected: analysisState.selected,
              moves: boardPrefs.showLegalMoves ? analysisState.selectedMoves : const IListConst([]),
              lastMove: boardPrefs.boardHighlights ? analysisState.lastMove : null,
              onTapSquare: controller.tapSquare,
              // A drag is the same two taps it would have been, in the order they were made — the
              // same wiring the game screen uses, and it moves nothing that could not be moved.
              onDragMove: (from, to) {
                controller.tapSquare(from);
                controller.tapSquare(to);
              },
              animationDuration: boardPrefs.pieceAnimationDuration,
              showCoordinates: boardPrefs.coordinates,
              showLastMove: boardPrefs.boardHighlights,
              showBorder: boardPrefs.showBorder,
              arrows: arrows,
              magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
              dragTargetKind: boardPrefs.dragTargetKind,
              style: XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors),
            ),
          ),
          // Above the board: how deep the engine has got. The score is not repeated here — it is on
          // the bar beside the board, which is what a bar is for.
          topTable: _AnalysisDepth(depth: analysisState.depth),
          // Under it: what the engine says, in as many lines as the player has asked to be shown.
          bottomTable: _EngineLines(
            state: analysisState,
            count: numEvalLines,
            onPlay: controller.play,
          ),
          evalGauge: evalEnabled
              ? XiangqiEvalGauge(
                  // A bar with nothing to report yet is drawn level rather than left out: the
                  // engine is about to answer, and a bar that came and went would flicker.
                  redWinProbability: analysisState.evaluation?.redWinProbability ?? 0.5,
                  orientation: orientation,
                  evaluation: analysisState.evaluation,
                )
              : null,
          moves: xiangqiGameNotation(analysisState.positions, analysisState.moves),
          // The line of play the player has made, marked at the move they are looking at. Unlike the
          // game screen's, this list is a control: stepping back and forward through what has been
          // played is the whole of what makes it an analysis board.
          currentMoveIndex: analysisState.cursor,
          onSelectMove: controller.goTo,
          userActionsBar: BottomBar(
            children: [
              BottomBarButton(
                label: context.l10n.flipBoard,
                onTap: () => setState(() => _isFlipped = !_isFlipped),
                icon: CupertinoIcons.arrow_2_squarepath,
              ),
              BottomBarButton(
                label: context.l10n.mobileEngineEvaluation,
                // The setting the whole screen hangs off, offered where the player is looking at the
                // board rather than only in the settings screen: an analysis board with no engine is
                // a move list, and the switch that makes it one belongs next to it.
                highlighted: evalEnabled,
                onTap: () {
                  unawaited(ref.read(engineEvaluationPreferencesProvider.notifier).toggle());
                },
                icon: Icons.memory,
              ),
              BottomBarButton(
                label: context.l10n.mobilePreviousMove,
                onTap: analysisState.canGoBack ? controller.goBack : null,
                icon: CupertinoIcons.chevron_back,
              ),
              BottomBarButton(
                label: context.l10n.next,
                onTap: analysisState.canGoForward ? controller.goForward : null,
                icon: CupertinoIcons.chevron_forward,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How deep the engine has got, written above the board.
///
/// Nothing at all before it has answered: a depth of zero is not a depth, and a line that appears
/// with a nought in it and is replaced a moment later is worse than one that arrives when there is
/// something to say.
class const _AnalysisDepth({required final int depth}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (depth == 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        context.l10n.depthX('$depth'),
        style: TextTheme.of(context).bodySmall?.copyWith(color: textShade(context, 0.6)),
      ),
    );
  }
}

/// The engine's lines, best first, under the board.
///
/// One row per line the player has asked for, padded out so that the board does not move up and down
/// as the engine finds them — the same shape, and for the same reason, as the chess analysis's own
/// engine lines. A row says the score the line ends on and then the line itself in the game's
/// notation, and tapping it plays the move the engine would play: the fastest way to look at what
/// the engine is talking about is to go there.
class const _EngineLines({
  required final XiangqiAnalysisState state,
  required final int count,
  required final void Function(XiangqiMove move) onPlay,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final lines = state.lines.take(count).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          _EngineLineRow(
            line: i < lines.length ? lines[i] : null,
            position: state.position,
            onPlay: onPlay,
          ),
      ],
    );
  }
}

/// One line of [_EngineLines], or the empty room one that has not been found yet takes up.
class const _EngineLineRow({
  required final XiangqiEngineLine? line,
  required final XiangqiPosition position,
  required final void Function(XiangqiMove move) onPlay,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final line = this.line;
    if (line == null) return const SizedBox(height: _kEngineLineHeight);

    final moves = line.moves;
    final notation = xiangqiMovesExport(position, moves);
    // Red ahead fills the badge with the colour the evaluation bar has claimed, exactly as the
    // chess analysis's own engine lines fill theirs from the side that is winning. The text on it
    // is chosen the same way the bar's own label is: whichever of the scheme's ink pair reads on
    // the fill the badge was given. See [XiangqiEvalGauge].
    final redIsAhead = line.evaluation.redWinProbability >= 0.5;
    final background = redIsAhead
        ? XiangqiEvalGauge.valueColor(context)
        : XiangqiEvalGauge.backgroundColor(context);
    final scheme = ColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkOnBackground = redIsAhead
        ? (isDark ? scheme.surface : scheme.onSurface)
        : (isDark ? scheme.onSurface : scheme.surface);

    return InkWell(
      onTap: moves.isEmpty ? null : () => onPlay(moves.first),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kEngineLineHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: Styles.boardBorderRadius,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                child: Text(
                  _scoreLabel(line.evaluation),
                  style: TextStyle(
                    color: inkOnBackground,
                    fontSize: _kEngineLineFontSize,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  notation,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textShade(context, 0.9), fontSize: _kEngineLineFontSize),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The score of [evaluation] as short text, or the empty string when there is none.
///
/// Red's point of view, like everything else on this screen: `+1.2` is red a soldier up and `M3` is
/// red mating in three. The sign is carried by the badge's colour rather than by the text — the same
/// division of labour the evaluation bar makes, and the same spelling of a score, since a board and
/// a bar saying `+1.2` and `1.2` for the same position would be two answers to one question. See
/// `_scoreLabel` in `xiangqi_game_layout.dart`.
String _scoreLabel(XiangqiEvaluation evaluation) {
  final mate = evaluation.mate;
  if (mate != null) return mate > 0 ? 'M$mate' : 'M${-mate}';
  final pawns = (evaluation.cp ?? 0) / 100.0;
  return '${pawns > 0 ? '+' : ''}${pawns.toStringAsFixed(1)}';
}
