import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';

import 'xiangqi_analysis_controller_test.dart' as analysis;
import 'xiangqi_game_controller_test.dart' as game;

void main() {
  test('a game drag does not reinterpret the existing selection', () async {
    final harness = await game.makeHarness();
    harness.controller.tapSquare(game.square('h2'));
    harness.controller.movePiece(game.square('h2'), game.square('e2'));
    expect(harness.state.moves, [game.move('h2e2')]);
    expect(harness.state.selected, isNull);
    expect(harness.controller.lastMoveViaDrag, isTrue);
  });

  test('an illegal drag leaves the game unchanged', () async {
    final harness = await game.makeHarness();
    final before = harness.state.position;
    harness.controller.movePiece(game.square('a0'), game.square('a9'));
    expect(harness.state.position, before);
    expect(harness.state.moves, isEmpty);
  });

  test('an analysis drag commits its origin instead of the previously selected piece', () async {
    clearSavedXiangqiAnalysis();
    addTearDown(clearSavedXiangqiAnalysis);
    final harness = await analysis.makeHarness();
    harness.notifier.tapSquare(game.square('h2'));
    harness.notifier.movePiece(game.square('a3'), game.square('a4'));
    expect(harness.state.moves, [game.move('a3a4')]);
    expect(harness.state.selected, isNull);
  });
}
