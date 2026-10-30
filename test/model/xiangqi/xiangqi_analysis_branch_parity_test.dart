import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';

import 'xiangqi_analysis_controller_test.dart' as analysis;

void main() {
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  test('a new continuation does not destroy the original mainline', () async {
    final harness = await analysis.makeHarness();
    final controller = harness.notifier;
    controller.play(analysis.move('h2e2'));
    controller.play(analysis.move('h9g7'));
    controller.play(analysis.move('b0c2'));
    final original = harness.state.position;

    controller.goTo(1);
    controller.play(analysis.move('g6g5'));
    expect(harness.state.lastMove, analysis.move('g6g5'));
    controller.goTo(1);
    controller.goForward();
    expect(harness.state.lastMove, analysis.move('h9g7'));
    expect(harness.state.canGoForward, isTrue);
    controller.goForward();
    expect(harness.state.position, original);
  });

  test('playing an existing continuation keeps its future moves', () async {
    final harness = await analysis.makeHarness();
    final controller = harness.notifier;
    controller.play(analysis.move('h2e2'));
    controller.play(analysis.move('h9g7'));
    controller.play(analysis.move('b0c2'));
    final original = harness.state.position;

    controller.goTo(1);
    controller.play(analysis.move('h9g7'));
    expect(harness.state.cursor, 2);
    expect(harness.state.canGoForward, isTrue);
    controller.goForward();
    expect(harness.state.position, original);
  });
}
