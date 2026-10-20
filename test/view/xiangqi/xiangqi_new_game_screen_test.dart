// Tests for the screen a game on xiangqi.com is set up on.
//
// The screen is driven over a stubbed HTTP client, and what is pinned is the panel: the same
// arrangement of the same widgets the chess lobby uses — see `create_game_widget.dart` — with the
// settings the two games do not share replaced. The values are invented; the shapes come from
// `xiangqi-com-re/docs/game.md`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/view/play/common_play_widgets.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_new_game_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// The session store, in memory — the real one is secure storage, which this test never touches.
class FakeNewGameStorage([var XiangqiSession? session]) implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession value) async => session = value;

  @override
  Future<void> delete() async => session = null;
}

/// A signed-in account, which is what the panel is behind.
const _session = XiangqiSession(
  userId: '100001',
  name: 'a-player',
  accessToken: 'stored-token',
  isGuest: false,
);

/// The bodies the two ways in answer with.
String _bodyFor(String path) => switch (path) {
  '/api/v2/games/quick-challenge' => '{"message": "Successfully scheduled request"}',
  '/api/games/check-challenge-status' => '{"message": "Search in progress..."}',
  '/api/games/cancel-quick-challenge' => '{}',
  _ => '{"game_id": "AbCdEfGhIj"}',
};

/// Opens the screen over a client that answers [handler], falling back to the happy path.
Future<List<(String, String)>> pumpNewGame(
  WidgetTester tester, {
  Future<http.Response?> Function(http.Request)? handler,
}) async {
  final sent = <(String, String)>[];
  final client = MockClient((request) async {
    // Connectivity probes are not traffic this screen produced.
    if (internetCheckUris.contains(request.url)) return http.Response('', 200);
    sent.add((request.url.path, request.body));
    final custom = handler == null ? null : await handler(request);
    if (custom != null) return custom;
    return http.Response(_bodyFor(request.url.path), 200);
  });

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const XiangqiNewGameScreen(),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
          (ref) => FakeNewGameStorage(_session),
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
  return sent;
}

/// The control labelled [label], which is how a setting is found: its label is above it and its
/// value is on it.
PlaySetupButton setupButton(WidgetTester tester, String label) => tester
    .widgetList<PlaySetupButton>(find.byType(PlaySetupButton))
    .firstWhere((button) => button.label == label);

/// The outlined button of the control labelled [label].
///
/// The control's *value* and the panel's action button can say the same thing — a quick match is
/// both what the opponent control is set to and what the button at the bottom does — so a control
/// is reached by its label and the button inside it, never by the text on it.
Finder setupButtonOf(String label) => find.descendant(
  of: find.byWidgetPredicate((widget) => widget is PlaySetupButton && widget.label == label),
  matching: find.byType(OutlinedButton),
);

/// Opens the control labelled [label] and picks [value] out of the picker it shows.
Future<void> choose(WidgetTester tester, String label, String value) async {
  await tester.tap(setupButtonOf(label));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(value)));
  await tester.pumpAndSettle();
}

void main() {
  group('XiangqiNewGameScreen', () {
    testWidgets('sets a game up with the same panel the chess lobby uses', (tester) async {
      await pumpNewGame(tester);

      // The same widget the chess panel is built from, in the same arrangement: a row of labelled
      // buttons over a full-width action button.
      expect(find.byType(PlaySetupButton), findsNWidgets(2));
      expect(setupButton(tester, 'Opponent').value, 'Quick game');
      expect(setupButton(tester, 'Clock').value, '10 + 0');
      expect(find.widgetWithText(FilledButton, 'Quick game'), findsOneWidget);

      // A quick match is a time control and nothing else, so the settings only a game of your own
      // has are not on screen.
      expect(find.text('Side'), findsNothing);
      expect(find.text('Game mode'), findsNothing);
      expect(find.text('Private'), findsNothing);
    });

    testWidgets('asks for the rest of the settings once the game is your own', (tester) async {
      await pumpNewGame(tester);

      await choose(tester, 'Opponent', 'Create a game');

      expect(find.byType(PlaySetupButton), findsNWidgets(4));
      expect(setupButton(tester, 'Side').value, 'Random side');
      expect(setupButton(tester, 'Game mode').value, 'Casual');
      // The one setting that is a yes or a no, drawn the way this app draws every other one.
      expect(find.text('Private'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create a game'), findsOneWidget);
    });

    testWidgets('creates the game the panel is set to', (tester) async {
      final sent = await pumpNewGame(tester);

      await choose(tester, 'Opponent', 'Create a game');
      // The clock: 15 + 5, which is the one control whose config string carries an increment.
      await choose(tester, 'Clock', '15 + 5');
      // The side, and the mode.
      await choose(tester, 'Side', 'Red');
      await choose(tester, 'Game mode', 'Rated');

      await tester.tap(find.widgetWithText(FilledButton, 'Create a game'));
      await tester.pumpAndSettle();

      final body = jsonDecode(
        sent.lastWhere((request) => request.$1 == '/api/v2/games/create-custom').$2,
      );
      expect(body, {
        'is_rated': true,
        'is_private': true,
        'is_daily': false,
        'is_timed': true,
        'side': 1,
        'opponent': null,
        'opponent_email': null,
        'rating_diff': 'Any',
        'move_time': 2,
        'game_time': 15,
        'increment': 5,
      });
    });

    testWidgets('asks to be queued with the clock alone for a quick match', (tester) async {
      final sent = await pumpNewGame(tester);

      await choose(tester, 'Clock', '5 + 0');

      await tester.tap(find.widgetWithText(FilledButton, 'Quick game'));
      await tester.pumpAndSettle();

      // One field, and it is the clock's own string — the server pairs on nothing else.
      final quick = sent.firstWhere((request) => request.$1 == '/api/v2/games/quick-challenge');
      expect(jsonDecode(quick.$2), {'config_str': '5/1'});

      // The screen then waits for an opponent, and gives up after a dozen rounds. Giving up
      // cancels the match: one left in the pool would pair the account with somebody after the
      // screen that asked for it had gone. The stub never pairs, so that is what happens here.
      for (var round = 0; round < xiangqiQuickMatchRounds; round++) {
        await tester.pump(kXiangqiQuickMatchPollInterval);
        await tester.pump(kXiangqiQuickMatchPollInterval);
      }
      await tester.pumpAndSettle();
      expect(sent.map((request) => request.$1), contains('/api/games/cancel-quick-challenge'));
    });
  });
}
