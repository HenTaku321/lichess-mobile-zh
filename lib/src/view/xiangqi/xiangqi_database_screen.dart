import 'package:chessground/chessground.dart' show BrightnessHueFilter;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_options.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_country_names.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_locale.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform_search_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_analysis_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
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
    final locale = xiangqiLocaleOf(Localizations.localeOf(context));
    final players = ref.watch(
      xiangqiMasterPlayersProvider((
        search: _search.isEmpty ? null : _search,
        page: _page,
        locale: locale,
      )),
    );

    final identity = (_search, _page, locale, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(
        xiangqiMasterPlayersProvider((
          search: _search.isEmpty ? null : _search,
          page: _page,
          locale: locale,
        )).future,
      ),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: players,
        builder: (context, players) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(
              '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiDatabase}',
            ),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
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
                  error: (error, stackTrace) => _Failed(onRetry: refresh),
                ),
              ),
            ],
          ),
        ),
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
    final locale = xiangqiLocaleOf(Localizations.localeOf(context));
    final stats = ref.watch(xiangqiMasterStatsProvider((id: widget.playerId, locale: locale)));
    final games = ref.watch(
      xiangqiMasterGamesProvider((playerId: widget.playerId, page: _page, locale: locale)),
    );

    final identity = (widget.playerId, _page, locale, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => Future.wait<Object?>([
        ref.refresh(xiangqiMasterStatsProvider((id: widget.playerId, locale: locale)).future),
        ref.refresh(
          xiangqiMasterGamesProvider((playerId: widget.playerId, page: _page, locale: locale))
              .future,
        ),
      ]),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: (widget.playerId, locale, ref.watch(xiangqiAccountGenerationProvider)),
        value: stats,
        builder: (context, stats) => XiangqiRetainedData(
          identity: identity,
          value: games,
          builder: (context, games) => Scaffold(
            appBar: AppBar(
              title: AppBarTitleText(widget.playerName),
              actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
            ),
            body: ListView(
              children: [
                if (stats.isLoading) ListSection.loading(itemsNumber: 2, hasLeading: true),
                if (stats.hasError)
                  ListSection(
                    hasLeading: true,
                    children: [
                      XiangqiRetryTile(
                        onRetry: busy
                            ? null
                            : () => refresh(
                                request: () => ref.refresh(
                                  xiangqiMasterStatsProvider((id: widget.playerId, locale: locale))
                                      .future,
                                ),
                              ),
                      ),
                    ],
                  ),
                if (stats.value != null)
                  ListSection(
                    hasLeading: true,
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                          [
                            if (stats.value!.title != null) stats.value!.title!,
                            if (stats.value!.country != null)
                              xiangqiLocalizedCountryName(
                                    Localizations.localeOf(context),
                                    code: stats.value!.country,
                                  ) ??
                                  stats.value!.country!,
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
                        ListTile(
                          dense: true,
                          title: Text(context.l10n.mobileXiangqiDatabaseGamesEmpty),
                        )
                      else
                        for (final game in games.items) _GameRow(game: game),
                    ],
                  ),
                  loading: () =>
                      ListSection.loading(itemsNumber: 4, header: true, hasLeading: true),
                  error: (error, stackTrace) => ListSection(
                    hasLeading: true,
                    header: Text(context.l10n.mobileXiangqiDatabaseGames),
                    children: [
                      XiangqiRetryTile(
                        onRetry: busy
                            ? null
                            : () => refresh(
                                request: () => ref.refresh(
                                  xiangqiMasterGamesProvider((
                                    playerId: widget.playerId,
                                    page: _page,
                                    locale: locale,
                                  )).future,
                                ),
                              ),
                      ),
                    ],
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
          ),
        ),
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
    final locale = xiangqiLocaleOf(Localizations.localeOf(context));
    final game = ref.watch(xiangqiMasterGameProvider((slug: slug, locale: locale)));

    final identity = (slug, locale, ref.watch(xiangqiAccountGenerationProvider));
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(xiangqiMasterGameProvider((slug: slug, locale: locale)).future),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: game,
        builder: (context, game) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(context.l10n.mobileXiangqiDatabase),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          ),
          body: game.when(
            data: (game) => _Game(game: game, onRefresh: refresh),
            loading: () => const Center(child: CircularProgressIndicator.adaptive()),
            error: (error, stackTrace) => _Failed(onRetry: refresh),
          ),
        ),
      ),
    );
  }
}

/// The board, with a cursor on it.
class const _Game({required final XiangqiMasterGame game, required final XiangqiRefresh onRefresh})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Game> createState() => _GameState();
}

class _GameState() extends ConsumerState<_Game> {
  /// Which position is on the board: 0 is before the first move.
  int _cursor = 0;
  bool _animate = false;
  bool _isFlipped = false;

  @override
  void didUpdateWidget(_Game oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game == widget.game) return;
    final keep =
        _cursor < widget.game.positions.length &&
        _cursor < oldWidget.game.positions.length &&
        widget.game.positions[_cursor] == oldWidget.game.positions[_cursor];
    if (!keep) _cursor = 0;
    _animate = false;
  }

  void _goTo(int target, {bool fastSeek = false}) {
    final game = widget.game;
    final next = target.clamp(0, game.moves.length);
    if (next == _cursor) return;
    _animate = !fastSeek && (next - _cursor).abs() == 1;
    if (next > 0) {
      final i = next - 1;
      final capture = game.positions[i].pieceAt(game.moves[i].to) != null;
      ref.read(soundServiceProvider).play(capture ? Sound.capture : Sound.move);
    }
    setState(() => _cursor = next);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    if (!game.isPlayable) {
      return Center(
        child: Padding(
          padding: Styles.bodySectionPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: widget.onRefresh, child: Text(context.l10n.retry)),
            ],
          ),
        ),
      );
    }

    final boardPrefs = ref.watch(boardPreferencesProvider);
    final style = XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors);
    final cursor = _cursor.clamp(0, game.moves.length);

    return SafeArea(
      child: XiangqiAnalysisLayout(
        smallBoard: ref.watch(analysisPreferencesProvider).smallBoard,
        inlineNotation: ref.watch(analysisPreferencesProvider).inlineNotation,
        boardBuilder: (context, size, radius) => BrightnessHueFilter(
          brightness: boardPrefs.brightness,
          hue: boardPrefs.hue,
          child: XiangqiBoard(
            settings: XiangqiBoardSettings.fromPreferences(boardPrefs),
            position: game.positions[cursor],
            orientation: _isFlipped ? XiangqiSide.black : XiangqiSide.red,
            selected: null,
            moves: const IListConst([]),
            // A game out of a book is read, not played: no tap, no drag, no legal-move dots.
            onTapSquare: null,
            onDragMove: null,
            lastMove: cursor > 0 ? game.moves[cursor - 1] : null,
            animationDuration: _animate ? boardPrefs.pieceAnimationDuration : Duration.zero,
            showCoordinates: boardPrefs.coordinates,
            showLastMove: boardPrefs.boardHighlights,
            showBorder: boardPrefs.showBorder,
            magnifyDraggedPiece: false,
            dragTargetKind: boardPrefs.dragTargetKind,
            style: style,
          ),
        ),
        boardHeader: _PlayerLine(
          name: _isFlipped ? game.redPlayer : game.blackPlayer,
          title: _isFlipped ? game.redTitle : game.blackTitle,
          country: _isFlipped ? game.redCountry : game.blackCountry,
          isWinner: game.winner == (_isFlipped ? XiangqiSide.red : XiangqiSide.black),
        ),
        boardFooter: _PlayerLine(
          name: _isFlipped ? game.blackPlayer : game.redPlayer,
          title: _isFlipped ? game.blackTitle : game.redTitle,
          country: _isFlipped ? game.blackCountry : game.redCountry,
          isWinner: game.winner == (_isFlipped ? XiangqiSide.black : XiangqiSide.red),
        ),
        moves: xiangqiGameNotation(game.positions, game.moves),
        currentMoveIndex: cursor,
        onSelectMove: _goTo,
        bottomBar: BottomBar(
          children: [
            BottomBarButton(
              label: context.l10n.menu,
              icon: Icons.menu,
              onTap: () => showAdaptiveActionSheet<void>(
                context: context,
                actions: [
                  BottomSheetAction(
                    makeLabel: (context) => Text(context.l10n.analysis),
                    onPressed: () => Navigator.of(context).push(
                      XiangqiAnalysisScreen.buildRoute(
                        options: XiangqiAnalysisOptions.line(
                          sourceId: 'master:${game.slug}',
                          initialPosition: game.positions.first,
                          moves: game.moves,
                          initialCursor: cursor,
                          orientation: _isFlipped ? XiangqiSide.black : XiangqiSide.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            BottomBarButton(
              label: context.l10n.flipBoard,
              icon: CupertinoIcons.arrow_2_squarepath,
              onTap: () => setState(() => _isFlipped = !_isFlipped),
            ),
            HistoryNavigationButton(
              forward: false,
              onTap: cursor > 0 ? () => _goTo(cursor - 1) : null,
              onRepeat: () => _goTo(cursor - 1, fastSeek: true),
            ),
            HistoryNavigationButton(
              forward: true,
              onTap: cursor < game.moves.length ? () => _goTo(cursor + 1) : null,
              onRepeat: () => _goTo(cursor + 1, fastSeek: true),
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
          child: Tooltip(
            message: [name, title, country].nonNulls.join(' · '),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (title != null || country != null)
                    TextSpan(
                      text: ' · ${[title, country].nonNulls.join(' · ')}',
                      style: TextStyle(color: textShade(context, 0.7)),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
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
