// Tests for the xiangqi.com identity row of the account menu.
//
// The row has three states — no session, a guest session, a real account — and only the third one
// carries a subtitle. What is under test here is that the first two are untouched and that the
// third draws its ratings and its online/country line when the account lookup answers, and draws
// nothing extra while that lookup is in flight or after it has failed.
//
// The lookup is stubbed at the HTTP layer, per AGENTS.md, so the provider under it is the real one:
// the row is reading a real `xiangqiUserProvider`, over a fake transport.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// The account the real-session fixtures sign in as, and the name the row is titled with.
const xiangqiAccountUsername = '起司ㅤ';

/// The account lookup's answer, in the measured shape: the ratings are plain numbers and the
/// country is a nested object.
Map<String, Object?> xiangqiAccountPayload() => {
  'id': 484155,
  'username': xiangqiAccountUsername,
  'country': const {'id': 226, 'code': 'US', 'name': 'United States'},
  'bullet_rating': 500,
  'rapid_rating': 600,
  'daily_rating': 700,
  'puzzle_rating': 1200,
  'is_online': true,
  'last_online': "b'1788179925'",
  'member_since': 'Tue, 11 Aug 2026 10:46:26 GMT',
};

/// The subtitle the payload above is expected to produce.
///
/// The perf names are the lichess short labels (`Bullet`, `Rapid`, `Corresp.`, `Puzzle`), and the
/// status words are `l10n.online` / `l10n.offline`.
const expectedSubtitle =
    'Bullet 500 · Rapid 600 · Corresp. 700 · Puzzle 1200 · online · United States';

/// The row the xiangqi section drew.
///
/// Found by the one icon every arm of the switch leads with, so a test does not have to know which
/// arm is on screen to read the row it made.
ListTile xiangqiRow(WidgetTester tester) => tester.widget<ListTile>(
  find.ancestor(of: find.byIcon(Icons.grid_on), matching: find.byType(ListTile)),
);

/// The text of [row]'s title.
String titleOf(ListTile row) => (row.title! as Text).data!;

/// The text of [row]'s subtitle, or null when it has none.
String? subtitleOf(ListTile row) => (row.subtitle as Text?)?.data;

/// A session for the row to be built from.
XiangqiSession xiangqiSession({required bool isGuest}) => XiangqiSession(
  userId: '484155',
  name: xiangqiAccountUsername,
  accessToken: fx.xiangqiTestToken('484155'),
  isGuest: isGuest,
);

/// A body encoded as UTF-8 bytes, whatever the headers claim.
///
/// The real server sends UTF-8 with no charset, and `http.Response(body)` would encode a `String`
/// as Latin-1 and throw on the non-ASCII username this fixture uses.
http.Response utf8Response(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status);

/// Pumps the account menu with [session] signed in and [client] answering the account lookup.
///
/// The session store is a fake with no disk behind it — a plain provider, which is what AGENTS.md
/// allows to be overridden directly.
Future<void> pumpAccountMenu(
  WidgetTester tester, {
  required XiangqiSession? session,
  required MockClient client,
}) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const AccountMenuScreen(),
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
          (ref) => fx.FakeXiangqiAuthStorage(session),
        ),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
          return FakeHttpClientFactory(() => client);
        }),
      },
    ),
  );
  // The auth controller restores its session from storage in a microtask; one pump is what lets
  // that land before the row is read.
  await tester.pump();
}

/// A client that answers the account lookup with [response] once it is completed, and 404s
/// everything else.
MockClient pendingAccountClient(Completer<http.Response> response) => MockClient((request) {
  if (request.url.path.startsWith('/api/users/account/')) return response.future;
  return Future.value(utf8Response('', 404));
});

void main() {
  TestLichessBinding.ensureInitialized();

  group('xiangqi identity row', () {
    testWidgets('with no session the row is the way in', (tester) async {
      await pumpAccountMenu(
        tester,
        session: null,
        client: MockClient((request) => Future.value(utf8Response('', 404))),
      );

      final row = xiangqiRow(tester);
      expect(titleOf(row), 'Sign in to xiangqi.com');
      expect(subtitleOf(row), isNull);
      expect(row.onTap, isNotNull);
      expect(row.enabled, isTrue);
    });

    testWidgets('a guest row is unchanged: the guest label and a sign-in button', (tester) async {
      await pumpAccountMenu(
        tester,
        session: xiangqiSession(isGuest: true),
        client: MockClient((request) => Future.value(utf8Response('', 404))),
      );

      final row = xiangqiRow(tester);
      expect(titleOf(row), 'Guest');
      expect(subtitleOf(row), isNull);
      expect(row.trailing, isA<TextButton>());
      expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
      // A guest is not signed in, so there is nothing to sign out of.
      expect(row.onTap, isNull);
    });

    testWidgets('a real account is titled with its name and shows no subtitle while loading', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      await pumpAccountMenu(
        tester,
        session: xiangqiSession(isGuest: false),
        client: pendingAccountClient(response),
      );

      final row = xiangqiRow(tester);
      expect(titleOf(row), xiangqiAccountUsername);
      expect(subtitleOf(row), isNull, reason: 'a profile that has not arrived shows nothing');
      expect(row.enabled, isTrue);
      expect(row.onTap, isNotNull);

      // Let the lookup finish so the test does not end with a pending future.
      response.complete(utf8Response(jsonEncode(xiangqiAccountPayload()), 200));
      await tester.pump();
    });

    testWidgets('a real account shows its ratings and its online/country line', (tester) async {
      await pumpAccountMenu(
        tester,
        session: xiangqiSession(isGuest: false),
        client: MockClient(
          (request) => Future.value(
            request.url.path.startsWith('/api/users/account/')
                ? utf8Response(jsonEncode(xiangqiAccountPayload()), 200)
                : utf8Response('', 404),
          ),
        ),
      );
      await tester.pump();

      expect(subtitleOf(xiangqiRow(tester)), expectedSubtitle);
      // The title is still the session's name, and the row is still a sign-out.
      expect(titleOf(xiangqiRow(tester)), xiangqiAccountUsername);
      expect(xiangqiRow(tester).onTap, isNotNull);
    });

    testWidgets('a real account whose lookup failed shows no subtitle rather than an error', (
      tester,
    ) async {
      await pumpAccountMenu(
        tester,
        session: xiangqiSession(isGuest: false),
        client: MockClient((request) => Future.value(utf8Response('', 500))),
      );
      await tester.pump();

      final row = xiangqiRow(tester);
      expect(titleOf(row), xiangqiAccountUsername);
      expect(subtitleOf(row), isNull);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });
}
