import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_options.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_computer_menu_parity_test.dart' as computer;
import 'xiangqi_game_screen_test.dart' as game;

Future<void> finishRoute(WidgetTester tester, Finder screen) async {
  await tester.pump();
  final route = ModalRoute.of(tester.element(screen))!;
  await tester.pump();
  await tester.pump(route.transitionDuration + const Duration(milliseconds: 50));
  await tester.pump();
  expect(route.animation!.status, AnimationStatus.completed);
}

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  testWidgets('the analysis menu offers independent continuation at its selected position', (
    tester,
  ) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    final controller = root.read(xiangqiAnalysisControllerProvider.notifier);
    controller.play(analysis.moveAt('h2e2'));
    controller.play(analysis.moveAt('h9g7'));
    final before = root.read(xiangqiAnalysisControllerProvider);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Continue from here'), findsOneWidget);
    await tester.tap(find.text('Continue from here'));
    await tester.pumpAndSettle();
    expect(find.text('Play against computer'), findsOneWidget);
    expect(find.text('Over the board'), findsOneWidget);
    await tester.tap(find.text('Over the board'));
    await finishRoute(tester, find.byType(XiangqiOverTheBoardScreen, skipOffstage: false));
    await tester.tap(find.text('Play'));
    await tester.pump();
    final child = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard).last));
    expect(child.read(xiangqiGameControllerProvider).gamePosition, before.position);
    expect(child.read(xiangqiGameControllerProvider).opponent, XiangqiOpponent.human);
    expect(child.read(xiangqiGameControllerProvider).moves, isEmpty);
    expect(root.read(xiangqiAnalysisControllerProvider).variationTree, same(before.variationTree));
    expect(tester.takeException(), isNull);
  });

  testWidgets('restricted analysis does not expose editor, continuation or export exits', (
    tester,
  ) async {
    final (:engine, :transport) = analysis.fakeXiangqiEngine();
    final options = XiangqiAnalysisOptions.line(
      sourceId: 'ongoing-read-only',
      initialPosition: XiangqiPosition.initial(),
      moves: const IListConst([]),
      engineAllowed: false,
    );
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: XiangqiAnalysisScreen(options: options),
        overrides: {xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((ref) => engine)},
        defaultPreferences: analysis.evaluationPreferences(isEnabled: true),
        failOnOverflow: true,
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Board editor'), findsNothing);
    expect(find.text('Continue from here'), findsNothing);
    expect(find.textContaining('Copy to clipboard'), findsNothing);
    expect(transport.takeCommands().where((command) => command.startsWith('go ')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final otb in [false, true]) {
    testWidgets('a new local $otb route cannot overwrite the suspended parent game or clock', (
      tester,
    ) async {
      await game.pumpGameScreen(tester, screen: computer.screen, failOnOverflow: true);
      final root = game.containerOf(tester);
      final controller = root.read(xiangqiGameControllerProvider.notifier);
      controller.movePiece(game.squareAt('h2'), game.squareAt('e2'));
      await tester.pump();
      controller.suspendForAnalysis();
      root
          .read(xiangqiClockProvider.notifier)
          .setupClock(
            const TimeIncrement(300, 3),
            redTimeLeft: const Duration(seconds: 123),
            blackTimeLeft: const Duration(seconds: 234),
          );
      final original = root.read(xiangqiGameControllerProvider);
      final clock = root.read(xiangqiClockProvider);
      const fen = '3k5/9/9/9/9/9/9/9/9/4K4 w - - 0 1';
      final navigator = Navigator.of(tester.element(find.byType(XiangqiGameScreen)));
      navigator.push(
        otb
            ? XiangqiOverTheBoardScreen.buildRoute(initialFen: fen)
            : XiangqiGameScreen.buildRoute(initialFen: fen),
      );
      await finishRoute(
        tester,
        (otb
                ? find.byType(XiangqiOverTheBoardScreen, skipOffstage: false)
                : find.byType(XiangqiGameScreen, skipOffstage: false))
            .last,
      );
      await tester.tap(find.text('Play'));
      await tester.pump();
      final child = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard).last));
      expect(child.read(xiangqiGameControllerProvider).gamePosition.toFen(), fen);
      expect(root.read(xiangqiGameControllerProvider).gamePosition, original.gamePosition);
      expect(root.read(xiangqiGameControllerProvider).moves, original.moves);
      expect(root.read(xiangqiClockProvider).redTimeLeft, clock.redTimeLeft);
      expect(root.read(xiangqiClockProvider).blackTimeLeft, clock.blackTimeLeft);
      expect(tester.takeException(), isNull);
    });
  }
}
