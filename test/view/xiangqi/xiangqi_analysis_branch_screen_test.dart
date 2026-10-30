import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import 'xiangqi_analysis_screen_test.dart' as analysis;

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  testWidgets('a selected sideline can be promoted without losing the old continuation', (
    tester,
  ) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
    // A failed previous route can dispose after its tearDown and save its session again.
    // Each branch-edit scenario explicitly starts from the standard root.
    controller.reset();
    controller.play(analysis.moveAt('h2e2'));
    controller.play(analysis.moveAt('h9g7'));
    controller.play(analysis.moveAt('b0c2'));
    final original = container.read(xiangqiAnalysisControllerProvider).position;
    controller.goTo(1);
    controller.play(analysis.moveAt('g6g5'));
    final sideline = container.read(xiangqiAnalysisControllerProvider).position;
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Promote variation'), findsOneWidget);
    await tester.tap(find.text('Promote variation'));
    await tester.pumpAndSettle();
    expect(container.read(xiangqiAnalysisControllerProvider).position, sideline);
    controller.goTo(1);
    controller.goForward();
    expect(container.read(xiangqiAnalysisControllerProvider).lastMove, analysis.moveAt('g6g5'));
    controller.goBack();
    controller.selectVariation(analysis.moveAt('h9g7'));
    controller.goForward();
    expect(container.read(xiangqiAnalysisControllerProvider).position, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete from here removes only the selected sideline and its descendants', (
    tester,
  ) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
    // A failed previous route can dispose after its tearDown and save its session again.
    // Each branch-edit scenario explicitly starts from the standard root.
    controller.reset();
    controller.play(analysis.moveAt('h2e2'));
    controller.play(analysis.moveAt('h9g7'));
    controller.play(analysis.moveAt('b0c2'));
    final original = container.read(xiangqiAnalysisControllerProvider).position;
    controller.goTo(1);
    controller.play(analysis.moveAt('g6g5'));
    controller.play(analysis.moveAt('b0c2'));
    controller.goBack();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Delete from here'), findsOneWidget);
    await tester.tap(find.text('Delete from here'));
    await tester.pumpAndSettle();
    final state = container.read(xiangqiAnalysisControllerProvider);
    expect(state.cursor, 1);
    expect(state.variations.map((node) => node.move).toList(), [analysis.moveAt('h9g7')]);
    controller.goForward();
    controller.goForward();
    expect(container.read(xiangqiAnalysisControllerProvider).position, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both analysis continuations remain selectable on the board page', (tester) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
    // A failed previous route can dispose after its tearDown and save its session again.
    // Each branch-edit scenario explicitly starts from the standard root.
    controller.reset();
    controller.play(analysis.moveAt('h2e2'));
    controller.play(analysis.moveAt('h9g7'));
    controller.play(analysis.moveAt('b0c2'));
    controller.goTo(1);
    controller.play(analysis.moveAt('g6g5'));
    controller.goBack();
    await tester.pump();

    final mainline = find.byKey(ValueKey(analysis.moveAt('h9g7')));
    final variation = find.byKey(ValueKey(analysis.moveAt('g6g5')));
    expect(mainline, findsOneWidget);
    expect(variation, findsOneWidget);
    await tester.tap(mainline);
    await tester.pump();
    expect(container.read(xiangqiAnalysisControllerProvider).lastMove, analysis.moveAt('h9g7'));
    expect(container.read(xiangqiAnalysisControllerProvider).canGoForward, isTrue);
    controller.goBack();
    await tester.pump();
    await tester.tap(variation);
    await tester.pump();
    expect(container.read(xiangqiAnalysisControllerProvider).lastMove, analysis.moveAt('g6g5'));
    expect(container.read(xiangqiAnalysisControllerProvider).cursor, 2);
  });
}
