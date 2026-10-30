import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
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
  await tester.tap(find.text('Analysis'));
  await tester.pump(const Duration(milliseconds: 400));
  await drain(tester);
}

void main() {
  TestLichessBinding.ensureInitialized();

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
}
