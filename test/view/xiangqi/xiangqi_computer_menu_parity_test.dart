import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_difficulty_tile.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/engine/fake_transport.dart';
import 'xiangqi_game_screen_test.dart' as game;

const screen = XiangqiGameScreen(
  initialSide: .red,
  initialDifficulty: .level4,
  initialTimeIncrement: TimeIncrement.infinite(),
);

Future<void> drain(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue(times: 2));
  await tester.pump();
}

/// Acknowledge only real readiness requests, and require an actual search command.
Future<List<String>> startSearch(WidgetTester tester, FakeTransport transport) async {
  final observed = <String>[];
  for (var i = 0; i < 5; i++) {
    await drain(tester);
    final commands = transport.takeCommands();
    observed.addAll(commands);
    if (commands.any((command) => command.startsWith('go '))) return observed;
    if (commands.contains('isready')) transport.emit('readyok');
  }
  fail('No real search started: $observed');
}

Future<void> openAnalysis(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Analysis board'));
  await tester.pump();
  final route = ModalRoute.of(
    tester.element(find.byType(XiangqiAnalysisScreen, skipOffstage: false)),
  )!;
  await tester.pump(route.transitionDuration + const Duration(milliseconds: 50));
  await drain(tester);
  expect(find.byType(XiangqiBoard), findsOneWidget);
}

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(() {
    const channel = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      channel,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    addTearDown(() => messenger.setMockMessageHandler(channel, null));
  });

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    for (final practiceMode in [false, true]) {
      testWidgets('computer title reflects the actual mode: $locale / practice=$practiceMode', (
        tester,
      ) async {
        await game.pumpGameScreen(
          tester,
          locale: locale,
          screen: XiangqiGameScreen(
            initialSide: .red,
            initialDifficulty: .level4,
            initialTimeIncrement: const TimeIncrement.infinite(),
            initialPracticeMode: practiceMode,
          ),
          failOnOverflow: true,
        );
        final appBar = find.byType(AppBar);
        final context = tester.element(appBar);
        final title = practiceMode
            ? context.l10n.practiceWithComputer
            : context.l10n.playAgainstComputer;
        expect(
          game.containerOf(tester).read(xiangqiGameControllerProvider).practiceMode,
          practiceMode,
        );
        expect(find.descendant(of: appBar, matching: find.text(title)), findsOneWidget);
        expect(
          find.descendant(of: appBar, matching: find.byTooltip(context.l10n.settingsSettings)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('repeated settings activation does not leave a second sheet underneath', (
    tester,
  ) async {
    await game.pumpGameScreen(tester, screen: screen, failOnOverflow: true);
    final controller = game.containerOf(tester).read(xiangqiGameControllerProvider.notifier);
    final generation = controller.generation;
    final settings = tester.widget<IconButton>(
      find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Settings'),
    );
    // Replay the actual callback twice before the next frame disables or obscures the button.
    final activate = settings.onPressed!;
    activate();
    activate();
    await tester.pumpAndSettle();
    final difficulty = find.byType(XiangqiDifficultyTile);
    expect(difficulty, findsOneWidget);
    Navigator.of(tester.element(difficulty)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(XiangqiDifficultyTile), findsNothing);
    activate();
    await tester.pumpAndSettle();
    expect(find.byType(XiangqiDifficultyTile), findsOneWidget);
    Navigator.of(tester.element(find.byType(XiangqiDifficultyTile))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(XiangqiDifficultyTile), findsNothing);
    expect(
      controller.generation,
      generation,
      reason: 'Inspecting settings must not replace the game.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('computer actions use the same menu, resign, takeback and hint order as chess', (
    tester,
  ) async {
    await game.pumpGameScreen(tester, screen: screen, failOnOverflow: true);
    final buttons = tester.widgetList<BottomBarButton>(find.byType(BottomBarButton)).toList();
    expect(buttons.map((button) => button.icon), [
      Icons.menu,
      CupertinoIcons.flag,
      CupertinoIcons.arrow_uturn_left,
      CupertinoIcons.lightbulb,
    ]);
  });

  testWidgets('analysis pauses a pending reply, ignores its late result and resumes once', (
    tester,
  ) async {
    final transport = await game.pumpGameScreen(tester, screen: screen, failOnOverflow: true);
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    await game.tapSquare(tester, 'h2');
    await game.tapSquare(tester, 'e2');
    await startSearch(tester, transport);
    expect(root.read(xiangqiGameControllerProvider).isEngineThinking, isTrue);
    expect(root.read(xiangqiGameControllerProvider).moves, hasLength(1));

    await openAnalysis(tester);
    expect(find.byType(XiangqiAnalysisScreen), findsOneWidget);
    expect(root.read(xiangqiGameControllerProvider).isEngineThinking, isFalse);
    expect(transport.takeCommands(), contains('stop'));
    transport.emit('bestmove h9g7');
    await drain(tester);
    expect(root.read(xiangqiGameControllerProvider).moves, hasLength(1));

    Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final resumed = await startSearch(tester, transport);
    expect(resumed.where((command) => command.startsWith('go ')), hasLength(1));
    expect(root.read(xiangqiGameControllerProvider).isEngineThinking, isTrue);
    transport.emit('bestmove h9g7');
    await drain(tester);
    expect(root.read(xiangqiGameControllerProvider).moves, hasLength(2));
    expect(root.read(xiangqiGameControllerProvider).isEngineThinking, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the computer result dialog offers analysis of the finished game', (tester) async {
    final transport = await game.pumpGameScreen(tester, screen: screen, failOnOverflow: true);
    await tester.tap(find.byIcon(CupertinoIcons.flag));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(XiangqiGameResultDialog), findsOneWidget);
    expect(find.text('Analysis board'), findsOneWidget);
    await tester.tap(find.text('Analysis board'));
    await tester.pump();
    final route = ModalRoute.of(
      tester.element(find.byType(XiangqiAnalysisScreen, skipOffstage: false)),
    )!;
    await tester.pump(route.transitionDuration + const Duration(milliseconds: 50));
    expect(find.byType(XiangqiAnalysisScreen), findsOneWidget);
    expect(transport.takeCommands().where((command) => command.startsWith('go ')), isEmpty);
  });

  testWidgets('a stopped analysis search cannot cancel the resumed opponent search', (
    tester,
  ) async {
    final transport = await game.pumpGameScreen(
      tester,
      screen: screen,
      engineEvaluation: true,
      settle: false,
      failOnOverflow: true,
    );
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    await startSearch(tester, transport);
    transport.emit('bestmove h2e2');
    await drain(tester);
    await game.tapSquare(tester, 'h2');
    await game.tapSquare(tester, 'e2');
    await startSearch(tester, transport);
    await openAnalysis(tester);
    transport.emit('bestmove h9g7');
    await drain(tester);
    final studying = await startSearch(tester, transport);
    expect(studying, contains('go infinite'));
    expect(root.read(xiangqiGameControllerProvider).moves, hasLength(1));
    Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await drain(tester);
    expect(transport.takeCommands(), contains('stop'));
    transport.emit('bestmove h9g7'); // Finish the stopped analysis, not the resumed game.
    await drain(tester);
    expect(root.read(xiangqiGameControllerProvider).moves, hasLength(1));
    final resumed = await startSearch(tester, transport);
    expect(resumed.where((command) => command.startsWith('go ')), hasLength(1));
    expect(resumed, isNot(contains('go infinite')));
    transport.emit('bestmove h9g7');
    await drain(tester);
    expect(root.read(xiangqiGameControllerProvider).moves, hasLength(2));
  });

  testWidgets('returning from analysis resumes the unfinished practice assessment first', (
    tester,
  ) async {
    final transport = await game.pumpGameScreen(
      tester,
      screen: const XiangqiGameScreen(
        initialSide: .red,
        initialDifficulty: .level4,
        initialTimeIncrement: TimeIncrement.infinite(),
        initialPracticeMode: true,
      ),
      failOnOverflow: true,
    );
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    await game.tapSquare(tester, 'h2');
    await game.tapSquare(tester, 'e2');
    expect(await startSearch(tester, transport), contains('go depth 9'));
    expect(root.read(xiangqiGameControllerProvider).isEvaluatingMove, isTrue);
    await openAnalysis(tester);
    transport.emit('bestmove b2e2');
    await drain(tester);
    Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await startSearch(tester, transport), contains('go depth 9'));
    expect(root.read(xiangqiGameControllerProvider).isEvaluatingMove, isTrue);
    transport.emit('info depth 9 score cp 20 pv b2e2');
    transport.emit('bestmove b2e2');
    await drain(tester);
    expect(await startSearch(tester, transport), contains('go depth 9'));
    transport.emit('info depth 9 score cp -30 pv h9g7');
    transport.emit('bestmove h9g7');
    await drain(tester);
    final feedback = root.read(xiangqiGameControllerProvider).practiceComment;
    expect(feedback, isNotNull);
    await startSearch(tester, transport);
    transport.emit('bestmove h9g7');
    await drain(tester);
    expect(root.read(xiangqiGameControllerProvider).moves, hasLength(2));
    expect(root.read(xiangqiGameControllerProvider).practiceComment, same(feedback));
  });

  testWidgets('analysis pauses and restores the same remaining clocks rather than resetting them', (
    tester,
  ) async {
    final transport = await game.pumpGameScreen(
      tester,
      screen: const XiangqiGameScreen(
        initialSide: .red,
        initialDifficulty: .level4,
        initialTimeIncrement: TimeIncrement(300, 3),
      ),
      settle: false,
      failOnOverflow: true,
    );
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    root
        .read(xiangqiClockProvider.notifier)
        .setupClock(
          const TimeIncrement(300, 3),
          redTimeLeft: const Duration(seconds: 120),
          blackTimeLeft: const Duration(seconds: 150),
        );
    root.read(xiangqiClockProvider.notifier).resume(.red);
    await game.tapSquare(tester, 'h2');
    await game.tapSquare(tester, 'e2');
    await startSearch(tester, transport);
    await openAnalysis(tester);
    final paused = root.read(xiangqiClockProvider);
    expect(paused.activeClock, isNull);
    transport.emit('bestmove h9g7');
    await drain(tester);
    Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await startSearch(tester, transport);
    final restored = root.read(xiangqiClockProvider);
    expect(restored.activeClock, XiangqiSide.black);
    expect((restored.redTimeLeft! - paused.redTimeLeft!).inMilliseconds.abs(), lessThan(250));
    expect((restored.blackTimeLeft! - paused.blackTimeLeft!).inMilliseconds.abs(), lessThan(250));
    transport.emit('bestmove h9g7');
    await drain(tester);
  });
}
