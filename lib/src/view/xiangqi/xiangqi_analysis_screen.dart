import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_options.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_export.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_settings_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_board_editor_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_engine_button.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/move_variations_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_analysis_layout.dart';
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
  final XiangqiAnalysisOptions? options,
}) extends ConsumerWidget {
  static Route<void> buildRoute({String? initialFen, XiangqiAnalysisOptions? options}) {
    if (initialFen != null && options != null) {
      throw ArgumentError('Pass an initial FEN or a history snapshot, not both.');
    }
    return buildScreenRoute(
      screen: XiangqiAnalysisScreen(
        options:
            options ??
            (initialFen == null
                ? null
                : XiangqiAnalysisOptions.line(
                    sourceId: 'position',
                    initialPosition: XiangqiPosition.fromFen(initialFen),
                    moves: const IListConst([]),
                  )),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imported = options;
    final screen = Scaffold(
      // The game it analyses, then what the screen is: the same shape the chess analysis board's
      // title takes when it is analysing a variant, and out of the app's own two names rather than
      // one of this screen's making.
      appBar: AppBar(
        title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.analysis}'),
      ),
      body: _Body(initialFen: initialFen, initialOrientation: imported?.orientation ?? .red),
    );
    return imported == null
        ? screen
        : _ImportedAnalysisScope(
            key: ValueKey(imported.sourceKey),
            options: imported,
            child: screen,
          );
  }
}

class const _ImportedAnalysisScope({
  required final XiangqiAnalysisOptions options,
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  @override
  State<_ImportedAnalysisScope> createState() => _ImportedAnalysisScopeState();
}

class _ImportedAnalysisScopeState() extends State<_ImportedAnalysisScope> {
  // Stable overrides: rebuilds for a theme or locale change must not recreate the session.
  late final _overrides = [
    xiangqiAnalysisControllerProvider.overrideWith(
      () => XiangqiAnalysisController(options: widget.options),
    ),
  ];

  @override
  Widget build(BuildContext context) => ProviderScope(overrides: _overrides, child: widget.child);
}

class const _Body({
  final String? initialFen,
  final XiangqiSide initialOrientation = XiangqiSide.red,
}) extends ConsumerStatefulWidget {
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
    _isFlipped = widget.initialOrientation == XiangqiSide.black;
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
    if (controller.engineAllowed && ref.read(engineEvaluationPreferencesProvider).isEnabled) {
      controller.startEngine();
    } else {
      controller.stopEngine();
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(xiangqiAnalysisControllerProvider);
    final analysisPrefs = ref.watch(analysisPreferencesProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final evalEnabled =
        ref.watch(engineEvaluationPreferencesProvider.select((p) => p.isEnabled)) &&
        ref.read(xiangqiAnalysisControllerProvider.notifier).engineAllowed;
    final numEvalLines = ref.watch(
      engineEvaluationPreferencesProvider.select((p) => p.numEvalLines),
    );
    final shownLines = analysisState.lines.take(numEvalLines > 0 ? numEvalLines : 1).toList();
    final arrows = IList<XiangqiBoardArrow>([
      if (evalEnabled && analysisPrefs.showBestMoveArrow)
        for (var index = 0; index < shownLines.length; index++)
          if (shownLines[index].moves.isNotEmpty)
            XiangqiBoardArrow(
              move: shownLines[index].moves.first,
              color: _analysisArrowColors[index % _analysisArrowColors.length],
              opacity: index == 0 ? 0.9 : 0.62,
            ),
    ]);
    final controller = ref.read(xiangqiAnalysisControllerProvider.notifier);

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
        child: XiangqiAnalysisLayout(
          smallBoard: analysisPrefs.smallBoard,
          inlineNotation: analysisPrefs.inlineNotation,
          boardBuilder: (context, size, radius) => BrightnessHueFilter(
            brightness: boardPrefs.brightness,
            hue: boardPrefs.hue,
            child: XiangqiBoard(
              position: analysisState.position,
              orientation: orientation,
              selected: analysisState.selected,
              moves: boardPrefs.showLegalMoves ? analysisState.selectedMoves : const IListConst([]),
              lastMove: analysisState.lastMove,
              onTapSquare: controller.tapSquare,
              onDragMove: controller.movePiece,
              onCancelInteraction: controller.clearSelection,
              animationDuration: controller.shouldAnimateUpdate
                  ? boardPrefs.pieceAnimationDuration
                  : Duration.zero,
              showCoordinates: boardPrefs.coordinates,
              showLastMove: boardPrefs.boardHighlights,
              showBorder: boardPrefs.showBorder,
              arrows: arrows,
              magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
              dragTargetKind: boardPrefs.dragTargetKind,
              settings: XiangqiBoardSettings.fromPreferences(boardPrefs),
              canStartDrag: (piece) => piece.side == analysisState.position.turn,
              style: XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors),
            ),
          ),
          // Above the board: how deep the engine has got. The score is not repeated here — it is on
          // the bar beside the board, which is what a bar is for.
          boardHeader: _AnalysisDepth(depth: analysisState.depth),
          // Under it: what the engine says, in as many lines as the player has asked to be shown.
          engineLinesHeight: numEvalLines * _kEngineLineHeight,
          engineLines: !evalEnabled || !analysisPrefs.showEngineLines || numEvalLines == 0
              ? null
              : _EngineLines(state: analysisState, count: numEvalLines, onPlay: controller.play),
          evalGauge: evalEnabled && analysisPrefs.showEvaluationGauge
              ? XiangqiEvalGauge(
                  // A bar with nothing to report yet is drawn level rather than left out: the
                  // engine is about to answer, and a bar that came and went would flicker.
                  redWinProbability: analysisState.evaluation?.redWinProbability ?? 0.5,
                  orientation: orientation,
                  evaluation: analysisState.evaluation,
                  outcome: analysisState.isFinished
                      ? (winner: analysisState.position.turn.opposite)
                      : null,
                )
              : null,
          moves: xiangqiGameNotation(analysisState.positions, analysisState.moves),
          // The line of play the player has made, marked at the move they are looking at. Unlike the
          // game screen's, this list is a control: stepping back and forward through what has been
          // played is the whole of what makes it an analysis board.
          currentMoveIndex: analysisState.cursor,
          onSelectMove: controller.goTo,
          panelFooter: MoveVariationsBar<XiangqiMove>(
            choices: [
              for (var i = 0; i < analysisState.variations.length; i++)
                MoveVariationChoice(
                  value: analysisState.variations[i].move!,
                  label: xiangqiMoveNotation(
                    analysisState.position,
                    analysisState.variations[i].move!,
                  ),
                  mainline: i == 0,
                ),
            ],
            onSelect: controller.selectVariation,
          ),
          bottomBar: BottomBar(
            children: [
              BottomBarButton(label: context.l10n.menu, icon: Icons.menu, onTap: _showMenu),
              BottomBarButton(
                label: context.l10n.flipBoard,
                onTap: () => setState(() => _isFlipped = !_isFlipped),
                icon: CupertinoIcons.arrow_2_squarepath,
              ),
              if (controller.engineAllowed) const XiangqiEngineButton(),
              HistoryNavigationButton(
                forward: false,
                onTap: analysisState.canGoBack ? controller.goBack : null,
                onRepeat: () => controller.goBack(fastSeek: true),
              ),
              HistoryNavigationButton(
                forward: true,
                onTap: analysisState.canGoForward ? controller.goForward : null,
                onRepeat: () => controller.goForward(fastSeek: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu() {
    final state = ref.read(xiangqiAnalysisControllerProvider);
    showAdaptiveActionSheet<void>(
      context: context,
      actions: [
        if (state.variationTree?.canPromote(state.moves.sublist(0, state.cursor)) ?? false)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.promoteVariation),
            onPressed: () =>
                ref.read(xiangqiAnalysisControllerProvider.notifier).promoteVariation(),
          ),
        if (state.cursor > 0)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.deleteFromHere),
            onPressed: () => ref.read(xiangqiAnalysisControllerProvider.notifier).retract(),
          ),
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.settingsSettings),
          onPressed: () => Navigator.of(context).push(XiangqiAnalysisSettingsScreen.buildRoute()),
        ),
        if (ref.read(xiangqiAnalysisControllerProvider.notifier).isStandalone)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.clearLocalData),
            onPressed: () => showConfirmDialog<void>(
              context,
              title: Text(context.l10n.clearLocalData),
              onConfirm: () {
                if (!mounted) return;
                clearSavedXiangqiAnalysis();
                ref.read(xiangqiAnalysisControllerProvider.notifier).reset();
              },
            ),
          ),
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.boardEditor),
          onPressed: () => Navigator.of(context).push(
            XiangqiBoardEditorScreen.buildRoute(
              initialFen: ref.read(xiangqiAnalysisControllerProvider).position.toFen(),
            ),
          ),
        ),
        BottomSheetAction(
          makeLabel: (context) => Text('${context.l10n.copyToClipboard} · FEN'),
          onPressed: () =>
              _copy(xiangqiFenExport(ref.read(xiangqiAnalysisControllerProvider).position)),
        ),
        BottomSheetAction(
          makeLabel: (context) =>
              Text('${context.l10n.copyToClipboard} · ${context.l10n.movesPlayed}'),
          onPressed: () {
            final state = ref.read(xiangqiAnalysisControllerProvider);
            unawaited(_copy(xiangqiLineExport(state.positions.first, state.moves)));
          },
        ),
      ],
    );
  }

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) showSnackBar(context, context.l10n.success);
    } on Object catch (error) {
      if (mounted) showSnackBar(context, error.toString(), type: SnackBarType.error);
    }
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
                  line.evaluation.evalString ?? '',
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
