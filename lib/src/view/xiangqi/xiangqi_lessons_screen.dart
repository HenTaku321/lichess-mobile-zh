import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_locale.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lesson_player_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refreshable_empty.dart';
import 'package:material_ui/material_ui.dart';

/// xiangqi.com's courses, as a list of topics grouped by level.
///
/// ## What this app does with a lesson, and what it does not
///
/// Lists topics and chapters, then opens the script-driven lesson player. Scripts are not legal
/// games: they may ask for consecutive moves by the same side. The player follows the chapter's
/// measured turn markers rather than imposing a normal game's alternating-turn rule.
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

    final identity = (locale, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(xiangqiTopicsProvider(locale).future),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: topics,
        builder: (context, topics) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(
              '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiLessons}',
            ),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          ),
          body: topics.when(
            data: (topics) => RefreshIndicator.adaptive(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                    FilledButton(onPressed: refresh, child: Text(context.l10n.retry)),
                  ],
                ),
              ),
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

    final identity = (topicId, locale, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(xiangqiTopicProvider((topicId, locale)).future),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: detail,
        builder: (context, detail) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(detail.value?.topic.title ?? context.l10n.mobileXiangqiLessons),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          ),
          body: detail.when(
            data: (detail) => RefreshIndicator.adaptive(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (detail.topic.description != null)
                    Padding(
                      padding: Styles.bodySectionPadding,
                      child: Text(
                        detail.topic.description!,
                        style: TextTheme.of(context).bodyMedium
                            ?.copyWith(color: textShade(context, 0.7)),
                      ),
                    ),
                  ListSection(
                    hasLeading: true,
                    children: [for (final lesson in detail.lessons) _LessonRow(lesson: lesson)],
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
                    FilledButton(onPressed: refresh, child: Text(context.l10n.retry)),
                  ],
                ),
              ),
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

    final identity = (lessonId, locale, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(xiangqiChaptersProvider((lessonId, locale)).future),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: chapters,
        builder: (context, chapters) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(lessonTitle),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          ),
          body: chapters.when(
            data: (chapters) => chapters.isEmpty
                ? XiangqiRefreshableEmpty(
                    onRefresh: refresh,
                    child: Padding(
                      padding: Styles.bodySectionPadding,
                      child: Text(context.l10n.mobileXiangqiLessonNoChapters),
                    ),
                  )
                : RefreshIndicator.adaptive(
                    onRefresh: refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        ListSection(
                          hasLeading: true,
                          header: Text(context.l10n.mobileXiangqiLessonChapters),
                          children: [
                            for (final (index, chapter) in chapters.indexed)
                              _ChapterRow(
                                chapter: chapter,
                                lessonTitle: lessonTitle,
                                chapters: chapters,
                                index: index,
                                lessonId: lessonId,
                              ),
                          ],
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
                    FilledButton(onPressed: refresh, child: Text(context.l10n.retry)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One chapter of a lesson.
class const _ChapterRow({
  required final XiangqiChapter chapter,
  required final String lessonTitle,
  required final IList<XiangqiChapter> chapters,
  required final int index,
  required final String lessonId,
}) extends StatelessWidget {
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
      // The whole lesson goes to the player, not the one chapter: the bar at the bottom of it walks
      // the list, and a chapter that was opened on its own would have nowhere to walk to.
      onTap: playable
          ? () => Navigator.of(context, rootNavigator: true).push(
              XiangqiLessonPlayerScreen.buildRoute(
                lessonId: lessonId,
                lessonTitle: lessonTitle,
                chapters: chapters,
                initialIndex: index,
              ),
            )
          : null,
    );
  }
}
