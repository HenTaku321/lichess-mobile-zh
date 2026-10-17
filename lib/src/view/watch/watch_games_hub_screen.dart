import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/tv/live_tv_channels.dart';
import 'package:lichess_mobile/src/model/tv/tv_channel.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/watch/tv_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/board_preview.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/source_preview_block.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';

/// Live games from Lichess TV and xiangqi.com on one page.
class const WatchGamesHubScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const WatchGamesHubScreen());

  @override
  ConsumerState<WatchGamesHubScreen> createState() => _WatchGamesHubScreenState();
}

class _WatchGamesHubScreenState() extends ConsumerState<WatchGamesHubScreen> {
  bool _lichessExpanded = false;
  bool _xiangqiExpanded = false;

  @override
  Widget build(BuildContext context) {
    final lichess = ref.watch(liveTvChannelsProvider);
    final xiangqi = ref.watch(xiangqiLiveGamesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.mobileWatchGames)),
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          ref.read(liveTvChannelsProvider.notifier).startWatching();
          await Future.wait([
            ref.refresh(liveTvChannelsProvider.future),
            ref.refresh(xiangqiLiveGamesProvider.future),
          ]);
        },
        child: ListView(
          children: [
            SourcePreviewBlock(
              leading: const Icon(Icons.smart_display_outlined),
              title: const Text('Lichess TV'),
              expandedState: _lichessExpanded,
              onToggle: () => setState(() => _lichessExpanded = !_lichessExpanded),
              preview: _LichessGames(state: lichess, expanded: false),
              expanded: _LichessGames(state: lichess, expanded: true),
            ),
            const Divider(height: 1),
            SourcePreviewBlock(
              leading: const Icon(Icons.grid_on),
              title: const Text('Xiangqi.com'),
              expandedState: _xiangqiExpanded,
              onToggle: () => setState(() => _xiangqiExpanded = !_xiangqiExpanded),
              summary: xiangqi.value == null ? null : Text('${xiangqi.value!.length}'),
              preview: _XiangqiGames(state: xiangqi, expanded: false),
              expanded: _XiangqiGames(state: xiangqi, expanded: true),
            ),
            const SizedBox(height: 24.0),
          ],
        ),
      ),
    );
  }
}

class const _LichessGames({
  required final AsyncValue<LiveTvChannelsState> state,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (games) {
        final channels = [
          for (final channel in TvChannel.values)
            if (games[channel] != null) games[channel]!,
        ];
        final shown = expanded ? channels : channels.take(4).toList();
        if (shown.isEmpty) {
          return ListSection(
            children: [ListTile(dense: true, title: Text(context.l10n.noGameFound))],
          );
        }
        return Column(
          children: [
            for (final game in shown)
              SmallBoardPreview(
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  TvScreen.buildRoute(
                    channel: game.channel,
                    gameId: game.id,
                    orientation: game.orientation,
                  ),
                ),
                orientation: game.orientation,
                fen: game.fen ?? kEmptyFEN,
                lastMove: game.lastMove,
                description: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(game.channel.label(context.l10n), style: Styles.boardPreviewTitle),
                    Icon(game.channel.icon, size: 32),
                    UserFullNameWidget.player(
                      user: game.player.asPlayer.user,
                      aiLevel: game.player.asPlayer.aiLevel,
                      rating: game.player.rating,
                    ),
                  ],
                ),
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

class const _XiangqiGames({
  required final AsyncValue<IList<XiangqiLiveGame>> state,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (games) {
        final shown = expanded ? games : games.take(5).toList();
        if (shown.isEmpty) {
          return ListSection(
            children: [ListTile(dense: true, title: Text(context.l10n.mobileXiangqiNoGames))],
          );
        }
        return ListSection(
          hasLeading: true,
          children: [for (final game in shown) _XiangqiGameRow(game: game)],
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

class const _XiangqiGameRow({required final XiangqiLiveGame game}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final red = game.red.name;
    final black = game.black.name;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.grid_on),
      title: Text('$red — $black', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${game.gameTimeSeconds ~/ 60}+${game.incrementSeconds} · '
        '${game.movesCount} moves',
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiOnlineGameScreen.buildRoute(game.id)),
    );
  }
}
