import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/tournament/tournament.dart';
import 'package:lichess_mobile/src/model/tournament/tournament_providers.dart';
import 'package:lichess_mobile/src/model/xiangqi/tournament/xiangqi_tournament.dart';
import 'package:lichess_mobile/src/model/xiangqi/tournament/xiangqi_tournament_repository.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/tournament/tournament_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_tournaments_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/source_preview_block.dart';
import 'package:material_ui/material_ui.dart';

/// Tournaments from both servers, on one page.
///
/// Lichess and xiangqi.com are two tournaments calendars rather than two answers to a question the
/// reader has to give before the screen can be drawn. Both are shown, each with its own loading and
/// error state, and each can be expanded without leaving the page.
class const TournamentsHubScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const TournamentsHubScreen());

  @override
  ConsumerState<TournamentsHubScreen> createState() => _TournamentsHubScreenState();
}

class _TournamentsHubScreenState() extends ConsumerState<TournamentsHubScreen> {
  bool _lichessExpanded = false;
  bool _xiangqiExpanded = false;

  @override
  Widget build(BuildContext context) {
    final lichess = ref.watch(tournamentsProvider);
    final xiangqi = ref.watch(xiangqiTournamentsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.arenaArenaTournaments)),
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(tournamentsProvider.future),
            ref.refresh(xiangqiTournamentsProvider.future),
          ]);
        },
        child: ListView(
          children: [
            SourcePreviewBlock(
              leading: const Icon(Icons.emoji_events_outlined),
              title: const Text('Lichess'),
              expandedState: _lichessExpanded,
              onToggle: () => setState(() => _lichessExpanded = !_lichessExpanded),
              summary: _Summary(
                value: lichess.value == null ? null : _lichessCount(lichess.value!),
              ),
              preview: _LichessTournaments(state: lichess, expanded: false),
              expanded: _LichessTournaments(state: lichess, expanded: true),
            ),
            const Divider(height: 1),
            SourcePreviewBlock(
              leading: const Icon(Icons.grid_on),
              title: const Text('Xiangqi.com'),
              expandedState: _xiangqiExpanded,
              onToggle: () => setState(() => _xiangqiExpanded = !_xiangqiExpanded),
              summary: _Summary(
                value: xiangqi.value == null ? null : _xiangqiCount(xiangqi.value!),
              ),
              preview: _XiangqiTournaments(state: xiangqi, expanded: false),
              expanded: _XiangqiTournaments(state: xiangqi, expanded: true),
            ),
            const SizedBox(height: 24.0),
          ],
        ),
      ),
    );
  }

  int _lichessCount(TournamentLists lists) =>
      lists.started.length + lists.created.length + lists.finished.length;

  int _xiangqiCount(XiangqiTournaments lists) => lists.active.length + lists.previous.length;
}

class const _Summary({required final int? value}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => value == null ? const SizedBox.shrink() : Text('$value');
}

class const _LichessTournaments({
  required final AsyncValue<TournamentLists> state,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (lists) {
        final rows = expanded
            ? [...lists.started, ...lists.created, ...lists.finished]
            : [...lists.started.take(3), ...lists.created.take(2)];
        if (rows.isEmpty) {
          return ListSection(
            children: [
              ListTile(dense: true, title: Text(context.l10n.mobileXiangqiTournamentsEmpty)),
            ],
          );
        }
        return ListSection(
          hasLeading: true,
          children: [for (final tournament in rows) _LichessTournamentRow(tournament: tournament)],
        );
      },
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator.adaptive()),
      ),
      error: (error, stackTrace) => ListSection(
        children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
      ),
    );
  }
}

class const _LichessTournamentRow({required final LightTournament tournament})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final starts = tournament.startsAt.toLocal();
    return ListTile(
      dense: true,
      title: Text(tournament.meta.fullName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${tournament.meta.variant.label(context.l10n)} · ${tournament.nbPlayers} players · '
        '${starts.month}/${starts.day} ${starts.hour.toString().padLeft(2, '0')}:'
        '${starts.minute.toString().padLeft(2, '0')}',
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(TournamentScreen.buildRoute(tournament.id)),
    );
  }
}

class const _XiangqiTournaments({
  required final AsyncValue<XiangqiTournaments> state,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (lists) {
        final rows = expanded
            ? [...lists.active, ...lists.previous]
            : [...lists.active.take(3), ...lists.previous.take(2)];
        if (rows.isEmpty) {
          return ListSection(
            children: [
              ListTile(dense: true, title: Text(context.l10n.mobileXiangqiTournamentsEmpty)),
            ],
          );
        }
        return ListSection(
          hasLeading: true,
          children: [for (final tournament in rows) _XiangqiTournamentRow(tournament: tournament)],
        );
      },
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator.adaptive()),
      ),
      error: (error, stackTrace) => ListSection(
        children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
      ),
    );
  }
}

class const _XiangqiTournamentRow({required final XiangqiTournament tournament})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final starts = tournament.startsAt?.toLocal();
    final when = starts == null
        ? ''
        : ' · ${starts.month}/${starts.day} '
              '${starts.hour.toString().padLeft(2, '0')}:${starts.minute.toString().padLeft(2, '0')}';
    return ListTile(
      dense: true,
      title: Text(tournament.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${context.l10n.nbPlayers(tournament.participants)} · ${tournament.ongoingGames} · $when',
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiTournamentScreen.buildRoute(tournament.id, tournament.name)),
    );
  }
}
