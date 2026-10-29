import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/tournament/xiangqi_tournament.dart';
import 'package:lichess_mobile/src/model/xiangqi/tournament/xiangqi_tournament_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_country_names.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

/// xiangqi.com's tournaments, split the way the server splits them.
///
/// ## What this app does with one, and what it does not
///
/// It lists them and it shows a tournament's standings. It does **not** offer to sign up or to take
/// a seat: `PUT tournament/<id>/register` and `PUT tournament/<id>/join` were read off the shipped
/// client and never sent, because joining a tournament is a commitment to be at a board at a
/// particular time and this project has no reason to make one. What `register` and `join` take, and
/// what they answer, is therefore not pinned — see `xiangqi-com-re/docs/tournament.md` — and a
/// button built on a guess would be a button that might do nothing.
///
/// ## The three lists a tournament page is made of
///
/// Standings, pairings and games in progress are **REST**, not socket frames: the shipped client's
/// own sagas fetch them with the same call every other read uses. Only `tournament.join` and
/// `tournament.left` are socket events, and those are the lobby's, not the list's.
class const XiangqiTournamentsScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiTournamentsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(xiangqiTournamentsProvider);

    final identity = ref.watch(xiangqiAccountGenerationProvider);
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(xiangqiTournamentsProvider.future),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: tournaments,
        builder: (context, tournaments) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(
              '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiTournaments}',
            ),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          ),
          body: tournaments.when(
            data: (tournaments) => RefreshIndicator.adaptive(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _Section(
                    title: context.l10n.mobileXiangqiTournamentsActive,
                    tournaments: tournaments.active,
                  ),
                  _Section(
                    title: context.l10n.mobileXiangqiTournamentsPrevious,
                    tournaments: tournaments.previous,
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

/// One of the two lists.
class const _Section({
  required final String title,
  required final IList<XiangqiTournament> tournaments,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListSection(
      hasLeading: true,
      header: Text(title),
      children: [
        if (tournaments.isEmpty)
          ListTile(dense: true, title: Text(context.l10n.mobileXiangqiTournamentsEmpty))
        else
          for (final tournament in tournaments) _TournamentRow(tournament: tournament),
      ],
    );
  }
}

/// One tournament: its name, when it starts, and how big it is.
class const _TournamentRow({required final XiangqiTournament tournament}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        tournament.isFinished ? Icons.emoji_events_outlined : Icons.emoji_events,
        color: tournament.isFinished ? textShade(context, 0.5) : context.lichessColors.brag,
      ),
      title: Text(tournament.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (tournament.startsAt != null)
            context.l10n.mobileXiangqiTournamentsStartsAt(_date(tournament.startsAt!)),
          context.l10n.mobileXiangqiTournamentsRounds('${tournament.rounds}'),
          context.l10n.mobileXiangqiTournamentsParticipants('${tournament.participants}'),
          _timeControl(tournament),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiTournamentScreen.buildRoute(tournament.id, tournament.name)),
    );
  }
}

/// One tournament: what it is, and who is in it.
class const XiangqiTournamentScreen({
  required final String id,
  required final String name,
  super.key,
}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute(String id, String name) => buildScreenRoute(
    screen: XiangqiTournamentScreen(id: id, name: name),
  );

  @override
  ConsumerState<XiangqiTournamentScreen> createState() => _XiangqiTournamentScreenState();
}

class _XiangqiTournamentScreenState() extends ConsumerState<XiangqiTournamentScreen> {
  @override
  Widget build(BuildContext context) {
    final tournament = ref.watch(xiangqiTournamentProvider(widget.id));
    // The first page of the standings and no more: a tournament's table is long, and a list that
    // only ever grew would be a list nobody could get to the end of. The page is not a setting —
    // there is nowhere on this screen to change it — so it is not state.
    final leaders = ref.watch(xiangqiTournamentLeadersProvider((widget.id, 1)));
    final participants = ref.watch(xiangqiTournamentParticipantsProvider(widget.id));

    final identity = (widget.id, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => Future.wait<Object?>([
        ref.refresh(xiangqiTournamentProvider(widget.id).future),
        ref.refresh(xiangqiTournamentLeadersProvider((widget.id, 1)).future),
        ref.refresh(xiangqiTournamentParticipantsProvider(widget.id).future),
      ]),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: tournament,
        builder: (context, tournament) => XiangqiRetainedData(
          identity: identity,
          value: leaders,
          builder: (context, leaders) => XiangqiRetainedData(
            identity: identity,
            value: participants,
            builder: (context, participants) => Scaffold(
              appBar: AppBar(
                title: AppBarTitleText(widget.name),
                actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
              ),
              body: RefreshIndicator.adaptive(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (tournament.isLoading) ListSection.loading(itemsNumber: 2, hasLeading: true),
                    if (tournament.hasError)
                      ListSection(
                        hasLeading: true,
                        children: [
                          XiangqiRetryTile(
                            onRetry: busy
                                ? null
                                : () => refresh(
                                    request: () =>
                                        ref.refresh(xiangqiTournamentProvider(widget.id).future),
                                  ),
                          ),
                        ],
                      ),
                    if (tournament.value != null)
                      ListSection(
                        hasLeading: true,
                        children: [
                          ListTile(
                            dense: true,
                            title: Text(
                              [
                                if (tournament.value!.startsAt != null)
                                  context.l10n.mobileXiangqiTournamentsStartsAt(
                                    _date(tournament.value!.startsAt!),
                                  ),
                                _timeControl(tournament.value!),
                                if (tournament.value!.isRated) context.l10n.rated,
                              ].join(' · '),
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: Text(
                              context.l10n.mobileXiangqiTournamentsParticipants(
                                '${tournament.value!.participants}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    // The standings first, and the sign-ups under them: a tournament that has been played has
                    // a table worth reading, and one that has not has nothing but the list of who is coming.
                    leaders.when(
                      data: (leaders) => ListSection(
                        hasLeading: true,
                        header: Text(context.l10n.mobileXiangqiTournamentsStandings),
                        children: [
                          if (leaders.items.isEmpty)
                            ListTile(
                              dense: true,
                              title: Text(context.l10n.mobileXiangqiTournamentsStandingsEmpty),
                            )
                          else
                            for (final entry in leaders.items) _StandingRow(entry: entry),
                        ],
                      ),
                      loading: () =>
                          ListSection.loading(itemsNumber: 3, header: true, hasLeading: true),
                      error: (error, stackTrace) => ListSection(
                        hasLeading: true,
                        header: Text(context.l10n.mobileXiangqiTournamentsStandings),
                        children: [
                          ListTile(
                            dense: true,
                            title: Text(context.l10n.mobileSomethingWentWrong),
                            trailing: IconButton(
                              tooltip: context.l10n.retry,
                              icon: const Icon(Icons.refresh),
                              onPressed: busy
                                  ? null
                                  : () => refresh(
                                      request: () => ref.refresh(
                                        xiangqiTournamentLeadersProvider((widget.id, 1)).future,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (participants.isLoading)
                      ListSection.loading(itemsNumber: 2, hasLeading: true),
                    if (participants.hasError)
                      ListSection(
                        hasLeading: true,
                        children: [
                          XiangqiRetryTile(
                            onRetry: busy
                                ? null
                                : () => refresh(
                                    request: () => ref.refresh(
                                      xiangqiTournamentParticipantsProvider(widget.id).future,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    if (participants.value != null && participants.value!.isNotEmpty)
                      ListSection(
                        hasLeading: true,
                        header: Text(
                          context.l10n.mobileXiangqiTournamentsParticipants(
                            '${participants.value!.length}',
                          ),
                        ),
                        children: [
                          for (final entry in participants.value!) _StandingRow(entry: entry),
                        ],
                      ),
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

/// One account's place in a tournament.
class const _StandingRow({required final XiangqiTournamentParticipant entry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 24,
        child: Text(
          // A rank of zero is the server's way of saying nothing has been played yet, and a `0`
          // printed beside a name would read as last place.
          entry.rank == 0 ? '—' : '${entry.rank}',
          textAlign: TextAlign.end,
          style: TextStyle(color: textShade(context, 0.6)),
        ),
      ),
      title: Text(entry.player.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (entry.player.countryName != null)
            xiangqiLocalizedCountryName(
                  Localizations.localeOf(context),
                  englishName: entry.player.countryName,
                ) ??
                entry.player.countryName!,
          if (entry.gameCount > 0) '${entry.winCount}/${entry.gameCount}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.totalScore == 0 ? null : Text('${entry.totalScore}'),
    );
  }
}

/// The time control, written the way the app writes every other one.
String _timeControl(XiangqiTournament tournament) =>
    '${tournament.gameTimerSeconds ~/ 60}+${tournament.incrementSeconds}';

/// [instant] as a date and a time, in the reader's own time zone.
String _date(DateTime instant) {
  final local = instant.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} ${local.hour}:$minute';
}
