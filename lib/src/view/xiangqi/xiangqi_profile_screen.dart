import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart'
    show
        kXiangqiComEndCheckmate,
        kXiangqiComEndDraw,
        kXiangqiComEndDrawNoCapture,
        kXiangqiComEndDrawNoThreatPattern,
        kXiangqiComEndResign,
        kXiangqiComEndStalemate,
        kXiangqiComEndTimerExpired;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_user_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_review_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:material_ui/material_ui.dart';

/// A xiangqi.com account, as this app shows it.
///
/// ## What is here, and what is not
///
/// The header, the four ratings, one record per speed and the first page of the account's games.
/// What is **not** here is the rating history the stats endpoints carry: they send it, and drawing
/// it is a chart this wave did not take on — see `xiangqi-com-re/docs/profile.md`, where the shape
/// is written down for whoever does.
///
/// ## Where the numbers come from
///
/// Four endpoints, and each answers a different question: the account for the name and the four
/// ratings, `multiplayer_stats` for one speed's record, `puzzle_stats` for the puzzle record, and
/// `users/games` for the games. They are four providers rather than one so that a slow one does not
/// hold the others back — a screen that showed nothing until the last of them arrived would be a
/// screen that showed nothing for as long as the slowest took.
class const XiangqiProfileScreen({required final String username, super.key})
    extends ConsumerWidget {
  static Route<void> buildRoute(String username) =>
      buildScreenRoute(screen: XiangqiProfileScreen(username: username));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(xiangqiUserProvider(username));

    // Signing out is offered only on the account's own profile: it is an action on the session this
    // device holds, and a profile of somebody else has nothing to sign out of.
    final isMe = ref.watch(xiangqiAuthControllerProvider)?.name == username;

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText(username),
        actions: [
          if (isMe)
            IconButton(
              tooltip: context.l10n.logOut,
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(xiangqiAuthControllerProvider.notifier).signOut(),
            ),
        ],
      ),
      body: profile.when(
        data: (profile) => ListView(
          children: [
            _Header(profile: profile),
            _Ratings(profile: profile),
            for (final speed in XiangqiRatingType.values)
              _SpeedRecord(username: username, speed: speed),
            _RecentGames(username: username),
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
                  onPressed: () => ref.invalidate(xiangqiUserProvider(username)),
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

/// Who the account is: its piece, its name, and what the server says about it.
class const _Header({required final XiangqiUserProfile profile}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (profile.countryName != null) profile.countryName!,
      if (profile.memberSince != null) '${context.l10n.memberSince} ${_date(profile.memberSince!)}',
    ];
    return Padding(
      padding: Styles.bodySectionPadding,
      child: Row(
        children: [
          // The red general, because a xiangqi account has no avatar of its own here and a piece
          // is what this app draws a xiangqi identity with — the same one the account menu uses.
          const XiangqiPieceAvatar(side: XiangqiSide.red, size: 56),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.username, style: TextTheme.of(context).titleLarge),
                if (parts.isNotEmpty)
                  Text(
                    parts.join(' · '),
                    style: TextTheme.of(context).bodyMedium
                        ?.copyWith(color: textShade(context, 0.7)),
                  ),
                if (profile.isOnline)
                  Text(
                    context.l10n.online,
                    style: TextTheme.of(context).bodySmall
                        ?.copyWith(color: context.lichessColors.good),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The four ratings, as one section.
class const _Ratings({required final XiangqiUserProfile profile}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ratings = XiangqiRatings(
      bullet: profile.bulletRating,
      rapid: profile.rapidRating,
      daily: profile.dailyRating,
      puzzle: profile.puzzleRating,
    );
    return ListSection(
      hasLeading: true,
      children: [
        for (final speed in XiangqiRatingType.values)
          ListTile(
            leading: Icon(_speedIcon(speed)),
            title: Text(_speedLabel(context, speed)),
            trailing: Text(
              ratings.of(speed)?.toString() ?? '—',
              style: TextTheme.of(context).titleMedium
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
      ],
    );
  }
}

/// One speed's record, as a section of its own.
///
/// The puzzle record is read from a different endpoint with a different shape, so the two are two
/// widgets rather than one with a branch: what they share is the section and the heading, and what
/// they do not share is everything they say.
class const _SpeedRecord({required final String username, required final XiangqiRatingType speed})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = speed.isGame
        ? ref
              .watch(xiangqiGameStatsProvider((username, speed)))
              .whenData((stats) => _gameLines(context, stats))
        : ref
              .watch(xiangqiPuzzleStatsProvider(username))
              .whenData((stats) => _puzzleLines(context, stats));

    return ListSection(
      hasLeading: true,
      header: Text(_speedLabel(context, speed)),
      children: [
        for (final line in record.value ?? const <String>[])
          ListTile(dense: true, title: Text(line)),
        if (record.isLoading) const ListTile(dense: true, title: Text('…')),
      ],
    );
  }

  /// The lines a game record is written as.
  List<String> _gameLines(BuildContext context, XiangqiGameStats stats) => [
    context.l10n.nbWins(stats.wins),
    context.l10n.nbLosses(stats.losses),
    context.l10n.nbDraws(stats.draws),
    '${context.l10n.winRate} ${stats.winRate.round()}%',
    '${context.l10n.gamesPlayed} ${stats.totalGames}',
    if (stats.highestRating != null)
      '${context.l10n.mobileXiangqiHighestRating} ${stats.highestRating}',
  ];

  /// The lines a puzzle record is written as.
  List<String> _puzzleLines(BuildContext context, XiangqiPuzzleStats stats) => [
    context.l10n.mobileXiangqiPuzzlesAttempted('${stats.attempted}'),
    context.l10n.mobileXiangqiPuzzlesSuccessRate('${stats.successRate.round()}%'),
    if (stats.highestRating != null)
      '${context.l10n.mobileXiangqiHighestRating} ${stats.highestRating}',
  ];
}

/// The first page of the account's games.
///
/// The first page and no more: the endpoint paginates and this screen does not, because a list that
/// only ever grew would be a list nobody could get to the end of. A game that is over opens its
/// review; one still being played is a row with no way in, since watching it is the watch list's
/// business and not a profile's.
class const _RecentGames({required final String username}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(xiangqiGameHistoryProvider((username, 1)));
    return history.when(
      data: (history) => ListSection(
        hasLeading: true,
        header: Text(context.l10n.games),
        children: [
          if (history.games.isEmpty)
            ListTile(dense: true, title: Text(context.l10n.mobileXiangqiNoGames))
          else
            for (final game in history.games) _GameRow(game: game),
        ],
      ),
      loading: () => ListSection.loading(itemsNumber: 3, header: true, hasLeading: true),
      // A history that did not arrive is not a reason to fail the whole screen: everything above it
      // is already drawn, and this is the last section of it.
      error: (error, stackTrace) => ListSection(
        hasLeading: true,
        header: Text(context.l10n.games),
        children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
      ),
    );
  }
}

/// One finished game: who played it, and how it went.
class const _GameRow({required final XiangqiGameSummary game}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final red = game.red?.name ?? context.l10n.mobileXiangqiSideRed;
    final black = game.black?.name ?? context.l10n.mobileXiangqiSideBlack;
    final winner = game.winner;
    return ListTile(
      dense: true,
      title: Text('$red — $black', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (winner != null) winner.label(context.l10n),
          if (game.endReason != null) _endReasonLabel(context, game.endReason!),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: game.isFinished ? const Icon(Icons.chevron_right, size: 18) : null,
      onTap: game.isFinished
          ? () => Navigator.of(
              context,
              rootNavigator: true,
            ).push(XiangqiReviewScreen.buildRoute(game.id))
          : null,
    );
  }
}

/// The name of [reason], in the reader's own language.
///
/// The same sentences the online game screen ends a game with, read from the same codes — the
/// server's own `end_reason`, which the socket's end frames carry too. A code this app has no
/// sentence for is left out rather than guessed at.
String _endReasonLabel(BuildContext context, int reason) => switch (reason) {
  kXiangqiComEndCheckmate => context.l10n.mobileXiangqiCheckmated(''),
  kXiangqiComEndStalemate => context.l10n.mobileXiangqiStalemateLoss(''),
  kXiangqiComEndTimerExpired => context.l10n.mobileXiangqiRanOutOfTime(''),
  kXiangqiComEndResign => context.l10n.mobileXiangqiResigned(''),
  kXiangqiComEndDraw ||
  kXiangqiComEndDrawNoCapture ||
  kXiangqiComEndDrawNoThreatPattern => context.l10n.mobileXiangqiThreefoldRepetition,
  _ => '',
};

/// The icon a speed is drawn with.
IconData _speedIcon(XiangqiRatingType speed) => switch (speed) {
  .rapid => Icons.timer_outlined,
  .bullet => Icons.bolt_outlined,
  .daily => Icons.calendar_today_outlined,
  .puzzle => Icons.extension_outlined,
};

/// The name of [speed], in the reader's own language.
String _speedLabel(BuildContext context, XiangqiRatingType speed) => switch (speed) {
  .rapid => context.l10n.mobileXiangqiSpeedRapid,
  .bullet => context.l10n.mobileXiangqiSpeedBullet,
  .daily => context.l10n.mobileXiangqiSpeedDaily,
  .puzzle => context.l10n.mobileXiangqiSpeedPuzzle,
};

/// [instant] as a date, without a time.
String _date(DateTime instant) =>
    '${instant.year}-${instant.month.toString().padLeft(2, '0')}-'
    '${instant.day.toString().padLeft(2, '0')}';
