import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

import 'xiangqi_game_controller_test.dart' as game;

Future<void> score(game.XiangqiHarness harness, int cp, String move) async {
  await pumpEventQueue();
  harness.transport.emit('readyok');
  await pumpEventQueue();
  harness.transport.emit('info depth 9 score cp $cp pv $move');
  await pumpEventQueue();
  harness.transport.emit('bestmove $move');
  await pumpEventQueue();
}

void main() {
  for (final side in XiangqiSide.values) {
    test('$side feedback survives the reply until the next legal player move', () async {
      final harness = await game.makeHarness();
      harness.controller.startNewGame(side: side, difficulty: .level4, practiceMode: true);
      if (side == .black) await game.answer(harness.transport, 'h2e2');
      final played = game.move(side == .red ? 'h2e2' : 'h9g7');
      harness.controller.tapSquare(played.from);
      harness.controller.tapSquare(played.to);
      await score(harness, 20, side == .red ? 'b2e2' : 'b9c7');
      final reply = side == .red ? 'h9g7' : 'h0g2';
      await score(harness, -30, reply);
      final comment = harness.state.practiceComment;
      expect(comment, isNotNull);

      await game.answer(harness.transport, reply);
      expect(harness.state.practiceComment, same(comment));
      final origin = game.square(side == .red ? 'a3' : 'a6');
      harness.controller.tapSquare(origin);
      expect(harness.state.practiceComment, same(comment));
      harness.controller.tapSquare(game.square(side == .red ? 'a5' : 'a4'));
      expect(harness.state.practiceComment, same(comment));
      harness.controller.tapSquare(origin);
      harness.controller.tapSquare(game.square(side == .red ? 'a4' : 'a5'));
      expect(harness.state.isEvaluatingMove, isTrue);
      expect(harness.state.practiceComment, isNull);
    });
  }

  for (final afterPreSearch in [false, true]) {
    test('undo cancels practice evaluation, after pre-search: $afterPreSearch', () async {
      final harness = await game.makeHarness();
      harness.controller.startNewGame(side: .red, difficulty: .level4, practiceMode: true);
      harness.controller.tapSquare(game.square('h2'));
      harness.controller.tapSquare(game.square('e2'));
      if (afterPreSearch) await score(harness, 20, 'b2e2');
      await pumpEventQueue();
      harness.transport.emit('readyok');
      await pumpEventQueue();
      harness.transport.takeCommands();

      harness.controller.undo();
      expect(harness.state.isEvaluatingMove, isFalse);
      expect(harness.state.moves, isEmpty);
      expect(harness.transport.takeCommands(), contains('stop'));
      harness.transport.emit('info depth 9 score cp 300 pv h9g7');
      harness.transport.emit('bestmove h9g7');
      await pumpEventQueue();
      expect(harness.state.practiceComment, isNull);
      expect(harness.state.isEngineThinking, isFalse);
      expect(harness.state.moves, isEmpty);
    });
  }

  test('resigning while scoring clears temporary practice state', () async {
    final harness = await game.makeHarness();
    harness.controller.startNewGame(side: .red, difficulty: .level4, practiceMode: true);
    harness.controller.tapSquare(game.square('h2'));
    harness.controller.tapSquare(game.square('e2'));
    harness.controller.resign();
    expect(harness.state.isEvaluatingMove, isFalse);
    expect(harness.state.end, XiangqiGameEnd.resign);
  });

  test('a new game retains its time control but resets the old clocks', () async {
    final harness = await game.makeHarness();
    harness.controller.startNewGame(
      side: .red,
      difficulty: .level4,
      timeIncrement: const TimeIncrement(300, 3),
    );
    harness.container
        .read(xiangqiClockProvider.notifier)
        .setupClock(
          const TimeIncrement(300, 3),
          redTimeLeft: const Duration(seconds: 20),
          blackTimeLeft: const Duration(seconds: 30),
        );
    harness.controller.startNewGame(side: .red, difficulty: .level6);
    final clock = harness.container.read(xiangqiClockProvider);
    expect(clock.timeIncrement, const TimeIncrement(300, 3));
    expect(clock.redTimeLeft, const Duration(seconds: 300));
    expect(clock.blackTimeLeft, const Duration(seconds: 300));
    expect(clock.activeClock, isNull);
    expect(clock.flagSide, isNull);
  });

  test('restoring a pending move clears scoring state and asks for one reply', () async {
    final harness = await game.makeHarness();
    harness.controller.startNewGame(side: .red, difficulty: .level4, practiceMode: true);
    harness.controller.tapSquare(game.square('h2'));
    harness.controller.tapSquare(game.square('e2'));
    final pending = harness.state;
    harness.controller.restoreGame(game: pending, timeIncrement: const TimeIncrement.infinite());
    expect(harness.state.isEvaluatingMove, isFalse);
    expect(harness.state.isEngineThinking, isTrue);
    await game.answer(harness.transport, 'h9g7');
    expect(harness.state.moves.length, 2);
  });

  test('practice feedback survives a trip to saved-game JSON', () async {
    final harness = await game.makeHarness();
    harness.controller.startNewGame(side: .red, difficulty: .level4, practiceMode: true);
    harness.controller.tapSquare(game.square('h2'));
    harness.controller.tapSquare(game.square('e2'));
    await score(harness, 20, 'b2e2');
    await score(harness, -30, 'h9g7');
    final saved = SavedXiangqiGame(
      state: harness.state,
      timeIncrement: const TimeIncrement.infinite(),
    );
    final restored = SavedXiangqiGame.fromJson(saved.toJson());
    expect(restored, isNotNull);
    expect(restored!.state.practiceComment, isNotNull);
    expect(restored.state.practiceComment!.bestMove, harness.state.practiceComment!.bestMove);
    expect(restored.state.practiceComment!.verdict, harness.state.practiceComment!.verdict);

    final legacy = saved.toJson()..remove('practiceComments');
    expect(SavedXiangqiGame.fromJson(legacy)!.state.practiceComment, isNull);
    final damagedFeedback = saved.toJson();
    damagedFeedback['practiceComments'] = [
      {'ply': 99, 'verdict': 'blunder', 'cp': 50},
      {'ply': 1, 'verdict': 'mistake', 'cp': 'not-a-score'},
    ];
    final damaged = SavedXiangqiGame.fromJson(damagedFeedback);
    expect(damaged, isNotNull);
    expect(damaged!.state.positions, harness.state.positions);
    expect(damaged.state.practiceComment, isNull);
  });

  test('undo restores the surviving prior verdict instead of the removed move', () async {
    final harness = await game.makeHarness();
    harness.controller.startNewGame(side: .red, difficulty: .level4, practiceMode: true);
    harness.controller.tapSquare(game.square('h2'));
    harness.controller.tapSquare(game.square('e2'));
    await score(harness, 20, 'b2e2');
    await score(harness, -30, 'h9g7');
    await game.answer(harness.transport, 'h9g7');
    final first = harness.state.practiceComment;
    harness.controller.tapSquare(game.square('a3'));
    harness.controller.tapSquare(game.square('a4'));
    expect(harness.state.previousPracticeComment, same(first));
    await score(harness, 20, 'h0g2');
    await score(harness, -300, 'b9c7');
    await game.answer(harness.transport, 'b9c7');
    expect(harness.state.practiceComment, isNot(same(first)));
    harness.controller.undo();
    expect(harness.state.practiceComment, same(first));
    expect(harness.state.practiceComments.keys, [1]);
    harness.controller.startNewGame(side: .red, difficulty: .level4, practiceMode: true);
    expect(harness.state.practiceComment, isNull);
    expect(harness.state.previousPracticeComment, isNull);
  });

  test('corrupt saved history is refused rather than silently dropping bad moves', () async {
    final harness = await game.makeHarness();
    harness.controller.startNewGame(side: .red, difficulty: .level4);
    harness.controller.tapSquare(game.square('h2'));
    harness.controller.tapSquare(game.square('e2'));
    final json = SavedXiangqiGame(
      state: harness.state,
      timeIncrement: const TimeIncrement.infinite(),
    ).toJson();
    json['moves'] = ['not-a-move'];
    expect(SavedXiangqiGame.fromJson(json), isNull);
  });
}
