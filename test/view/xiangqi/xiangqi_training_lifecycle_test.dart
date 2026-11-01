import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lichess_mobile/src/model/puzzle/puzzle_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart'
    show xiangqiEngineProvider;
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lesson_player_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_puzzle_screen.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/puzzle/xiangqi_puzzle_fixture.dart' as fixture;
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage;
import '../../test_provider_scope.dart';
import 'xiangqi_analysis_exit_contract_test.dart' as exits;
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_computer_menu_parity_test.dart' as computer;
import 'xiangqi_lesson_player_screen_test.dart' as lesson;
import 'xiangqi_puzzle_screen_test.dart' as puzzle;
import 'xiangqi_training_history_test.dart' as history;

/// Delay only the first completion. The real HTTP client, parsing and controller still run.
class DeferredTrainingServer(final Completer<http.Response> completion)
    extends puzzle.PuzzleServer {
  @override
  Future<http.Response> answer(http.Request request) {
    if (request.url.path.endsWith('/complete') &&
        !requests.any((previous) => previous.url.path.endsWith('/complete'))) {
      requests.add(request);
      return completion.future;
    }
    return super.answer(request);
  }
}

Future<void> pumpPendingTrainingPuzzle(WidgetTester tester, DeferredTrainingServer server) async {
  final (:engine, :transport) = analysis.fakeXiangqiEngine();
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const XiangqiPuzzleScreen(),
      surfaceSize: const Size(1280, 720),
      failOnOverflow: true,
      defaultPreferences: analysis.evaluationPreferences(isEnabled: false),
      overrides: {
        xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((ref) => engine),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          FakeXiangqiAuthStorage(fixture.xiangqiTestSession),
        ),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => server.client),
        ),
      },
    ),
  );
  await puzzle.settle(tester);
  expect(transport.takeCommands().where((command) => command.startsWith('go ')), isEmpty);
}

Future<void> finishPendingPuzzle(WidgetTester tester) async {
  for (var i = 0; i < fixture.xiangqiTestLine.solution.length; i += 2) {
    final move = fixture.xiangqiTestLine.solution[i];
    await puzzle.tapSquare(tester, move.from.name, orientation: .black);
    await puzzle.tapSquare(tester, move.to.name, orientation: .black);
    await tester.pump(xiangqiPuzzleReplyDelay + const Duration(milliseconds: 1));
  }
  await puzzle.settle(tester, rounds: 2);
  expect(puzzle.attemptState(tester).phase, XiangqiPuzzlePhase.submitting);
}

Finder previousMove() =>
    find.byWidgetPredicate((widget) => widget is HistoryNavigationButton && !widget.forward);

Future<void> returnFromAnalysis(WidgetTester tester) async {
  final element = tester.element(find.byType(XiangqiAnalysisScreen));
  final route = ModalRoute.of(element)!;
  Navigator.of(element).pop();
  await tester.pump();
  await tester.pump(route.reverseTransitionDuration + const Duration(milliseconds: 50));
}

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  testWidgets('temporary verifying and rejected multi moves never enter the accepted history', (
    tester,
  ) async {
    final chapter = history.multiChapter();
    final transport = await history.pumpTrainingLesson(tester, chapter: chapter);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    final provider = xiangqiChapterControllerProvider(chapter);
    final start = container.read(provider).position.toFen();
    await lesson.tapSquare(tester, 'i0');
    await lesson.tapSquare(tester, 'i4');
    await computer.startSearch(tester, transport);
    expect(container.read(provider).isVerifying, isTrue);
    expect(container.read(provider).acceptedMoves, isEmpty);
    expect(container.read(provider).acceptedPositions.single.toFen(), start);
    expect(find.byIcon(Icons.menu), findsNothing);
    transport.emit('info depth 12 multipv 1 score cp 2000 pv i0h0');
    transport.emit('info depth 12 multipv 2 score cp 0 pv i0i4');
    transport.emit('info depth 12 multipv 3 score cp -1000 pv i0g0');
    transport.emit('bestmove i0h0');
    await computer.drain(tester);
    expect(container.read(provider).wrongMove?.iccs, 'i0i4');
    expect(container.read(provider).acceptedMoves, isEmpty);
    expect(container.read(provider).acceptedPositions.single.toFen(), start);
    await tester.pump(kXiangqiLessonWrongMoveDelay);
    expect(container.read(provider).wrongMove, isNull);
    expect(container.read(provider).position.toFen(), start);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'undo after a multi capture truncates the accepted move and exact recorded position',
    (tester) async {
      final chapter = history.multiChapter();
      final transport = await history.pumpTrainingLesson(tester, chapter: chapter);
      final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
      final provider = xiangqiChapterControllerProvider(chapter);
      final start = container.read(provider).position.toFen();
      await history.acceptAlternative(tester, transport);
      await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
      await tester.pump();
      expect(container.read(provider).acceptedMoves, isEmpty);
      expect(container.read(provider).acceptedPositions.map((p) => p.toFen()), [start]);
      expect(container.read(provider).position.toFen(), start);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in [200, 503]) {
    testWidgets('completed puzzle feedback survives a delayed submission with status $status', (
      tester,
    ) async {
      final completion = Completer<http.Response>();
      final server = DeferredTrainingServer(completion);
      await pumpPendingTrainingPuzzle(tester, server);
      await finishPendingPuzzle(tester);
      final before = puzzle.attemptState(tester);
      final feedbackBefore = find.text('Success!').evaluate().length;
      await tester.tap(previousMove());
      await tester.pump();
      expect(puzzle.attemptState(tester), before);
      expect(
        puzzle.board(tester).position.toFen(),
        before.positions[before.moves.length - 1].toFen(),
      );
      completion.complete(http.Response('{"p_rating":1833,"status":4}', status));
      await puzzle.settle(tester, rounds: 2);
      expect(
        puzzle.attemptState(tester).phase,
        status == 200 ? XiangqiPuzzlePhase.recorded : XiangqiPuzzlePhase.unrecorded,
      );
      expect(puzzle.attemptState(tester).moves, before.moves);
      expect(
        puzzle.board(tester).position.toFen(),
        before.positions[before.moves.length - 1].toFen(),
      );
      expect(
        server.requests.where((request) => request.url.path.endsWith('/complete')),
        hasLength(1),
      );
      expect(feedbackBefore, 1, reason: 'The local solve verdict must not wait for the network.');
      expect(find.text('Success!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('analysis while submitting prevents automatic next and does not submit on return', (
    tester,
  ) async {
    final completion = Completer<http.Response>();
    final server = DeferredTrainingServer(completion);
    await pumpPendingTrainingPuzzle(tester, server);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    await container.read(puzzlePreferencesProvider.notifier).setAutoNext(true);
    await finishPendingPuzzle(tester);
    final solved = puzzle.attemptState(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analysis board'));
    await exits.finishRoute(tester, find.byType(XiangqiAnalysisScreen, skipOffstage: false));
    completion.complete(http.Response('{"p_rating":1833,"status":4}', 200));
    await puzzle.settle(tester, rounds: 2);
    await returnFromAnalysis(tester);
    await puzzle.settle(tester, rounds: 2);
    expect(puzzle.attemptState(tester).phase, XiangqiPuzzlePhase.recorded);
    expect(puzzle.attemptState(tester).moves, solved.moves);
    expect(
      server.requests.where((request) => request.url.path.endsWith('/complete')),
      hasLength(1),
    );
    expect(
      server.requests.where((request) => request.url.path == '/api/puzzle/search'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson history viewing cancels automatic chapter advance even after a late save', (
    tester,
  ) async {
    final completion = Completer<http.Response>();
    final chapter = lesson.chapter(
      fen: history.trainingFen,
      autoTransition: true,
      steps: IList([lesson.step(null), lesson.step('i0i4', nextMove: 'b')]),
    );
    final requests = <http.Request>[];
    await history.pumpTrainingLesson(
      tester,
      chapter: chapter,
      followingChapters: IList([lesson.chapter(id: 'next', order: 2, description: 'Next chapter')]),
      requests: requests,
      answer: (_) => completion.future,
    );
    await lesson.tapSquare(tester, 'i0');
    await lesson.tapSquare(tester, 'i4');
    await tester.tap(previousMove());
    await tester.pump(kXiangqiLessonAutoTransitionDelay + const Duration(milliseconds: 1));
    completion.complete(http.Response('{}', 200));
    await puzzle.settle(tester, rounds: 2);
    expect(find.text('Chapter 1 of 2'), findsOneWidget);
    expect(
      tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position.toFen(),
      history.trainingFen,
    );
    expect(requests.where((request) => request.url.path.endsWith('/complete')), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a completed lesson menu cannot hand off the previous account after a session change',
    (tester) async {
      final chapter = history.multiChapter();
      final transport = await history.pumpTrainingLesson(tester, chapter: chapter);
      await history.acceptAlternative(tester, transport);
      final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await container
          .read(xiangqiSessionStoreProvider)
          .write(fixture.xiangqiTestSession.copyWith(userId: '200002', name: 'another-player'));
      await tester.pump();
      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();
      expect(find.byType(XiangqiAnalysisScreen), findsNothing);
      expect(find.byType(XiangqiLessonPlayerScreen), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
