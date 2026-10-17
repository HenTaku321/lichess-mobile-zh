import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_country_names.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform_search_bar.dart';
import 'package:material_ui/material_ui.dart';

/// xiangqi.com's leaderboards, one board per rating.
///
/// ## What is on the boards
///
/// Four of them — rapid, bullet, daily and puzzle — and **three of the four are empty**. Measured on
/// 2026-10-16, every game board answered `total_players: 0` with no rows at all, while the puzzle
/// board held 409,730 accounts over 27,316 pages. That is the site's own state and not a failure of
/// this screen, which is why an empty board says so in a sentence rather than showing an error: a
/// screen that called it a fault would be reporting a fault where there is none.
///
/// ## Where a rank comes from
///
/// The server sends the rows in order and the page number, and **no rank on the rows themselves**.
/// A row's rank is worked out from where it sits — see [kXiangqiLeaderboardPageSize] — which is why
/// the page size is written down in the model rather than left to the server to imply.
class const XiangqiLeaderboardScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiLeaderboardScreen());

  @override
  ConsumerState<XiangqiLeaderboardScreen> createState() => _XiangqiLeaderboardScreenState();
}

class _XiangqiLeaderboardScreenState() extends ConsumerState<XiangqiLeaderboardScreen> {
  XiangqiRatingType _mode = XiangqiRatingType.rapid;

  /// The country the board is filtered to, or null for every country.
  String? _country;

  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(xiangqiLeaderboardProvider((_mode, _country, _page)));

    // The tabs are a plain `TabBar` over a `DefaultTabController`: the screen keeps the mode in its
    // own state and the controller is only what the bar needs to draw itself, so there is nothing
    // for a controller of the screen's own to do that its state does not already do.
    return DefaultTabController(
      length: XiangqiRatingType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.leaderboard}'),
          actions: [
            IconButton(
              tooltip: context.l10n.mobileXiangqiLeaderboardCountry,
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => _pickCountry(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (index) => setState(() {
              _mode = XiangqiRatingType.values[index];
              _page = 1;
            }),
            tabs: [
              for (final mode in XiangqiRatingType.values) Tab(text: _modeLabel(context, mode)),
            ],
          ),
        ),
        body: board.when(
          data: (board) => board.entries.isEmpty
              ? const Center(
                  child: Padding(padding: Styles.bodySectionPadding, child: _Empty()),
                )
              : ListView(
                  children: [
                    ListSection(
                      header: Text(
                        context.l10n.mobileXiangqiLeaderboardPlayers('${board.totalPlayers}'),
                      ),
                      hasLeading: true,
                      children: [for (final entry in board.entries) _LeaderRow(entry: entry)],
                    ),
                    _Pager(
                      page: board.currentPage,
                      hasNext: board.hasNextPage,
                      onChanged: (page) => setState(() => _page = page),
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
                    onPressed: () =>
                        ref.invalidate(xiangqiLeaderboardProvider((_mode, _country, _page))),
                    child: Text(context.l10n.retry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Asks which country to filter by, and clears the filter when asked for none.
  ///
  /// The list is the server's own country table, which is fetched once and kept for the session —
  /// see [xiangqiCountriesProvider]. A table that has not arrived yet is an empty picker rather than
  /// a spinner: this is a filter, and a filter that cannot be set is not a reason to hold the board
  /// back.
  Future<void> _pickCountry(BuildContext context) async {
    final countries = ref.read(xiangqiCountriesProvider).value ?? const IMapConst({});
    String? choice;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => _CountrySheet(
        countries: countries,
        selected: _country,
        onSelected: (code) => choice = code,
      ),
    );
    if (!mounted || choice == _country) return;
    setState(() {
      _country = choice;
      _page = 1;
    });
  }
}

/// One row of a board: the rank, who it is, and the rating they hold it with.
class const _LeaderRow({required final XiangqiLeaderboardEntry entry}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = entry.player;
    return ListTile(
      leading: SizedBox(
        width: 28,
        child: Text(
          '${entry.rank}',
          textAlign: TextAlign.end,
          style: TextStyle(
            color: textShade(context, 0.6),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      title: Text(player.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (player.countryName != null)
            xiangqiLocalizedCountryName(
                  Localizations.localeOf(context),
                  englishName: player.countryName,
                ) ??
                player.countryName!,
          // The two boards count different things, and the server sends whichever one is the
          // board's own. A row that has neither shows neither.
          if (entry.challengeAttempts != null)
            context.l10n.mobileXiangqiLeaderboardPlayers('${entry.challengeAttempts}'),
          if (entry.winRate != null) '${entry.winRate!.round()}%',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${entry.rating}',
        style: TextTheme.of(context).titleMedium
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiProfileScreen.buildRoute(player.name)),
    );
  }
}

/// The way from one page of a board to the next.
///
/// Two buttons rather than an endless scroll: the boards can be tens of thousands of pages long,
/// and a list that only ever grew would be a list nobody could get to the end of.
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

/// The country picker.
class const _CountrySheet({
  required final IMap<String, String> countries,
  required final String? selected,
  required final void Function(String?) onSelected,
}) extends StatefulWidget {
  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState() extends State<_CountrySheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final locale = Localizations.localeOf(context);
    final entries =
        widget.countries.entries
            .map(
              (entry) => (
                code: entry.key,
                name:
                    xiangqiLocalizedCountryName(
                      locale,
                      code: entry.key,
                      englishName: entry.value,
                    ) ??
                    entry.value,
              ),
            )
            .where((entry) => query.isEmpty || entry.name.toLowerCase().contains(query))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: PlatformSearchBar(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                // A check rather than a radio: the Material radio group's own API is deprecated in
                // this Flutter, and a list of countries is a list of choices either way.
                _CountryTile(
                  name: context.l10n.mobileXiangqiLeaderboardAllCountries,
                  selected: widget.selected == null,
                  onTap: () => _pick(null),
                ),
                for (final entry in entries)
                  _CountryTile(
                    name: entry.name,
                    selected: widget.selected == entry.code,
                    onTap: () => _pick(entry.code),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pick(String? code) {
    widget.onSelected(code);
    Navigator.of(context).pop();
  }
}

/// One country in the picker, and whether it is the one being filtered by.
class const _CountryTile({
  required final String name,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(name),
      trailing: selected ? Icon(Icons.check, color: ColorScheme.of(context).primary) : null,
      onTap: onTap,
    );
  }
}

/// What a board says when nobody is on it.
class const _Empty() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(context.l10n.mobileXiangqiLeaderboardEmpty, textAlign: TextAlign.center);
  }
}

/// The name of [mode], in the reader's own language.
String _modeLabel(BuildContext context, XiangqiRatingType mode) => switch (mode) {
  .rapid => context.l10n.mobileXiangqiSpeedRapid,
  .bullet => context.l10n.mobileXiangqiSpeedBullet,
  .daily => context.l10n.mobileXiangqiSpeedDaily,
  .puzzle => context.l10n.mobileXiangqiSpeedPuzzle,
};
