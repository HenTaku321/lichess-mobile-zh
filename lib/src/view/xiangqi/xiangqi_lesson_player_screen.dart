import 'dart:async';

import 'package:chessground/chessground.dart' show BrightnessHueFilter;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_locale.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:material_ui/material_ui.dart';

/// How long a chapter that asks for it waits before moving on to the next one.
///
/// Two seconds, which is the site's own pause: long enough to read "Great job!", short enough that a
/// reader working through a lesson is not made to tap for every chapter.
const Duration kXiangqiLessonAutoTransitionDelay = Duration(seconds: 2);

/// One chapter of a lesson, played.
///
/// The chapter is the whole of what there is to do here: the script, the position it starts from,
/// and the reader's moves against it. [XiangqiChapterController] owns all of that — this screen
/// draws it, and hands the reader's taps to it.
///
/// The chapters come in as a list so that the bar at the bottom can walk it: a lesson is a sequence,
/// and finishing one chapter is the moment the reader is most likely to want the next one. The
/// screen keeps its place in that list, and nothing else about it.
class const XiangqiLessonPlayerScreen({
  /// The lesson the chapters belong to, which is what the list behind this screen is asked for
  /// again when a chapter is finished, so that its tick appears without leaving the lesson.
  required final String lessonId,
  required final String lessonTitle,
  required final IList<XiangqiChapter> chapters,
  required final int initialIndex,
  super.key,
}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute({
    required String lessonId,
    required String lessonTitle,
    required IList<XiangqiChapter> chapters,
    required int initialIndex,
  }) => buildScreenRoute(
    screen: XiangqiLessonPlayerScreen(
      lessonId: lessonId,
      lessonTitle: lessonTitle,
      chapters: chapters,
      initialIndex: initialIndex,
    ),
  );

  @override
  ConsumerState<XiangqiLessonPlayerScreen> createState() => _XiangqiLessonPlayerScreenState();
}

class _XiangqiLessonPlayerScreenState() extends ConsumerState<XiangqiLessonPlayerScreen> {
  late int _index = widget.initialIndex;

  /// The timer that carries a solved chapter on to the next one, when the chapter asks for it.
  Timer? _transition;

  XiangqiChapter get _chapter => widget.chapters[_index];

  @override
  void dispose() {
    _transition?.cancel();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.chapters.length || index == _index) return;
    _transition?.cancel();
    setState(() => _index = index);
  }

  /// What happens when a chapter is finished: the list behind this screen is told, and the next
  /// chapter is opened if the chapter asked for that.
  ///
  /// The chapters are read again rather than patched in place: the tick on the chapter just played
  /// is the server's answer — it is the server that counts a lesson's progress — and a screen that
  /// drew its own tick would be guessing at a number it can ask for.
  void _onSolved(XiangqiChapter chapter) {
    final locale = xiangqiLocaleOf(Localizations.localeOf(context));
    ref.invalidate(xiangqiChaptersProvider((widget.lessonId, locale)));
    if (!chapter.autoTransition || _index + 1 >= widget.chapters.length) return;
    _transition?.cancel();
    _transition = Timer(kXiangqiLessonAutoTransitionDelay, () {
      if (!mounted) return;
      _goTo(_index + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapter;
    final state = ref.watch(xiangqiChapterControllerProvider(chapter));
    final controller = ref.read(xiangqiChapterControllerProvider(chapter).notifier);

    ref.listen(xiangqiChapterControllerProvider(chapter), (previous, next) {
      if (next.isSolved && previous?.isSolved != true) _onSolved(chapter);
    });

    final boardPrefs = ref.watch(boardPreferencesProvider);
    final style = XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors);
    // The board faces whoever the chapter starts with, and keeps facing them for the whole
    // chapter: a board that turned around when the other side moved would be a board the reader has
    // to re-read after every move.
    final start = chapter.position ?? XiangqiPosition.initial();
    final orientation = chapter.flipBoard ? start.turn.opposite : start.turn;

    final hint = state.hint;
    final arrows = IList<XiangqiBoardArrow>([
      if (hint != null) XiangqiBoardArrow(move: hint),
      for (final arrow in state.arrows)
        XiangqiBoardArrow(
          move: XiangqiMove(arrow.from, arrow.to),
          color: _arrowColorOf(arrow.color),
        ),
    ]);

    // The line as far as it has been played, which is what the move list shows. The wrong move is
    // deliberately not in it: it is not part of the line, and it is about to come off the board.
    final playedMoves = <XiangqiMove>[
      for (var step = 1; step <= state.cursor; step++) ?chapter.steps[step].move,
    ];
    final playedPositions = <XiangqiPosition>[
      for (var step = 0; step <= state.cursor; step++) state.positions[step],
    ];
    final notation = playedMoves.isEmpty
        ? const IListConst<String>([])
        : xiangqiGameNotation(playedPositions.lock, playedMoves.lock);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText(widget.lessonTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(
              context.l10n.mobileXiangqiLessonChapterProgress(
                '${chapter.order}',
                '${widget.chapters.length}',
              ),
              style: TextTheme.of(context).bodySmall,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: XiangqiGameLayout(
          board: BrightnessHueFilter(
            brightness: boardPrefs.brightness,
            hue: boardPrefs.hue,
            child: XiangqiBoard(
              position: state.position,
              orientation: orientation,
              selected: state.selected,
              moves: boardPrefs.showLegalMoves ? state.selectedMoves : const IListConst([]),
              lastMove: boardPrefs.boardHighlights ? _lastMoveOf(chapter, state.cursor) : null,
              wrongMove: state.wrongMove,
              marked: state.intersections,
              onTapSquare: controller.tapSquare,
              // A drag is the same two taps it would have been, in the order they were made — the
              // same reading the game screens give it, so a piece is picked up and put down the one
              // way here and there.
              onDragMove: (from, to) {
                controller.tapSquare(from);
                controller.tapSquare(to);
              },
              animationDuration: boardPrefs.pieceAnimationDuration,
              showCoordinates: boardPrefs.coordinates,
              showLastMove: boardPrefs.boardHighlights,
              showBorder: boardPrefs.showBorder,
              hint: hint,
              arrows: arrows,
              magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
              dragTargetKind: boardPrefs.dragTargetKind,
              style: style,
            ),
          ),
          topTable: _ChapterTable(
            description: chapter.description,
            status: state.isSolved
                ? context.l10n.mobileXiangqiLessonGreatJob
                : state.isVerifying
                ? context.l10n.mobileXiangqiLessonThinking
                : state.wrongMove != null
                ? context.l10n.mobileXiangqiLessonWrongMove
                : state.expectedMove == null
                ? context.l10n.mobileXiangqiLessonScriptEmpty
                : null,
            statusColor: state.isSolved
                ? context.lichessColors.good
                : state.wrongMove != null
                ? context.lichessColors.error
                : null,
            busy: state.isVerifying,
          ),
          bottomTable: _ChapterTable(
            description: null,
            status: state.isSolved && !chapter.autoTransition
                ? context.l10n.mobileXiangqiLessonNextChapter
                : null,
            statusColor: null,
            busy: false,
          ),
          moves: notation,
          currentMoveIndex: notation.length,
          moveListVisible: notation.isNotEmpty,
          userActionsBar: BottomBar(
            children: [
              BottomBarButton(
                label: context.l10n.mobileXiangqiLessonHint,
                onTap: state.isPlayable && state.expectedMove != null ? controller.showHint : null,
                icon: CupertinoIcons.lightbulb,
                highlighted: state.hint != null,
              ),
              BottomBarButton(
                label: context.l10n.mobileXiangqiLessonUndo,
                onTap: state.cursor > 0 && !state.isVerifying ? controller.undo : null,
                icon: CupertinoIcons.arrow_uturn_left,
              ),
              BottomBarButton(
                label: context.l10n.mobileXiangqiLessonPreviousChapter,
                onTap: _index > 0 ? () => _goTo(_index - 1) : null,
                icon: CupertinoIcons.chevron_left,
              ),
              BottomBarButton(
                label: context.l10n.mobileXiangqiLessonNextChapter,
                onTap: _index + 1 < widget.chapters.length ? () => _goTo(_index + 1) : null,
                icon: CupertinoIcons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The move that led to the position the chapter is showing, or null at the start of it.
XiangqiMove? _lastMoveOf(XiangqiChapter chapter, int cursor) =>
    cursor > 0 && cursor < chapter.steps.length ? chapter.steps[cursor].move : null;

/// The colour an arrow asks for, read out of the `#RRGGBB` the chapter writes it as.
///
/// Null for anything else, which is the board's own hint colour: an arrow whose colour this app
/// cannot read is still an arrow, and dropping it would lose the chapter's own pointing.
Color? _arrowColorOf(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// The one line of text above the board and the one below it: what the chapter is teaching, and
/// what it has to say about the move just played.
class const _ChapterTable({
  required final String? description,
  required final String? status,
  required final Color? statusColor,
  required final bool busy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (description == null && status == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (description != null) Text(description!, style: TextTheme.of(context).bodyMedium),
        if (status != null)
          Padding(
            padding: EdgeInsets.only(top: description != null ? 6.0 : 0.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  const SizedBox.square(
                    dimension: 14.0,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2.0),
                  ),
                  const SizedBox(width: 8.0),
                ],
                Flexible(
                  child: Text(
                    status!,
                    style: TextTheme.of(context).bodyMedium
                        ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
