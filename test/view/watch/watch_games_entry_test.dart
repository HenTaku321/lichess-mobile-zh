// Tests for the watch tab's one "Live games" row.
//
// The row is the entry chess and xiangqi share, and the picker behind it is the only thing that
// decides which of the two is watched. What is under test here is therefore the row and the picker:
// the two screens it can open are asserted by the route the tap pushed, and neither of them is
// built.
//
// The tab is mounted on its own rather than through `Application`, which is what the outage tests in
// `watch_tab_screen_test.dart` need and this one does not: nothing here is about the app's startup,
// and a navigator this test owns is what lets it read the route a tap pushed.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/watch/watch_games_hub_screen.dart';
import 'package:lichess_mobile/src/view/watch/watch_tab_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// Records the routes a test navigator pushes.
///
/// These tests care *which* screen a tap opens, and the destination is a screen that fetches the
/// moment it appears. Recording the route keeps that screen out of the test entirely — a
/// [ScreenRoute] names the widget it builds without building it — so the tap is what is under test
/// and not the screen it lands on.
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

/// Pumps the watch tab with a navigator this test owns.
///
/// The platform is pinned to Android so the choice picker takes its Material radio-dialog branch on
/// every host: the iOS branch is an action sheet with its own widget shape, and what is under test
/// here is the tap on a radio.
Future<_RouteRecorder> pumpWatchTab(WidgetTester tester) async {
  final recorder = _RouteRecorder();
  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        navigatorObservers: [recorder],
        home: const WatchTabScreen(),
      ),
      overrides: {
        // Every request this tab makes is answered with an empty list, which each of its sections
        // reads as "nothing to show". None of them is what this file is about.
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) =>
              FakeHttpClientFactory(() => MockClient((request) async => http.Response('[]', 200))),
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
  return recorder;
}

void main() {
  TestLichessBinding.ensureInitialized();

  group("the watch tab's live games row", () {
    testWidgets('opens the dual-source watch page directly', (tester) async {
      final recorder = await pumpWatchTab(tester);

      expect(find.text('Live games'), findsOneWidget);
      await tester.tap(find.text('Live games'));
      await tester.pumpAndSettle();

      expect(pushedScreen(recorder), isA<WatchGamesHubScreen>());
      expect(find.text('Chess'), findsNothing);
      expect(find.text('Xiangqi'), findsNothing);
    });
  });
}
