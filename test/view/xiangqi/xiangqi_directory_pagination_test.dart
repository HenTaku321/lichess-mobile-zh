import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_friends_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_tournaments_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/tournament/xiangqi_tournament_test.dart' as tournaments;
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
