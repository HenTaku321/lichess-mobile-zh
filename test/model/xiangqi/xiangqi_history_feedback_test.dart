import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

const firstVerdict = XiangqiPracticeComment(
  verdict: MoveVerdict.goodMove,
  bestMove: null,
  evaluation: null,
  suggestionNotation: null,
  evalAfter: '+0.2',
);
const lastVerdict = XiangqiPracticeComment(
  verdict: MoveVerdict.mistake,
  bestMove: null,
  evaluation: null,
  suggestionNotation: null,
  evalAfter: '-1.0',
);

void main() {
  final moves = [
    'h2e2',
    'h9g7',
    'b0c2',
    'b9c7',
  ].map((iccs) => XiangqiMove.parseIccs(iccs)!).toIList();
  final positions = <XiangqiPosition>[XiangqiPosition.initial()];
  for (final move in moves) {
    positions.add(rules.play(positions.last, move));
  }

  for (final side in XiangqiSide.values) {
    final firstPly = side == XiangqiSide.red ? 1 : 2;
    final lastPly = firstPly + 2;
    final game = XiangqiGameState(
      playerSide: side,
      difficulty: XiangqiDifficulty.level4,
      positions: positions.lock,
      moves: moves,
      practiceMode: true,
      practiceComments: IMap({firstPly: firstVerdict, lastPly: lastVerdict}),
    );

    test('historical feedback follows the displayed position for $side', () {
      for (var cursor = 0; cursor < firstPly; cursor++) {
        expect(game.copyWith(cursor: cursor).practiceComment, isNull);
      }
      expect(game.copyWith(cursor: firstPly).practiceComment, firstVerdict);
      expect(game.copyWith(cursor: firstPly + 1).practiceComment, firstVerdict);
      expect(game.copyWith(cursor: lastPly).practiceComment, lastVerdict);
    });

    test('historical pending feedback never reads a verdict from a later move for $side', () {
      expect(game.copyWith(cursor: firstPly).previousPracticeComment, firstVerdict);
      expect(game.copyWith(cursor: 0).previousPracticeComment, isNull);
    });
  }
}
