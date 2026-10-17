import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' show play;

void main() {
  test('a saved game round-trips the position line, challenge settings and clock', () {
    final start = XiangqiPosition.initial();
    final move = XiangqiMove.parseIccs('h2e2')!;
    final after = playXiangqiMove(start, move);
    final state = XiangqiGameState(
      playerSide: XiangqiSide.red,
      difficulty: XiangqiDifficulty.level4,
      positions: IList([start, after]),
      moves: IList([move]),
      timeIncrement: const TimeIncrement(300, 3),
      practiceMode: true,
    );
    final saved = SavedXiangqiGame(
      state: state,
      timeIncrement: const TimeIncrement(300, 3),
      redTimeLeft: const Duration(seconds: 287),
      blackTimeLeft: const Duration(seconds: 300),
    );

    final restored = SavedXiangqiGame.fromJson(saved.toJson());

    expect(restored, isNotNull);
    expect(restored!.state.playerSide, XiangqiSide.red);
    expect(restored.state.difficulty, XiangqiDifficulty.level4);
    expect(restored.state.positions, state.positions);
    expect(restored.state.moves, state.moves);
    expect(restored.state.practiceMode, isTrue);
    expect(restored.timeIncrement, const TimeIncrement(300, 3));
    expect(restored.redTimeLeft, const Duration(seconds: 287));
    expect(restored.blackTimeLeft, const Duration(seconds: 300));
  });
}

XiangqiPosition playXiangqiMove(XiangqiPosition position, XiangqiMove move) {
  // The controller uses the rules' `play`; importing it here keeps the fixture a legal position
  // rather than rebuilding the board by hand.
  return play(position, move);
}
