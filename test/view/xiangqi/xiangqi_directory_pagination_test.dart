import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_database_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_friends_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_leaderboard_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_tournaments_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/database/xiangqi_master_game_test.dart' as database;
import '../../model/xiangqi/tournament/xiangqi_tournament_test.dart' as tournaments;
import 'xiangqi_leaderboard_screen_test.dart' as leaders;
import 'xiangqi_profile_screen_test.dart' as profiles;
import 'xiangqi_saved_friends_parity_test.dart' as remote;

Map<String, Object?> envelope(List<Object?> items, int page, {String field = 'items'}) => {
  field: items,
  'total_pages': 2,
  'has_next_page': page == 1,
  'next_page_num': page == 1 ? 2 : null,
  'prev_page_num': page == 1 ? null : 1,
};

void main() {
  TestLichessBinding.ensureInitialized();

  for (final ranking in [false, true]) {
    testWidgets('page navigation failure keeps the last selected result (ranking: $ranking)', (
      tester,
    ) async {
      final pages = <int>[];
      var failSecond = true;
      await remote.pumpRemote(
        tester,
        ranking ? const XiangqiLeaderboardScreen() : const XiangqiDatabaseScreen(),
        MockClient((request) async {
          if (!(ranking
              ? request.url.path.endsWith('/leaders/v2/list')
              : request.url.path.contains('/master-games/players'))) {
            return remote.jsonReply({});
          }
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          pages.add(page);
          if (page == 2 && failSecond) return remote.jsonReply({}, 503);
          return remote.jsonReply(
            ranking
                ? leaders.board(
                    data: [leaders.row(name: 'Player on page $page', rating: 1900)],
                    totalPages: 2,
                    totalPlayers: 2,
                    currentPage: page,
                  )
                : database.page([
                    database.player(name: 'Player on page $page'),
                  ], nextPage: page == 1 ? 2 : null),
          );
        }),
      );
      await tester.ensureVisible(find.byIcon(Icons.chevron_right));
      await tester.tap(find.byIcon(Icons.chevron_right));
      await remote.settleRemote(tester);
      expect(find.text('Player on page 1'), findsOneWidget);
      expect(pages, [1, 2]);
      final retry = find.byType(XiangqiRetryTile);
      expect(retry, findsOneWidget);
      final context = tester.element(
        ranking ? find.byType(XiangqiLeaderboardScreen) : find.byType(XiangqiDatabaseScreen),
      );
      failSecond = false;
      await tester.ensureVisible(retry);
      await tester.tap(find.descendant(of: retry, matching: find.byTooltip(context.l10n.retry)));
      await remote.settleRemote(tester);
      expect(pages, [1, 2, 2]);
      expect(find.text('Player on page 2'), findsOneWidget);
      expect(find.text('Player on page 1'), findsNothing);
    });

    testWidgets('an empty selected page still offers navigation back (ranking: $ranking)', (
      tester,
    ) async {
      final pages = <int>[];
      await remote.pumpRemote(
        tester,
        ranking ? const XiangqiLeaderboardScreen() : const XiangqiDatabaseScreen(),
        MockClient((request) async {
          if (!(ranking
              ? request.url.path.endsWith('/leaders/v2/list')
              : request.url.path.contains('/master-games/players'))) {
            return remote.jsonReply({});
          }
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          pages.add(page);
          return remote.jsonReply(
            ranking
                ? leaders.board(
                    data: page == 1 ? [leaders.row(name: 'First player', rating: 1900)] : [],
                    totalPages: 2,
                    totalPlayers: 1,
                    currentPage: page,
                  )
                : database.page(
                    page == 1 ? [database.player(name: 'First player')] : [],
                    nextPage: page == 1 ? 2 : null,
                  ),
          );
        }),
      );
      await tester.ensureVisible(find.byIcon(Icons.chevron_right));
      await tester.tap(find.byIcon(Icons.chevron_right));
      await remote.settleRemote(tester);
      final previous = find.byIcon(Icons.chevron_left);
      expect(previous, findsOneWidget);
      await tester.ensureVisible(previous);
      await tester.tap(previous);
      await remote.settleRemote(tester);
      expect(pages, [1, 2, 1]);
    });
  }

  testWidgets(
    'a failed previous ranking page retries that page without replacing the current one',
    (tester) async {
      final pages = <int>[];
      int? failPage;
      await remote.pumpRemote(
        tester,
        const XiangqiTournamentScreen(id: 'AbCdEf', name: 'Event'),
        MockClient((request) async {
          if (request.url.path.endsWith('/leaders')) {
            final page = int.parse(request.url.queryParameters['page'] ?? '1');
            pages.add(page);
            if (page == failPage) return remote.jsonReply({}, 503);
            return remote.jsonReply(envelope([], page, field: 'participants'));
          }
          if (request.url.path.contains('/participants/')) return remote.jsonReply(<Object?>[]);
          return remote.jsonReply(tournaments.tournament());
        }),
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      await remote.settleRemote(tester);
      failPage = 1;
      await tester.tap(find.byIcon(Icons.chevron_left));
      await remote.settleRemote(tester);
      expect(pages, [1, 2, 1]);
      final retry = find.byType(XiangqiRetryTile);
      expect(retry, findsOneWidget);
      failPage = null;
      final context = tester.element(find.byType(XiangqiTournamentScreen));
      await tester.tap(find.descendant(of: retry, matching: find.byTooltip(context.l10n.retry)));
      await remote.settleRemote(tester);
      expect(pages, [1, 2, 1, 1]);
      expect(retry, findsNothing);
    },
  );

  testWidgets('a partial refresh retry resumes at the failed page instead of rereading page one', (
    tester,
  ) async {
    final pages = <int>[];
    var fail = false;
    await remote.pumpRemote(
      tester,
      const XiangqiFriendsScreen(),
      MockClient((request) async {
        if (request.url.path.endsWith('/friend-requests')) {
          return remote.jsonReply({'friend_requests': <Object?>[]});
        }
        if (!request.url.path.startsWith('/api/friends/')) return remote.jsonReply({});
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        pages.add(page);
        if (page == 2 && fail) return remote.jsonReply({}, 503);
        return remote.jsonReply(envelope([], page));
      }),
    );
    final context = tester.element(find.byType(XiangqiFriendsScreen));
    await tester.tap(find.text(context.l10n.mobileLoadMore));
    await remote.settleRemote(tester);
    fail = true;
    await tester.tap(find.byType(DesktopRefreshButton));
    await remote.settleRemote(tester);
    expect(pages, [1, 2, 1, 2]);
    final retry = find.byType(XiangqiRetryTile);
    expect(retry, findsOneWidget);
    fail = false;
    await tester.ensureVisible(retry);
    await tester.tap(find.descendant(of: retry, matching: find.byTooltip(context.l10n.retry)));
    await remote.settleRemote(tester);
    expect(pages, [1, 2, 1, 2, 2]);
    expect(retry, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('friends expose the confirmed next-page cursor even for an empty current page', (
    tester,
  ) async {
    final pages = <int>[];
    await remote.pumpRemote(
      tester,
      const XiangqiFriendsScreen(),
      MockClient((request) async {
        if (request.url.path.endsWith('/friend-requests')) {
          return remote.jsonReply({'friend_requests': <Object?>[]});
        }
        if (!request.url.path.startsWith('/api/friends/')) {
          return remote.jsonReply({});
        }
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        pages.add(page);
        return remote.jsonReply(envelope([], page));
      }),
    );
    final context = tester.element(find.byType(XiangqiFriendsScreen));
    final more = find.text(context.l10n.mobileLoadMore);
    expect(more, findsOneWidget);
    await tester.tap(more);
    await remote.settleRemote(tester);
    expect(pages, [1, 2]);
    expect(more, findsNothing);
  });

  testWidgets('profile history appends page two without replacing the first game', (tester) async {
    final pages = <int>[];
    final details = profiles.profileClient(withGames: false);
    addTearDown(details.close);
    await profiles.pumpProfile(
      tester,
      client: MockClient((request) async {
        if (!request.url.path.startsWith('/api/users/games/')) {
          return await details.get(request.url, headers: request.headers);
        }
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        pages.add(page);
        return remote.jsonReply(
          envelope([
            {
              'id': 'history-page-$page',
              'state': 3,
              'end_reason': 100,
              'moves_count': 42,
              'game_timer': 10,
              'increment': 5,
              'last_move_time': '2026-10-16T08:24:45.411049',
              'rplayer': profiles.seat(name: 'red-page-$page', result: 30),
              'bplayer': profiles.seat(name: 'black-page-$page', result: 10),
            },
          ], page),
        );
      }),
    );
    await profiles.scrollDown(tester);
    await profiles.settle(tester);
    await profiles.scrollDown(tester);
    final context = tester.element(find.byType(XiangqiProfileScreen));
    final more = find.text(context.l10n.mobileLoadMore);
    expect(more, findsOneWidget);
    await tester.ensureVisible(more);
    await tester.tap(more);
    await profiles.settle(tester);
    expect(pages, [1, 2]);
    expect(find.textContaining('red-page-1'), findsOneWidget);
    expect(find.textContaining('red-page-2'), findsOneWidget);
  });

  testWidgets('tournament standings use reachable previous and next pages', (tester) async {
    final pages = <int>[];
    await remote.pumpRemote(
      tester,
      const XiangqiTournamentScreen(id: 'AbCdEf', name: 'Event'),
      MockClient((request) async {
        if (request.url.path.endsWith('/leaders')) {
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          pages.add(page);
          return remote.jsonReply(envelope([], page, field: 'participants'));
        }
        if (request.url.path.contains('/participants/')) return remote.jsonReply(<Object?>[]);
        return remote.jsonReply(tournaments.tournament());
      }),
    );
    final next = find.byIcon(Icons.chevron_right);
    expect(next, findsOneWidget);
    await tester.ensureVisible(next);
    await tester.tap(next);
    await remote.settleRemote(tester);
    expect(pages, [1, 2]);
    final previous = find.byIcon(Icons.chevron_left);
    await tester.tap(previous);
    await remote.settleRemote(tester);
    expect(pages, [1, 2, 1]);
  });
}
