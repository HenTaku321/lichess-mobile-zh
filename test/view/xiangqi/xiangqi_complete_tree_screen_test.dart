import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';

import '../../binding.dart';
import 'xiangqi_analysis_screen_test.dart' as analysis;

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  testWidgets('a right click opens the same node menu without moving the analysis cursor', (
    tester,
  ) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
    controller.play(analysis.moveAt('h2e2'));
    controller.play(analysis.moveAt('h9g7'));
    await tester.pump();
    final cursor = container.read(xiangqiAnalysisControllerProvider).cursor;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('炮二平五')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Delete from here'), findsOneWidget);
    expect(container.read(xiangqiAnalysisControllerProvider).cursor, cursor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analysis displays the original line and every retained sideline simultaneously', (
    tester,
  ) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
    controller.reset();
    controller.play(analysis.moveAt('h2e2'));
    final parent = container.read(xiangqiAnalysisControllerProvider).position;
    controller.play(analysis.moveAt('h9g7'));
    controller.play(analysis.moveAt('b0c2'));
    controller.goTo(1);
    controller.play(analysis.moveAt('g6g5'));
    controller.play(analysis.moveAt('b0c2'));
    controller.goTo(1);
    controller.play(analysis.moveAt('c6c5'));
    await tester.pump();

    for (final iccs in ['h9g7', 'g6g5', 'c6c5']) {
      expect(
        find.textContaining(xiangqiMoveNotation(parent, analysis.moveAt(iccs))),
        findsOneWidget,
      );
    }
    await tester.tap(find.textContaining(xiangqiMoveNotation(parent, analysis.moveAt('h9g7'))));
    await tester.pump();
    expect(container.read(xiangqiAnalysisControllerProvider).lastMove, analysis.moveAt('h9g7'));
    expect(container.read(xiangqiAnalysisControllerProvider).canGoForward, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the move context menu acts on the pressed branch, not the selected branch', (
    tester,
  ) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
    controller.reset();
    controller.play(analysis.moveAt('h2e2'));
    final parent = container.read(xiangqiAnalysisControllerProvider).position;
    controller.play(analysis.moveAt('h9g7'));
    controller.play(analysis.moveAt('b0c2'));
    controller.goTo(1);
    controller.play(analysis.moveAt('g6g5'));
    controller.goTo(1);
    controller.play(analysis.moveAt('c6c5'));
    final selected = container.read(xiangqiAnalysisControllerProvider).position;
    await tester.pump();
    final original = find.textContaining(xiangqiMoveNotation(parent, analysis.moveAt('h9g7')));
    expect(original, findsOneWidget);
    await tester.longPress(original);
    await tester.pumpAndSettle();
    expect(find.text('Delete from here'), findsOneWidget);
    await tester.tap(find.text('Delete from here'));
    await tester.pumpAndSettle();

    expect(container.read(xiangqiAnalysisControllerProvider).position, selected);
    expect(container.read(xiangqiAnalysisControllerProvider).lastMove, analysis.moveAt('c6c5'));
    expect(original, findsNothing);
    expect(
      find.textContaining(xiangqiMoveNotation(parent, analysis.moveAt('g6g5'))),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
