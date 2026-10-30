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

  testWidgets('both analysis continuations remain selectable on the board page', (tester) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
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
