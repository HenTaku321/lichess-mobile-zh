import 'package:chessground/chessground.dart' show BrightnessHueFilter;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform_search_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:material_ui/material_ui.dart';

/// The master-games database: famous players, and the games of theirs it holds.
///
/// ## What this is
///
/// A library of whole games — not openings, and not an explorer. A player is picked, their record
/// and their games are shown, and a game opens on a board with every move of it in a list.
///
/// ## Why this one is a board and the others are not
///
/// A master game is the one place on xiangqi.com where a game comes with its moves **in this app's
/// own spelling**: its `initial_fen` is a standard xiangqi FEN and its `moves` are standard ICCS,
/// so nothing has to be translated and nothing has to be guessed. That is not true of a lesson's
/// position, of a game's list entry, or of a puzzle's — see `xiangqi-com-re/docs/database.md`.
class const XiangqiDatabaseScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiDatabaseScreen());

  @override
  ConsumerState<XiangqiDatabaseScreen> createState() => _XiangqiDatabaseScreenState();
}

class _XiangqiDatabaseScreenState() extends ConsumerState<XiangqiDatabaseScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  int _page = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(
      xiangqiMasterPlayersProvider((_search.isEmpty ? null : _search, _page)),
    );

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText(
          '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiDatabase}',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: PlatformSearchBar(
              controller: _searchController,
              hintText: context.l10n.search,
              onChanged: (value) => setState(() {
                _search = value;
                _page = 1;
              }),
            ),
          ),
          Expanded(
            child: players.when(
              data: (players) => players.items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: Styles.bodySectionPadding,
                        child: Text(context.l10n.mobileXiangqiDatabasePlayersEmpty),
                      ),
                    )
                  : ListView(
                      children: [
                        ListSection(
                          hasLeading: true,
                          header: Text(context.l10n.mobileXiangqiDatabasePlayers),
                          children: [
                            for (final player in players.items) _PlayerRow(player: player),
                          ],
                        ),
                        _Pager(
                          page: players.totalPages == 0 ? 1 : _page,
                          hasNext: players.hasNextPage,
                          onChanged: (page) => setState(() => _page = page),
                        ),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator.adaptive()),
              error: (error, stackTrace) => _Failed(
                onRetry: () => ref.invalidate(
                  xiangqiMasterPlayersProvider((_search.isEmpty ? null : _search, _page)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One player of the database.
class const _PlayerRow({required final XiangqiMasterPlayer player}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(player.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (player.title != null) player.title!,
          context.l10n.mobileXiangqiDatabaseGamesCount('${player.gameCount}'),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Theme.of(context).platform == TargetPlatform.iOS
          ? const CupertinoListTileChevron()
          : null,
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiMasterPlayerScreen.buildRoute(player.id, player.name)),
    );
  }
}

/// One player's record and their games.
class const XiangqiMasterPlayerScreen({
  required final int playerId,
  required final String playerName,
  super.key,
}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute(int playerId, String playerName) => buildScreenRoute(
    screen: XiangqiMasterPlayerScreen(playerId: playerId, playerName: playerName),
  );

  @override
  ConsumerState<XiangqiMasterPlayerScreen> createState() => _XiangqiMasterPlayerScreenState();
}

class _XiangqiMasterPlayerScreenState() extends ConsumerState<XiangqiMasterPlayerScreen> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(xiangqiMasterStatsProvider(widget.playerId));
    final games = ref.watch(xiangqiMasterGamesProvider((widget.playerId, _page)));

    return Scaffold(
      appBar: AppBar(title: AppBarTitleText(widget.playerName)),
      body: ListView(
        children: [
          if (stats.value != null)
            ListSection(
              hasLeading: true,
              children: [
                ListTile(
                  dense: true,
                  title: Text(
                    [
                      if (stats.value!.title != null) stats.value!.title!,
                      if (stats.value!.country != null) stats.value!.country!,
                    ].join(' · '),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text(
                    [
                      context.l10n.nbWins(stats.value!.wins),
                      context.l10n.nbLosses(stats.value!.losses),
                      context.l10n.nbDraws(stats.value!.draws),
                    ].join(' · '),
                  ),
                ),
              ],
            ),
          games.when(
            data: (games) => ListSection(
              hasLeading: true,
              header: Text(context.l10n.mobileXiangqiDatabaseGames),
              children: [
                if (games.items.isEmpty)
                  ListTile(dense: true, title: Text(context.l10n.mobileXiangqiDatabaseGamesEmpty))
                else
                  for (final game in games.items) _GameRow(game: game),
              ],
            ),
            loading: () => ListSection.loading(itemsNumber: 4, header: true, hasLeading: true),
            error: (error, stackTrace) => ListSection(
              hasLeading: true,
              header: Text(context.l10n.mobileXiangqiDatabaseGames),
              children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
            ),
          ),
          if (games.value != null)
            _Pager(
              page: _page,
              hasNext: games.value!.hasNextPage,
              onChanged: (page) => setState(() => _page = page),
            ),
        ],
      ),
    );
  }
}

/// One game in a player's list.
class const _GameRow({required final XiangqiMasterGameRow game}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${game.redPlayer} — ${game.blackPlayer}', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          // The result is **for the player whose page this is**, which is what the server sends —
          // the same game read from the other player's page says the opposite.
          switch (game.resultForPlayer) {
            'won' => context.l10n.mobileXiangqiDatabaseWon,
            'lost' => context.l10n.mobileXiangqiDatabaseLost,
            'drawn' => context.l10n.mobileXiangqiDatabaseDrawn,
            _ => null,
          },
          if (game.tournamentName != null) game.tournamentName!,
          '${game.moveCount}',
        ].nonNulls.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Theme.of(context).platform == TargetPlatform.iOS
          ? const CupertinoListTileChevron()
          : null,
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiMasterGameScreen.buildRoute(game.slug)),
    );
  }
}

/// One game of the database, on a board.
class const XiangqiMasterGameScreen({required final String slug, super.key})
    extends ConsumerWidget {
  static Route<void> buildRoute(String slug) =>
      buildScreenRoute(screen: XiangqiMasterGameScreen(slug: slug));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(xiangqiMasterGameProvider(slug));

    return Scaffold(
      appBar: AppBar(title: AppBarTitleText(context.l10n.mobileXiangqiDatabase)),
      body: game.when(
        data: (game) => _Game(game: game),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stackTrace) =>
            _Failed(onRetry: () => ref.invalidate(xiangqiMasterGameProvider(slug))),
      ),
    );
  }
}

/// The board, with a cursor on it.
class const _Game({required final XiangqiMasterGame game}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Game> createState() => _GameState();
}

class _GameState() extends ConsumerState<_Game> {
  /// Which position is on the board: 0 is before the first move.
  int _cursor = 0;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    if (!game.isPlayable) {
      return Center(
        child: Padding(
          padding: Styles.bodySectionPadding,
          child: Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
        ),
      );
    }

    final boardPrefs = ref.watch(boardPreferencesProvider);
    final style = XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors);
    final cursor = _cursor.clamp(0, game.moves.length);

    return SafeArea(
      child: XiangqiGameLayout(
        board: BrightnessHueFilter(
          brightness: boardPrefs.brightness,
          hue: boardPrefs.hue,
          child: XiangqiBoard(
            position: game.positions[cursor],
            orientation: XiangqiSide.red,
            selected: null,
            moves: const IListConst([]),
            // A game out of a book is read, not played: no tap, no drag, no legal-move dots.
            onTapSquare: null,
            onDragMove: null,
            lastMove: boardPrefs.boardHighlights && cursor > 0 ? game.moves[cursor - 1] : null,
            animationDuration: Duration.zero,
            showCoordinates: boardPrefs.coordinates,
            showLastMove: boardPrefs.boardHighlights,
            showBorder: boardPrefs.showBorder,
            magnifyDraggedPiece: false,
            dragTargetKind: boardPrefs.dragTargetKind,
            style: style,
          ),
        ),
        topTable: _PlayerLine(
          name: game.blackPlayer,
          title: game.blackTitle,
          country: game.blackCountry,
          isWinner: game.winner == XiangqiSide.black,
        ),
        bottomTable: _PlayerLine(
          name: game.redPlayer,
          title: game.redTitle,
          country: game.redCountry,
          isWinner: game.winner == XiangqiSide.red,
        ),
        moves: xiangqiGameNotation(game.positions, game.moves),
        currentMoveIndex: cursor,
        onSelectMove: (index) => setState(() => _cursor = index),
        userActionsBar: BottomBar(
          children: [
            BottomBarButton(
              label: context.l10n.mobileXiangqiReviewPrevious,
              onTap: cursor > 0 ? () => setState(() => _cursor = cursor - 1) : null,
              icon: CupertinoIcons.chevron_back,
            ),
            BottomBarButton(
              label: context.l10n.mobileXiangqiReviewNext,
              onTap: cursor < game.moves.length ? () => setState(() => _cursor = cursor + 1) : null,
              icon: CupertinoIcons.chevron_forward,
            ),
          ],
        ),
      ),
    );
  }
}

/// One seat of a game out of the database.
class const _PlayerLine({
  required final String name,
  required final String? title,
  required final String? country,
  required final bool isWinner,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isWinner)
          Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: Icon(Icons.emoji_events, size: 18, color: context.lichessColors.brag),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (title != null || country != null)
                Text(
                  [title, country].nonNulls.join(' · '),
                  style: TextStyle(fontSize: 12, color: textShade(context, 0.7)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The way from one page of a list to the next.
class const _Pager({
  required final int page,
  required final bool hasNext,
  required final void Function(int) onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Styles.bodySectionPadding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton.icon(
            onPressed: page > 1 ? () => onChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
            label: Text('${page - 1}'),
          ),
          Text('$page'),
          TextButton.icon(
            onPressed: hasNext ? () => onChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
            label: Text('${page + 1}'),
          ),
        ],
      ),
    );
  }
}

/// Something did not arrive, and there is a way to ask again.
class const _Failed({required final VoidCallback onRetry}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Styles.bodySectionPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
            const SizedBox(height: 16.0),
            FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}
