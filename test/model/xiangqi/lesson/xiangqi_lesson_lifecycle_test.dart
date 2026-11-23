import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';

import '../../engine/fake_transport.dart';
import '../xiangqi_game_controller_test.dart' as engine_fixture;
import 'xiangqi_lesson_controller_test.dart' as fixture;

class DeferredLessonNnue() extends engine_fixture.LifecyclePikafishNnueService {
  final ready = Completer<String>();

  @override
  Future<String> ensureNnue() => ready.future;
}

void main() {
  for (final interaction in ['tap', 'drag', 'hint']) {
    test('automatic reply owns the board while a $interaction arrives', () async {
      final harness = await fixture.makeHarness(
        fixture.chapter(
          fen: kXiangqiInitialFen,
          steps: [
            fixture.step(null),
            fixture.step('b0c2', nextMove: 'b'),
            fixture.step('b9c7', nextMove: 'r'),
            fixture.step('h2e2', nextMove: 'b'),
          ],
        ),
      );
      final opening = fixture.move('b0c2');
      harness.controller.movePiece(opening.from, opening.to);
      final waiting = harness.state.position;
      switch (interaction) {
        case 'tap':
          harness.controller.tapSquare(fixture.move('b9a7').from);
          harness.controller.tapSquare(fixture.move('b9a7').to);
        case 'drag':
          harness.controller.movePiece(fixture.move('b9c7').from, fixture.move('b9c7').to);
        case 'hint':
          harness.controller.showHint();
      }
      expect(harness.state.cursor, 1);
      expect(harness.state.position, waiting);
      expect(harness.state.selected, isNull);
      expect(harness.state.wrongMove, isNull);
      expect(harness.state.hint, isNull);
      expect(harness.state.isPlayable, isFalse);
      await Future<void>.delayed(kXiangqiLessonReplyDelay + const Duration(milliseconds: 50));
      expect(harness.state.cursor, 2);
      expect(harness.state.acceptedMoves, [opening, fixture.move('b9c7')]);
      expect(harness.state.positions, hasLength(3));
      expect(harness.state.isPlayable, isTrue);
    });
  }

  for (final replied in [false, true]) {
    test('undo removes the last reader move and its automatic reply: $replied', () async {
      final harness = await fixture.makeHarness(
        fixture.chapter(
          fen: kXiangqiInitialFen,
          steps: [
            fixture.step(null),
            fixture.step('b0c2', nextMove: 'b'),
            fixture.step('b9c7', nextMove: 'r'),
            fixture.step('h2e2', nextMove: 'b'),
          ],
        ),
      );
      final opening = fixture.move('b0c2');
      harness.controller.movePiece(opening.from, opening.to);
      if (replied) {
        await Future<void>.delayed(kXiangqiLessonReplyDelay + const Duration(milliseconds: 50));
      }
      harness.controller.undo();
      expect(harness.state.cursor, 0);
      expect(harness.state.acceptedMoves, isEmpty);
      expect(harness.state.positions, [harness.chapter.position]);
      await Future<void>.delayed(kXiangqiLessonReplyDelay + const Duration(milliseconds: 50));
      expect(harness.state.cursor, 0);
      expect(harness.state.isPlayable, isTrue);
    });
  }

  test('a multi chapter retains its engine while NNUE preparation is pending', () async {
    final nnue = DeferredLessonNnue();
    final transports = <FakeTransport>[];
    final container = await engine_fixture.makeEngineLifecycleContainer(transports, nnue: nnue);
    await container.read(xiangqiSessionReadyProvider.future);
    final chapter = fixture.chapter(
      steps: [fixture.step(null), fixture.step('i0i9')],
      answerType: .multi,
    );
    final provider = xiangqiChapterControllerProvider(chapter);
    final watched = container.listen(provider, (_, _) {});
    addTearDown(watched.close);
    final move = fixture.move('i0i4');
    container.read(provider.notifier).movePiece(move.from, move.to);
    await pumpEventQueue();
    expect(container.read(provider).isVerifying, isTrue);
    nnue.ready.complete(nnue.nnueFile.path);
    await pumpEventQueue();
    expect(transports, hasLength(1));
    expect(transports.single.commands, contains('ucinewgame'));
    transports.single.emit('readyok');
    await pumpEventQueue();
    transports.single.emit('bestmove i0i4');
    await pumpEventQueue();
    expect(container.read(provider).isVerifying, isFalse);
    expect(container.read(provider).isSolved, isTrue);
  });

  for (final leave in ['dispose', 'change account']) {
    test('a $leave while NNUE loads cannot launch a late lesson search', () async {
      final nnue = DeferredLessonNnue();
      final transports = <FakeTransport>[];
      final container = await engine_fixture.makeEngineLifecycleContainer(transports, nnue: nnue);
      await container.read(xiangqiSessionReadyProvider.future);
      // A second screen is still waiting for the same shared engine.
      final engineWatcher = container.listen(xiangqiEngineProvider, (_, _) {});
      addTearDown(engineWatcher.close);
      final chapter = fixture.chapter(
        steps: [fixture.step(null), fixture.step('i0i9')],
        answerType: .multi,
      );
      final provider = xiangqiChapterControllerProvider(chapter);
      final watched = container.listen(provider, (_, _) {});
      addTearDown(watched.close);
      final move = fixture.move('i0i4');
      container.read(provider.notifier).movePiece(move.from, move.to);
      await pumpEventQueue();
      if (leave == 'dispose') {
        watched.close();
      } else {
        await container
            .read(xiangqiSessionStoreProvider)
            .write(
              const XiangqiSession(
                userId: 'new-reader',
                name: 'new-reader',
                accessToken: 'new-reader-token',
                isGuest: false,
              ),
            );
      }
      await pumpEventQueue();
      nnue.ready.complete(nnue.nnueFile.path);
      await pumpEventQueue();
      expect(transports, hasLength(1));
      expect(transports.single.commands, isNot(contains('ucinewgame')));
      expect(transports.single.commands.where((command) => command.startsWith('go ')), isEmpty);
      if (leave == 'change account') {
        expect(container.read(provider).cursor, 0);
        expect(container.read(provider).isVerifying, isFalse);
      }
    });
  }

  test(
    'leaving a chapter stops its active search even when another screen holds the engine',
    () async {
      final transports = <FakeTransport>[];
      final container = await engine_fixture.makeEngineLifecycleContainer(transports);
      await container.read(xiangqiSessionReadyProvider.future);
      final engineWatcher = container.listen(xiangqiEngineProvider, (_, _) {});
      addTearDown(engineWatcher.close);
      await container.read(xiangqiEngineProvider.future);
      final chapter = fixture.chapter(
        steps: [fixture.step(null), fixture.step('i0i9')],
        answerType: .multi,
      );
      final provider = xiangqiChapterControllerProvider(chapter);
      final watched = container.listen(provider, (_, _) {});
      addTearDown(watched.close);
      final move = fixture.move('i0i4');
      container.read(provider.notifier).movePiece(move.from, move.to);
      await pumpEventQueue();
      transports.single.emit('readyok');
      await pumpEventQueue();
      expect(
        transports.single.commands.where((command) => command.startsWith('go ')),
        hasLength(1),
      );
      transports.single.takeCommands();
      watched.close();
      await pumpEventQueue();
      expect(transports.single.commands, contains('stop'));
      transports.single.emit('bestmove i0i4');
      await pumpEventQueue();
      expect(container.exists(provider), isFalse);
    },
  );

  test('an engine crash rolls back an unjudged move instead of completing the chapter', () async {
    final transports = <FakeTransport>[];
    final container = await engine_fixture.makeEngineLifecycleContainer(transports);
    await container.read(xiangqiSessionReadyProvider.future);
    final engineWatcher = container.listen(xiangqiEngineProvider, (_, _) {});
    addTearDown(engineWatcher.close);
    await container.read(xiangqiEngineProvider.future);
    final events = <UiEvent>[];
    final errors = container.read(uiEventBusProvider).stream.listen(events.add);
    addTearDown(errors.cancel);
    final chapter = fixture.chapter(
      steps: [fixture.step(null), fixture.step('i0i9')],
      answerType: .multi,
    );
    final provider = xiangqiChapterControllerProvider(chapter);
    final watched = container.listen(provider, (_, _) {});
    addTearDown(watched.close);
    final move = fixture.move('i0i4');
    container.read(provider.notifier).movePiece(move.from, move.to);
    await pumpEventQueue();
    transports.single.emit('readyok');
    await pumpEventQueue();
    transports.single.die(
      const EngineFailure(kind: .runtime, message: 'test crash', engine: 'pikafish'),
    );
    await pumpEventQueue();
    final state = container.read(provider);
    expect(state.isSolved, isFalse);
    expect(state.isVerifying, isFalse);
    expect(state.wrongMove, isNull);
    expect(state.verifyingMove, isNull);
    expect(state.acceptedMoves, isEmpty);
    expect(state.positions, [chapter.position]);
    expect(events.whereType<ShowErrorEvent>(), hasLength(1));
    expect(container.read(xiangqiLessonSaveStateProvider(chapter.id)), XiangqiLessonSaveState.idle);

    container.read(provider.notifier).movePiece(move.from, move.to);
    await pumpEventQueue();
    expect(transports, hasLength(2));
    transports.last.emit('readyok');
    await pumpEventQueue();
    transports.last.emit('bestmove i0i4');
    await pumpEventQueue();
    expect(container.read(provider).isSolved, isTrue);
  });
}
