import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/user/leaderboard.dart';
import 'package:lichess_mobile/src/model/user/user_repository_providers.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile_repository.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/user/leaderboard_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/source_preview_block.dart';
import 'package:material_ui/material_ui.dart';

final _xiangqiHubLeaderboardsProvider =
    FutureProvider.autoDispose<IList<(XiangqiRatingType, XiangqiLeaderboard)>>((ref) async {
      final boards = await Future.wait([
        for (final mode in XiangqiRatingType.values)
          ref
              .watch(xiangqiLeaderboardProvider((mode, null, 1)).future)
              .then((board) => (mode, board)),
      ]);
      return boards.lock;
    });

/// Leaderboards from both sites on one page.
class const LeaderboardHubScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const LeaderboardHubScreen());

  @override
  ConsumerState<LeaderboardHubScreen> createState() => _LeaderboardHubScreenState();
}

class _LeaderboardHubScreenState() extends ConsumerState<LeaderboardHubScreen> {
  bool _lichessExpanded = false;
  bool _xiangqiExpanded = false;

  @override
  Widget build(BuildContext context) {
    final lichessTop = ref.watch(top1Provider);
    final lichessAll = ref.watch(leaderboardProvider);
    final xiangqi = ref.watch(_xiangqiHubLeaderboardsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.leaderboard)),
      body: ListView(
        children: [
          SourcePreviewBlock(
            leading: const Icon(Icons.leaderboard_outlined),
            title: const Text('Lichess'),
            expandedState: _lichessExpanded,
            onToggle: () => setState(() => _lichessExpanded = !_lichessExpanded),
            preview: _LichessLeaderboard(state: lichessTop, expanded: false, all: lichessAll),
            expanded: _LichessLeaderboard(state: lichessTop, expanded: true, all: lichessAll),
          ),
          const Divider(height: 1),
          SourcePreviewBlock(
            leading: const Icon(Icons.grid_on),
            title: const Text('Xiangqi.com'),
            expandedState: _xiangqiExpanded,
            onToggle: () => setState(() => _xiangqiExpanded = !_xiangqiExpanded),
            preview: _XiangqiLeaderboards(state: xiangqi, expanded: false),
            expanded: _XiangqiLeaderboards(state: xiangqi, expanded: true),
          ),
          const SizedBox(height: 24.0),
        ],
      ),
    );
  }
}

class const _LichessLeaderboard({
  required final AsyncValue<Top1Leaderboard> state,
  required final AsyncValue<Leaderboard> all,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return state.when(
        data: (top1) {
          const previewPerfs = [Perf.bullet, Perf.blitz, Perf.rapid, Perf.classical];
          final entries = [
            for (final perf in previewPerfs)
              if (top1[perf] != null) (perf, top1[perf]!),
          ];
          if (entries.isEmpty) {
            return ListSection(
              children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
            );
          }
          return ListSection(
            hasLeading: true,
            children: [
              for (final (perf, user) in entries)
                LeaderboardListTile(user: user, perfIcon: perf.icon),
            ],
          );
        },
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator.adaptive(),
          ),
        ),
        error: (error, stackTrace) => ListSection(
          children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
        ),
      );
    }
    return all.when(
      data: (data) {
        final categories = <(Perf, List<LeaderboardUser>)>[
          (Perf.bullet, data.bullet),
          (Perf.blitz, data.blitz),
          (Perf.rapid, data.rapid),
          (Perf.classical, data.classical),
          (Perf.ultraBullet, data.ultrabullet),
          (Perf.crazyhouse, data.crazyhouse),
          (Perf.chess960, data.chess960),
          (Perf.kingOfTheHill, data.kingOfThehill),
          (Perf.threeCheck, data.threeCheck),
          (Perf.atomic, data.atomic),
          (Perf.horde, data.horde),
          (Perf.antichess, data.antichess),
          (Perf.racingKings, data.racingKings),
        ];
        return Column(
          children: [
            for (final (perf, users) in categories)
              if (users.isNotEmpty)
                ListSection(
                  hasLeading: true,
                  header: Text(perf.label(context.l10n)),
                  children: [
                    for (final user in users.take(10))
                      LeaderboardListTile(user: user, perfIcon: perf.icon),
                  ],
                ),
          ],
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

class const _XiangqiLeaderboards({
  required final AsyncValue<IList<(XiangqiRatingType, XiangqiLeaderboard)>> state,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (boards) => Column(
        children: [
          for (final (mode, board) in boards)
            if (board.entries.isNotEmpty)
              ListSection(
                hasLeading: true,
                header: Text(_modeLabel(context, mode)),
                children: [
                  for (final entry in (expanded ? board.entries : board.entries.take(1)))
                    ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 24,
                        child: Text('${entry.rank}', textAlign: TextAlign.end),
                      ),
                      title: Text(entry.player.name, overflow: TextOverflow.ellipsis),
                      trailing: Text('${entry.rating}'),
                    ),
                ],
              ),
        ],
      ),
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator.adaptive()),
      ),
      error: (error, stackTrace) => ListSection(
        children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
      ),
    );
  }

  String _modeLabel(BuildContext context, XiangqiRatingType mode) => switch (mode) {
    .rapid => context.l10n.mobileXiangqiSpeedRapid,
    .bullet => context.l10n.mobileXiangqiSpeedBullet,
    .daily => context.l10n.mobileXiangqiSpeedDaily,
    .puzzle => context.l10n.mobileXiangqiSpeedPuzzle,
  };
}
