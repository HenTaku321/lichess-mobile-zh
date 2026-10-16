// Tests for the screen that lists the games being played on xiangqi.com.
//
// The screen is driven end to end over a stubbed HTTP client: the list, the empty list, the failure,
// and the tap that opens a game. Nothing here is a live host, and nothing here is a live socket
// either — what a row opens is asserted by the route it pushes, and what that route does with the
// game is the online game screen's own tests' business.
//
// One thing about the timing is worth knowing before reading the pumps below. The xiangqi client
// spaces requests to the host by at least `kXiangqiMinRequestSpacing`, and the spacing is measured
// against the real clock rather than the test's, so the request waits out the whole of it however
// fast the test itself is running.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_watch_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// A little over the client's own spacing between two requests to the host.
const _spacing = Duration(milliseconds: 1600);

/// Pumps until nothing more is coming, advancing the clock over the client's spacing.
///
/// Not `pumpAndSettle`: the spacing is a bare timer, which schedules no frame, so settling would
/// return while the request it holds back is still waiting.
Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
  for (var round = 0; round < rounds; round++) {
    await tester.pump(_spacing);
  }
}

/// One seat of a live-list entry, with the fields the endpoint was measured to carry.
Map<String, Object?> seat({
  Object id = 1,
  String username = 'player',
  int? rating = 1500,
  int? seconds = 600,
  int pType = 10,
}) => {
  'id': id,
  'username': username,
  'identity': username,
  'rating': rating,
  'seconds': seconds,
  'p_type': pType,
  'side': 1,
  'factor': 0,
  'result': -10,
  'hidden_username': false,
  'hidden_profile_icon': false,
  'profile_image': null,
  'profile_link_token': null,
  'country': {'name': 'Viet Nam', 'code': 'VN'},
};

/// One entry of the list, with both seats taken unless a case says otherwise.
Map<String, Object?> entry({
  String id = 'AbCdEf1234',
  bool isRated = true,
  int gameTimer = 20,
  int increment = 5,
  int moveTimer = 5,
  int movesCount = 144,
  Map<String, Object?>? red,
  Map<String, Object?>? black,
}) => {
  'id': id,
  'is_rated': isRated,
  'is_timed': true,
  'game_timer': gameTimer,
  'increment': increment,
  'move_timer': moveTimer,
  'moves_count': movesCount,
  'timestamp': '2026-10-16T07:56:58.241092',
  'last_move_time': '2026-10-16T08:37:27.313354',
  'rplayer': red ?? seat(id: 157013, username: 'red-one', rating: 2815, seconds: 423),
  'bplayer': black ?? seat(id: 464493, username: 'black-two', rating: 2869, seconds: 281),
};

/// Records the routes a test navigator pushes.
///
/// These tests care *which* screen a tap opens, and the destination is an online game screen that
/// opens a socket the moment it appears. Recording the route keeps that screen out of the test
/// entirely — a [ScreenRoute] names the widget it builds without building it — so the tap is what is
/// under test and not the screen it lands on.
class _RouteRecorder() extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

/// The widget the last [ScreenRoute] pushed on [recorder] builds.
Widget pushedScreen(_RouteRecorder recorder) {
  final route = recorder.pushed.lastWhere((route) => route is ScreenRoute);
  return (route as ScreenRoute).screen;
}

/// Opens the watch screen over a client that answers `v2/games/active` with [body].
///
/// The app is built by hand rather than through `makeTestProviderScopeApp` for one reason: the
/// shared harness installs its own navigator observer and no others, and a test that wants to read
/// the route a tap pushed has to be the one that owns the navigator.
Future<_RouteRecorder> pumpWatchScreen(
  WidgetTester tester,
  Object? body, {
  int status = 200,
}) async {
  final recorder = _RouteRecorder();
  final client = MockClient(
    (request) async => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json'},
    ),
  );
  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        navigatorObservers: [recorder],
        home: const XiangqiWatchScreen(),
      ),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
      },
    ),
  );
  await settle(tester);
  return recorder;
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiWatchScreen', () {
    testWidgets('lists the games being played, with both seats and the time control', (
      tester,
    ) async {
      await pumpWatchScreen(tester, [entry()]);

      // Both names, both ratings.
      expect(find.text('red-one'), findsOneWidget);
      expect(find.text('2815'), findsOneWidget);
      expect(find.text('black-two'), findsOneWidget);
      expect(find.text('2869'), findsOneWidget);

      // The time control and the move count, in the pairs a player counts: 144 plies is 72 moves.
      expect(find.text('20+5 · 72 moves · Rated'), findsOneWidget);

      // The two clocks, as the server last read them.
      expect(find.text('7:03'), findsOneWidget);
      expect(find.text('4:41'), findsOneWidget);

      // One general per seat, red above black — the order the notation is written in.
      expect(find.byType(XiangqiPieceAvatar), findsNWidgets(2));
    });

    testWidgets('shades the seat that is to move, read from the move count', (tester) async {
      // 144 plies is even, so red is to move.
      await pumpWatchScreen(tester, [entry(movesCount: 144)]);
      expect(_seatOpacity(tester, 'red-one'), 1.0);
      expect(_seatOpacity(tester, 'black-two'), lessThan(1.0));
    });

    testWidgets('a bot seat is badged, and a person is not', (tester) async {
      await pumpWatchScreen(tester, [
        entry(
          red: seat(username: 'a-bot', pType: 30),
          black: seat(username: 'a-person'),
        ),
      ]);

      expect(find.text('BOT'), findsOneWidget);
    });

    testWidgets('a tap opens the game', (tester) async {
      final recorder = await pumpWatchScreen(tester, [entry(id: 'AbCdEf1234')]);

      await tester.tap(find.text('red-one'));
      await tester.pump();

      final screen = pushedScreen(recorder);
      expect(screen, isA<XiangqiOnlineGameScreen>());
      expect((screen as XiangqiOnlineGameScreen).gameId, 'AbCdEf1234');
    });

    testWidgets('says so when nobody is playing', (tester) async {
      await pumpWatchScreen(tester, <Object?>[]);

      expect(find.text('Nobody is playing right now.'), findsOneWidget);
      expect(find.byType(XiangqiPieceAvatar), findsNothing);
    });

    testWidgets('an entry it cannot place is dropped rather than drawn', (tester) async {
      await pumpWatchScreen(tester, [
        entry(
          id: 'AbCdEf1234',
          black: seat(id: '', username: ''),
        ),
        entry(id: 'GhIjKl5678'),
      ]);

      expect(find.text('red-one'), findsOneWidget);
      expect(find.text('black-two'), findsOneWidget);
    });

    testWidgets('a failure offers the way to ask again', (tester) async {
      await pumpWatchScreen(tester, {'error': 'nope'}, status: 500);

      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

/// How opaque the name [name] is drawn.
///
/// The screen shades the seat that is not to move, and the shade is the only thing that tells the
/// two rows apart — the text is the same size and weight either way.
double _seatOpacity(WidgetTester tester, String name) {
  final text = tester.widget<Text>(find.text(name));
  final color = text.style?.color;
  // A null colour is the full-strength one: the row that is to move carries no colour of its own.
  if (color == null) return 1.0;
  return color.a;
}
