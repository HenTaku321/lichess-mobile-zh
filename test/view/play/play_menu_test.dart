import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/offline_computer/computer_game_screen.dart';
import 'package:lichess_mobile/src/view/over_the_board/over_the_board_screen.dart';
import 'package:lichess_mobile/src/view/play/play_bottom_sheet.dart';
import 'package:lichess_mobile/src/view/play/play_menu.dart';
import 'package:lichess_mobile/src/view/play/tournaments_hub_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

/// Records the routes a test navigator pushes and pops.
///
/// These tests only care *which* screen a tap opens, and all four screens are reachable through a
/// [ScreenRoute], whose [ScreenRoute.screen] names the widget without building it. Recording the
/// route keeps the destination — an engine-backed game screen, with a sheet of its own on startup —
/// out of the test entirely, so the tap is what is under test and not the screen it lands on.
class _RouteRecorder() extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  /// The route each entry of [pushed] was pushed onto.
  ///
  /// This is what tells whether the play bottom sheet was still in the stack when the destination
  /// went up: a push that happened before the sheet was popped would name the sheet here.
  final pushedOnto = <Route<dynamic>?>[];

  /// Every route the navigator popped, in order.
  final popped = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    pushedOnto.add(previousRoute);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
    super.didPop(route, previousRoute);
  }
}

/// The index of the last [ScreenRoute] among [recorder]'s pushes.
///
/// Deliberately not simply the last push: a destination may open a sheet of its own the moment it
/// appears — the offline computer game screen does — and that sheet is pushed after the screen.
int _lastScreenPushIndex(_RouteRecorder recorder) {
  final index = recorder.pushed.lastIndexWhere((route) => route is ScreenRoute);
  expect(index, isNot(-1), reason: 'no route was pushed');
  return index;
}

/// The widget the last [ScreenRoute] pushed on [recorder] builds.
Widget pushedScreen(_RouteRecorder recorder) {
  final index = _lastScreenPushIndex(recorder);
  final route = recorder.pushed[index];
  expect(route, isA<ScreenRoute>(), reason: 'pushed route is a ${route.runtimeType}');
  return (route as ScreenRoute).screen;
}

/// The route the last [ScreenRoute] was pushed onto.
Route<dynamic>? pushedScreenOnto(_RouteRecorder recorder) =>
    recorder.pushedOnto[_lastScreenPushIndex(recorder)];

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

/// Pumps [PlayMenu] the way the app really reaches it: inside a modal bottom sheet on the root
/// navigator, with a home screen underneath.
///
/// This is the shape the pop is for. [pumpPlayMenu] mounts the menu as the app's `home`, where
/// there is no sheet route above it and `popUntil` has nothing to do; here the sheet is real, so a
/// tap that fails to pop it leaves the destination stacked on top of it.
Future<_RouteRecorder> pumpPlayMenuInSheet(WidgetTester tester) async {
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
      home: Scaffold(body: Builder(builder: (context) => const FloatingPlayButton())),
    ),
    overrides: {
      engineAvailabilityProvider: engineAvailabilityProvider.overrideWith(
        (ref) => EngineAvailability.phone,
      ),
    },
  );
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();

  await tester.tap(find.byType(FloatingPlayButton));
  await tester.pumpAndSettle();
  expect(find.byType(PlayMenu), findsOneWidget, reason: 'the sheet should be open');

  return recorder;
}

void main() {
  group('PlayMenu', () {
    testWidgets('Play against computer opens one setup screen, with no game picker', (
      tester,
    ) async {
      final recorder = await pumpPlayMenu(tester, pikafish: true);

      await tester.tap(find.text('Play against computer'));
      await tester.pumpAndSettle();

      expect(pushedScreen(recorder), isA<ComputerGameScreen>());
      expect(find.text('Chess'), findsNothing);
      expect(find.text('Xiangqi'), findsNothing);
    });

    testWidgets('Over the board opens its setup screen directly', (tester) async {
      final recorder = await pumpPlayMenu(tester, pikafish: false);

      await tester.tap(find.text('Over the board'));
      await tester.pumpAndSettle();

      expect(pushedScreen(recorder), isA<OverTheBoardScreen>());
      expect(find.text('Chess'), findsNothing);
      expect(find.text('Xiangqi'), findsNothing);
    });

    testWidgets('Tournaments opens the dual-source hub directly', (tester) async {
      final recorder = await pumpPlayMenu(tester, pikafish: true);

      await tester.tap(find.text('Arena tournaments'));
      await tester.pumpAndSettle();

      expect(pushedScreen(recorder), isA<TournamentsHubScreen>());
      expect(find.text('Chess'), findsNothing);
      expect(find.text('Xiangqi'), findsNothing);
    });

    group('reached from the play bottom sheet', () {
      testWidgets('the sheet is popped before the computer screen goes up', (tester) async {
        final recorder = await pumpPlayMenuInSheet(tester);
        expect(recorder.pushed.last, isA<ModalBottomSheetRoute<void>>());
        expect(recorder.pushedOnto.last, isA<MaterialPageRoute<dynamic>>());

        await tester.tap(find.text('Play against computer'));
        await tester.pumpAndSettle();

        expect(find.byType(PlayMenu), findsNothing);
        expect(recorder.popped.whereType<ModalBottomSheetRoute<void>>(), isNotEmpty);
        expect(pushedScreen(recorder), isA<ComputerGameScreen>());
      });

      testWidgets('the OTB screen is pushed onto the screen the sheet covered', (tester) async {
        final recorder = await pumpPlayMenuInSheet(tester);

        await tester.tap(find.text('Over the board'));
        await tester.pumpAndSettle();

        expect(pushedScreen(recorder), isA<OverTheBoardScreen>());
        expect(pushedScreenOnto(recorder), isNot(isA<ModalBottomSheetRoute<void>>()));
        expect(pushedScreenOnto(recorder), isA<MaterialPageRoute<dynamic>>());
      });
    });
  });
}
