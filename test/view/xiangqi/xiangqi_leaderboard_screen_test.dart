// Tests for the screen a xiangqi.com leaderboard is read on.
//
// The screen is driven over a stubbed HTTP client, and the case that matters most is the empty one:
// measured on 2026-10-16, three of the four boards answer with nobody on them, so a screen that
// called that a failure would be reporting a fault where there is none.
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
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_leaderboard_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// A little over the client's own spacing between two requests to the host.
const _spacing = Duration(milliseconds: 1600);

/// Pumps until nothing more is coming, advancing the clock over the client's spacing.
Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
  for (var round = 0; round < rounds; round++) {
    await tester.pump(_spacing);
  }
}

/// One row of a board.
Map<String, Object?> row({required String name, required int rating, int? attempts}) => {
  'rating': rating,
  'challenge_attempts': attempts,
  'win_rate': null,
  'user': {
    'id': 1,
    'username': name,
    'identity': name,
    'rating': null,
    'country': {'name': 'Viet Nam', 'code': 'VN'},
    'hidden_username': false,
    'hidden_profile_icon': false,
    'profile_image': null,
    'profile_link_token': null,
    'locale': 'en',
    'active': true,
    'type': 1,
  },
};

/// A board body, with the meta the endpoint was measured to carry.
Map<String, Object?> board({
  required List<Map<String, Object?>> data,
  int totalPlayers = 0,
  int totalPages = 0,
  int currentPage = 1,
}) => {
  'meta': {
    'total_pages': totalPages,
    'total_players': totalPlayers,
    'current_page': currentPage,
    'user_context': {'is_ranked': false},
  },
  'data': data,
};

/// Opens the leaderboard screen over a client that answers [boards] by `mode`.
Future<void> pumpLeaderboard(
  WidgetTester tester, {
  required Map<String, Object?> Function(String mode) boards,
}) async {
  final client = MockClient((request) async {
    if (request.url.path == '/api/leaders/v2/list') {
      final mode = request.url.queryParameters['mode'] ?? '';
      return http.Response.bytes(
        utf8.encode(jsonEncode(boards(mode))),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    if (request.url.path == '/api/users/countries') {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(const [
            {'code': 'VN', 'name': 'Viet Nam', 'value': 1},
          ]),
        ),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return http.Response('', 404);
  });

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
        home: XiangqiLeaderboardScreen(),
      ),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
          (ref) => fx.FakeXiangqiAuthStorage(
            fx.xiangqiTestSession(fx.xiangqiTestToken(fx.xiangqiTestViewerId)),
          ),
        ),
      },
    ),
  );
  await settle(tester);
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiLeaderboardScreen', () {
    testWidgets('lists the rows with their rank, their rating and their country', (tester) async {
      await pumpLeaderboard(
        tester,
        boards: (mode) => board(
          data: [
            row(name: 'top-one', rating: 4660, attempts: 1962),
            row(name: 'top-two', rating: 4600, attempts: 1500),
          ],
          totalPlayers: 409730,
          totalPages: 27316,
        ),
      );

      expect(find.text('top-one'), findsOneWidget);
      expect(find.text('4660'), findsOneWidget);
      expect(find.text('top-two'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      expect(find.text('409730 players'), findsOneWidget);
    });

    testWidgets('says so, rather than failing, when a board has nobody on it', (tester) async {
      // The rapid, bullet and daily boards all answer exactly this, measured on 2026-10-16.
      await pumpLeaderboard(tester, boards: (mode) => board(data: const []));

      expect(find.text('No players yet.'), findsOneWidget);
      expect(find.text('Something went wrong.'), findsNothing);
    });

    testWidgets('asks for the board of the tab that is open, and not for the others', (
      tester,
    ) async {
      final asked = <String>[];
      await pumpLeaderboard(
        tester,
        boards: (mode) {
          asked.add(mode);
          return board(data: const []);
        },
      );

      // The screen opens on the rapid board, which is the first tab.
      expect(asked, ['rapid']);

      await tester.tap(find.text('Puzzles'));
      await settle(tester);

      expect(asked.last, 'puzzle');
    });

    testWidgets('a board the server refuses offers the way to ask again', (tester) async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(jsonEncode(const {'error': 'nope'})),
          500,
          headers: const {'content-type': 'application/json'},
        ),
      );
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
            home: XiangqiLeaderboardScreen(),
          ),
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (ref) => FakeHttpClientFactory(() => client),
            ),
            xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
              (ref) => fx.FakeXiangqiAuthStorage(
                fx.xiangqiTestSession(fx.xiangqiTestToken(fx.xiangqiTestViewerId)),
              ),
            ),
          },
        ),
      );
      await settle(tester);

      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
