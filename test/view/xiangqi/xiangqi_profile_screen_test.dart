// Tests for the screen a xiangqi.com account is looked at on.
//
// The screen is driven over a stubbed HTTP client: the account, the four records and the game
// history are five calls, and what is under test is that the screen draws each of them and does not
// hold one back for another.
//
// The values are invented. The shapes come from `xiangqi-com-re/captures/profile/`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// A little over the client's own spacing between two requests to the host.
const _spacing = Duration(milliseconds: 1600);

/// The name every request in these tests is about.
const _username = 'a-player';

/// Pumps until nothing more is coming, advancing the clock over the client's spacing.
///
/// Five calls, each spaced behind the one before it, is five spacings.
Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
  for (var round = 0; round < rounds; round++) {
    await tester.pump(_spacing);
  }
}

/// Pumps until every request the screen has started has been answered.
///
/// The client spaces its requests, and each section of the screen asks for its own — so a test that
/// stopped as soon as it had read what it came for would leave a spacing timer pending, and the
/// harness fails a test that ends with one. Twenty rounds is more than the five calls need.
Future<void> drain(WidgetTester tester) => settle(tester, rounds: 20);

/// Scrolls the profile to its lower half.
///
/// The screen is longer than a phone — a header, four ratings, four records and a game list — and a
/// [ListView] only builds what is on screen, so the sections below the fold are not in the tree
/// until they are scrolled to.
Future<void> scrollDown(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
  }
}

/// One seat of a game-history row.
Map<String, Object?> seat({required String name, required int result}) => {
  'id': 1,
  'username': name,
  'identity': name,
  'rating': 1500,
  'result': result,
  'seconds': 600,
  'p_type': 10,
  'country': {'name': 'Viet Nam', 'code': 'VN'},
};

/// A client that answers the five endpoints this screen reads.
MockClient profileClient({bool withGames = true}) => MockClient((request) async {
  Object body;
  switch (request.url.path) {
    case '/api/users/account/$_username':
      body = {
        'id': 1,
        'username': _username,
        'identity': _username,
        'country': {'id': 1, 'code': 'VN', 'name': 'Viet Nam'},
        'bullet_rating': 900,
        'rapid_rating': 1200,
        'daily_rating': 1000,
        'puzzle_rating': 600,
        'is_online': true,
        'member_since': 'Thu, 15 Oct 2026 14:05:19 GMT',
        'last_online': "b'1792142453'",
      };
    case '/api/users/multiplayer_stats/$_username':
      body = {
        'wins': 12,
        'losses': 8,
        'draws': 3,
        'win_rate': 52.17,
        'total_games': 23,
        'current_rating': 1234,
        'highest_rating': 1300,
        'rating_history': <Object?>[],
      };
    case '/api/users/puzzle_stats/$_username':
      body = {
        'attempted': 40,
        'success_rate': 62.5,
        'current_rating': 1500,
        'highest_rating': 1600,
        'rating_history': <Object?>[],
      };
    case '/api/users/games/$_username':
      body = {
        'total_pages': 1,
        'next_page_num': null,
        'items': withGames
            ? [
                {
                  'id': 'AbCdEf1234',
                  'state': 3,
                  'end_reason': 100,
                  'moves_count': 42,
                  'game_timer': 10,
                  'increment': 5,
                  'last_move_time': '2026-10-16T08:24:45.411049',
                  'rplayer': seat(name: 'red-one', result: 30),
                  'bplayer': seat(name: 'black-two', result: 10),
                },
              ]
            : <Object?>[],
      };
    default:
      return http.Response('', 404);
  }
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: const {'content-type': 'application/json'},
  );
});

/// Opens the profile screen over [client], signed in as [sessionName] or not at all.
Future<void> pumpProfile(
  WidgetTester tester, {
  required MockClient client,
  String? sessionName = _username,
}) async {
  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        home: XiangqiProfileScreen(username: _username),
      ),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
          (ref) => fx.FakeXiangqiAuthStorage(
            sessionName == null
                ? null
                // The fixture names a session after the id it is given, so the id is what has to
                // carry the name the screen compares against.
                : fx.xiangqiTestSession(fx.xiangqiTestToken(sessionName), userId: sessionName),
          ),
        ),
      },
    ),
  );
  await settle(tester);
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiProfileScreen', () {
    testWidgets('draws the account, its four ratings and its records', (tester) async {
      await pumpProfile(tester, client: profileClient());

      expect(find.text(_username), findsWidgets);
      expect(find.textContaining('Viet Nam'), findsWidgets);

      // The four ratings, each on its own row.
      expect(find.text('900'), findsOneWidget);
      expect(find.text('1200'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);

      // One record per speed, and the puzzle one is a different shape read from a different
      // endpoint — so both halves are pinned here. The list is longer than a phone, so the lower
      // half is scrolled to before it is asserted on.
      expect(find.text('12 wins'), findsWidgets);
      expect(find.text('Win rate 52%'), findsWidgets);

      await scrollDown(tester);
      await settle(tester, rounds: 2);
      expect(find.text('Puzzles attempted 40'), findsOneWidget);
      expect(find.text('Solved 63%'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('lists the games, with who won', (tester) async {
      await pumpProfile(tester, client: profileClient());

      await scrollDown(tester);
      await settle(tester, rounds: 2);
      expect(find.text('red-one — black-two'), findsOneWidget);
      // Red won the game: the winner is named by its own side's name.
      expect(find.textContaining('Red'), findsWidgets);
      await drain(tester);
    });

    testWidgets('says so when the account has no games', (tester) async {
      await pumpProfile(tester, client: profileClient(withGames: false));

      await scrollDown(tester);
      await settle(tester, rounds: 2);
      expect(find.text('No games yet.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('offers the way out on the account this device is signed in as', (tester) async {
      await pumpProfile(tester, client: profileClient());

      expect(find.byIcon(Icons.logout), findsOneWidget);
      await drain(tester);
    });

    testWidgets("offers no way out on somebody else's account", (tester) async {
      // Signing out is an action on the session this device holds, and a profile of somebody else
      // has nothing to sign out of. Two tests rather than one screen pumped twice: a second
      // `ProviderScope` over the same element tree keeps the first one's container, so the session
      // would not change and the test would be asserting on the wrong account.
      await pumpProfile(tester, client: profileClient(), sessionName: 'somebody-else');

      expect(find.byIcon(Icons.logout), findsNothing);
      await drain(tester);
    });
  });
}
