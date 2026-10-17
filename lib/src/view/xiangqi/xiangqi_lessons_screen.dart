import 'package:chessground/chessground.dart' show DragTargetKind;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_locale.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

/// xiangqi.com's courses, as a list of topics grouped by level.
///
/// ## What this app does with a lesson, and what it does not
///
/// It lists them, it shows a lesson's chapters, and it shows a chapter's position and the moves it
/// wants played. It does **not** play them: a chapter is a position and a script, the script is not
/// a legal game — a chapter with two red moves in a row was measured on 2026-10-16 — and what the
/// shipped client does with the opponent's turns between them is not pinned. A player that guessed
/// would be a player that taught the wrong thing.
///
/// The other half of the reason is the position itself: a chapter's `initial_fen` is written in
/// xiangqi.com's own spelling, whose general is a `j` that is not in the site's own piece set. It is
/// read here as the black general because that is what the positions are missing, and the model
/// says outright that this is an inference. See `xiangqi-com-re/docs/lesson.md`.
class const XiangqiLessonsScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiLessonsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = xiangqiLocaleOf(Localizations.localeOf(context));
    final topics = ref.watch(xiangqiTopicsProvider(locale));

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText(
          '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiLessons}',
        ),
      ),
      body: topics.when(
        data: (topics) => RefreshIndicator.adaptive(
          onRefresh: () => ref.refresh(xiangqiTopicsProvider(locale).future),
          child: ListView(
            children: [
              for (final level in _levelsOf(topics))
                ListSection(
                  hasLeading: true,
                  header: Text(level.title),
                  children: [for (final topic in level.topics) _TopicRow(topic: topic)],
                ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: Styles.bodySectionPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
                const SizedBox(height: 16.0),
                FilledButton(
                  onPressed: () => ref.invalidate(xiangqiTopicsProvider(locale)),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One level and the topics in it.
typedef _Level = ({String title, IList<XiangqiTopic> topics});

/// The topics grouped by the level they belong to, in the order the server lists both.
///
/// A topic with no level is grouped under an empty title rather than dropped: the level is a heading
/// and nothing more, and a topic this app cannot file is still a topic it can show.
List<_Level> _levelsOf(IList<XiangqiTopic> topics) {
  final levels = <String, List<XiangqiTopic>>{};
  for (final topic in topics) {
    levels.putIfAbsent(topic.levelTitle ?? '', () => []).add(topic);
  }
  return [for (final entry in levels.entries) (title: entry.key, topics: entry.value.lock)];
}

/// One topic: what it is, and how far through it the account is.
class const _TopicRow({required final XiangqiTopic topic}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(topic.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (topic.description != null) topic.description!,
          context.l10n.mobileXiangqiLessonsProgress(
            '${topic.completeLessons}',
            '${topic.totalLessons}',
          ),
        ].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: topic.isComplete
          ? Icon(Icons.check_circle, color: context.lichessColors.good)
          : Theme.of(context).platform == TargetPlatform.iOS
          ? const CupertinoListTileChevron()
          : null,
      onTap: () =>
          Navigator.of(context, rootNavigator: true).push(XiangqiTopicScreen.buildRoute(topic.id)),
    );
  }
}

/// One topic's lessons.
class const XiangqiTopicScreen({required final String topicId, super.key}) extends ConsumerWidget {
  static Route<void> buildRoute(String topicId) =>
      buildScreenRoute(screen: XiangqiTopicScreen(topicId: topicId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = xiangqiLocaleOf(Localizations.localeOf(context));
    final detail = ref.watch(xiangqiTopicProvider((topicId, locale)));

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText(detail.value?.topic.title ?? context.l10n.mobileXiangqiLessons),
      ),
      body: detail.when(
        data: (detail) => ListView(
          children: [
            if (detail.topic.description != null)
              Padding(
                padding: Styles.bodySectionPadding,
                child: Text(
                  detail.topic.description!,
                  style: TextTheme.of(context).bodyMedium?.copyWith(color: textShade(context, 0.7)),
                ),
              ),
            ListSection(
              hasLeading: true,
              children: [for (final lesson in detail.lessons) _LessonRow(lesson: lesson)],
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: Styles.bodySectionPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
                const SizedBox(height: 16.0),
                FilledButton(
                  onPressed: () => ref.invalidate(xiangqiTopicProvider((topicId, locale))),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One lesson: what it teaches, and how many of its chapters are done.
class const _LessonRow({required final XiangqiLesson lesson}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 24,
        child: Text(
          '${lesson.order}',
          textAlign: TextAlign.end,
          style: TextStyle(color: textShade(context, 0.6)),
        ),
      ),
      title: Text(lesson.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (lesson.description != null) lesson.description!,
          context.l10n.mobileXiangqiLessonsProgress(
            '${lesson.completeChapters}',
            '${lesson.totalChapters}',
          ),
        ].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: lesson.isComplete
          ? Icon(Icons.check_circle, color: context.lichessColors.good)
          : null,
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiLessonScreen.buildRoute(lesson.id, lesson.title)),
    );
  }
}

/// One lesson's chapters.
class const XiangqiLessonScreen({
  required final String lessonId,
  required final String lessonTitle,
  super.key,
}) extends ConsumerWidget {
  static Route<void> buildRoute(String lessonId, String lessonTitle) => buildScreenRoute(
    screen: XiangqiLessonScreen(lessonId: lessonId, lessonTitle: lessonTitle),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The chapters come back with their descriptions already in the reader's language, which is
    // what the `locale` parameter is for.
    final locale = xiangqiLocaleOf(Localizations.localeOf(context));
    final chapters = ref.watch(xiangqiChaptersProvider((lessonId, locale)));

    return Scaffold(
      appBar: AppBar(title: AppBarTitleText(lessonTitle)),
      body: chapters.when(
        data: (chapters) => chapters.isEmpty
            ? Center(
                child: Padding(
                  padding: Styles.bodySectionPadding,
                  child: Text(context.l10n.mobileXiangqiLessonNoChapters),
                ),
              )
            : ListView(
                children: [
                  ListSection(
                    hasLeading: true,
                    header: Text(context.l10n.mobileXiangqiLessonChapters),
                    children: [
                      for (final chapter in chapters)
                        _ChapterRow(chapter: chapter, lessonTitle: lessonTitle),
                    ],
                  ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: Styles.bodySectionPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
                const SizedBox(height: 16.0),
                FilledButton(
                  onPressed: () => ref.invalidate(xiangqiChaptersProvider((lessonId, locale))),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One chapter of a lesson.
class const _ChapterRow({required final XiangqiChapter chapter, required final String lessonTitle})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // A chapter whose position this app cannot read is a row that says so rather than one that
    // opens onto a board that is not the lesson's.
    final playable = chapter.position != null;
    return ListTile(
      leading: SizedBox(
        width: 24,
        child: Text(
          '${chapter.order}',
          textAlign: TextAlign.end,
          style: TextStyle(color: textShade(context, 0.6)),
        ),
      ),
      title: Text(chapter.description ?? lessonTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: playable ? null : Text(context.l10n.mobileXiangqiLessonNotPlayable),
      trailing: chapter.isCompleted
          ? Icon(Icons.check_circle, color: context.lichessColors.good)
          : null,
      onTap: playable
          ? () => Navigator.of(
              context,
              rootNavigator: true,
            ).push(XiangqiChapterScreen.buildRoute(chapter, lessonTitle))
          : null,
    );
  }
}

/// One chapter: the position it starts from, and the line it wants played.
class const XiangqiChapterScreen({
  required final XiangqiChapter chapter,
  required final String lessonTitle,
  super.key,
}) extends ConsumerWidget {
  static Route<void> buildRoute(XiangqiChapter chapter, String lessonTitle) => buildScreenRoute(
    screen: XiangqiChapterScreen(chapter: chapter, lessonTitle: lessonTitle),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final position = chapter.position!;
    final moves = chapter.moves;
    // The line is written from the positions it is played on, which is what the notation needs. A
    // move that does not fit the position before it ends the line there rather than throwing: a
    // chapter whose script is not a game is exactly what this app has no player for.
    final positions = <XiangqiPosition>[position];
    final played = <XiangqiMove>[];
    for (final move in moves) {
      final next = _playSafely(positions.last, move);
      if (next == null) break;
      positions.add(next);
      played.add(move);
    }
    final notation = played.isEmpty
        ? const IListConst<String>([])
        : xiangqiGameNotation(positions.lock, played.lock);

    return Scaffold(
      appBar: AppBar(title: AppBarTitleText(lessonTitle)),
      body: SafeArea(
        child: Column(
          children: [
            if (chapter.description != null)
              Padding(padding: Styles.bodySectionPadding, child: Text(chapter.description!)),
            Expanded(
              child: Center(
                child: Padding(
                  padding: Styles.horizontalBodyPadding,
                  child: AspectRatio(
                    aspectRatio: boardPrefs.coordinates ? 10 / 11 : 9 / 10,
                    child: XiangqiBoard(
                      position: position,
                      orientation: _sideToMove(position),
                      selected: null,
                      moves: const IListConst([]),
                      onTapSquare: null,
                      onDragMove: null,
                      lastMove: null,
                      animationDuration: Duration.zero,
                      showCoordinates: boardPrefs.coordinates,
                      showLastMove: false,
                      showBorder: boardPrefs.showBorder,
                      magnifyDraggedPiece: false,
                      dragTargetKind: DragTargetKind.circle,
                      style: XiangqiBoardStyle.fromChessboardColorScheme(
                        boardPrefs.boardTheme.colors,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: Styles.bodySectionPadding,
              child: Text(
                notation.isEmpty
                    ? context.l10n.mobileXiangqiLessonScriptEmpty
                    : '${context.l10n.mobileXiangqiLessonScript}: ${notation.join('  ')}',
                style: TextTheme.of(context).bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The side the board is drawn from: whoever is to move.
XiangqiSide _sideToMove(XiangqiPosition position) => position.turn;

/// [move] played on [position], or null when it does not fit.
XiangqiPosition? _playSafely(XiangqiPosition position, XiangqiMove move) {
  try {
    return rules.play(position, move);
  } catch (_) {
    return null;
  }
}
