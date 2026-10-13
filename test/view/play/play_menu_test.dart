import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/over_the_board/over_the_board_screen.dart';
import 'package:lichess_mobile/src/view/play/play_menu.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

/// Records the routes a test navigator pushes.
///
/// These tests only care *which* screen a tap opens, and all four screens are reachable through a
/// [ScreenRoute], whose [ScreenRoute.screen] names the widget without building it. Recording the
/// route keeps the destination — an engine-backed game screen, with a sheet of its own on startup —
/// out of the test entirely, so the tap is what is under test and not the screen it lands on.
class _RouteRecorder() extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

/// The widget the last route pushed on [recorder] builds, asserted to be a [ScreenRoute].
Widget pushedScreen(_RouteRecorder recorder) {
  expect(recorder.pushed, isNotEmpty, reason: 'no route was pushed');
  final route = recorder.pushed.last;
  expect(route, isA<ScreenRoute>(), reason: 'pushed route is a ${route.runtimeType}');
  return (route as ScreenRoute).screen;
}

/// Pumps [PlayMenu] on its own inside a [MaterialApp] whose navigator records pushed routes.
///
/// [pikafish] is what the build ships as far as xiangqi goes: true for a build with Pikafish, false
/// for one without. It is read through [engineAvailabilityProvider] rather than a binding because
/// the provider is not a network provider and is the exact switch `PlayMenu` consults.
///
/// The platform is pinned to Android so the choice picker takes its Material radio-dialog branch on
/// every host: the iOS branch is an action sheet with its own widget shape, and this wave is about
/// the tap on a radio the Material dialog used to swallow.
Future<_RouteRecorder> pumpPlayMenu(WidgetTester tester, {required bool pikafish}) async {
  final recorder = _RouteRecorder();
  final app = await makeTestProviderScope(
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
      home: const Scaffold(body: PlayMenu()),
    ),
    overrides: {
      engineAvailabilityProvider: engineAvailabilityProvider.overrideWith(
        (ref) => pikafish ? EngineAvailability.phone : EngineAvailability.none,
      ),
    },
  );
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return recorder;
}

void main() {
  group('PlayMenu', () {
    group('Play against the computer', () {
      testWidgets('offers both games where the build has Pikafish', (tester) async {
        await pumpPlayMenu(tester, pikafish: true);

        await tester.tap(find.text('Play against computer'));
        await tester.pumpAndSettle();

        expect(find.text('Chess'), findsOneWidget);
        expect(find.text('Xiangqi'), findsOneWidget);
      });

      testWidgets('offers chess and not xiangqi where the build has no Pikafish', (tester) async {
        await pumpPlayMenu(tester, pikafish: false);

        // The row itself must survive a build without Pikafish: the gate is on the choices, not on
        // the entry, so a phone that cannot play xiangqi still offers chess against the computer.
        expect(find.text('Play against computer'), findsOneWidget);

        await tester.tap(find.text('Play against computer'));
        await tester.pumpAndSettle();

        expect(find.text('Chess'), findsOneWidget);
        expect(find.text('Xiangqi'), findsNothing);
      });

      testWidgets('tapping chess opens the offline computer game screen', (tester) async {
        final recorder = await pumpPlayMenu(tester, pikafish: true);

        await tester.tap(find.text('Play against computer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chess'));

        expect(pushedScreen(recorder), isA<OfflineComputerGameScreen>());
      });

      testWidgets('tapping xiangqi opens the xiangqi game screen', (tester) async {
        final recorder = await pumpPlayMenu(tester, pikafish: true);

        await tester.tap(find.text('Play against computer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xiangqi'));

        expect(pushedScreen(recorder), isA<XiangqiGameScreen>());
      });
    });

    group('Over the board', () {
      testWidgets('offers both games even where the build has no Pikafish', (tester) async {
        await pumpPlayMenu(tester, pikafish: false);

        await tester.tap(find.text('Over the board'));
        await tester.pumpAndSettle();

        // Both sides of an over-the-board game are a person's, so this row is not gated on the
        // engine the way the computer row is: a build without Pikafish plays this one as well.
        expect(find.text('Chess'), findsOneWidget);
        expect(find.text('Xiangqi'), findsOneWidget);
      });

      testWidgets('tapping chess opens the over the board screen', (tester) async {
        final recorder = await pumpPlayMenu(tester, pikafish: false);

        await tester.tap(find.text('Over the board'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chess'));

        expect(pushedScreen(recorder), isA<OverTheBoardScreen>());
      });

      testWidgets('tapping xiangqi opens the xiangqi over the board screen', (tester) async {
        final recorder = await pumpPlayMenu(tester, pikafish: false);

        await tester.tap(find.text('Over the board'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xiangqi'));

        expect(pushedScreen(recorder), isA<XiangqiOverTheBoardScreen>());
      });
    });
  });
}
