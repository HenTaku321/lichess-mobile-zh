import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart'
    show xiangqiEngineProvider;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lesson_player_screen.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/engine/fake_transport.dart';
import '../../model/xiangqi/puzzle/xiangqi_puzzle_fixture.dart' as fixture;
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage;
import '../../service/fake_sound_service.dart';
import '../../test_provider_scope.dart';
import 'xiangqi_analysis_exit_contract_test.dart' as exits;
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_computer_menu_parity_test.dart' as computer;
import 'xiangqi_lesson_player_screen_test.dart' as lesson;
import 'xiangqi_puzzle_screen_test.dart' as puzzle;

const trainingFen = '3k5/9/9/9/9/8p/9/9/9/4K3R w - - 0 1';

class RecordingTrainingSound() extends FakeSoundService {
  final events = <Sound>[];
  @override
  Future<void> play(Sound sound, {double? volume}) async => events.add(sound);
  @override
  Future<void> playCaptureSound(Variant variant, {double? volume}) async =>
      events.add(Sound.capture);
}

Future<FakeTransport> pumpTrainingLesson(
  WidgetTester tester, {
  required XiangqiChapter chapter,
  RecordingTrainingSound? sound,
  List<http.Request>? requests,
}) async {
  final (:engine, :transport) = analysis.fakeXiangqiEngine();
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      surfaceSize: const Size(1280, 720),
      failOnOverflow: true,
      defaultPreferences: analysis.evaluationPreferences(isEnabled: false),
      home: XiangqiLessonPlayerScreen(
        lessonId: 'TrainingHistoryLesson',
        lessonTitle: 'Training history',
        chapters: IList([chapter]),
        initialIndex: 0,
      ),
      overrides: {
        xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((ref) => engine),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          FakeXiangqiAuthStorage(fixture.xiangqiTestSession),
        ),
        if (sound != null) soundServiceProvider: soundServiceProvider.overrideWithValue(sound),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(
            () => MockClient((request) async {
              requests?.add(request);
              return http.Response('{}', request.url.path.endsWith('/complete') ? 200 : 404);
            }),
          ),
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
  return transport;
}

XiangqiChapter multiChapter() => XiangqiChapter(
  id: 'TrainingMulti',
  order: 1,
  description: 'A quiet script move with an accepted capture alternative',
  position: XiangqiPosition.fromFen(trainingFen),
  steps: IList([lesson.step(null), lesson.step('i0h0', nextMove: 'b')]),
  answerType: .multi,
  isCompleted: false,
);

Future<void> acceptAlternative(WidgetTester tester, FakeTransport transport) async {
  await lesson.tapSquare(tester, 'i0');
  await lesson.tapSquare(tester, 'i4');
  await computer.startSearch(tester, transport);
  transport.emit('info depth 12 multipv 1 score cp 100 pv i0i4');
  transport.emit('info depth 12 multipv 2 score cp 95 pv i0h0');
  transport.emit('info depth 12 multipv 3 score cp 90 pv i0g0');
  transport.emit('bestmove i0i4');
  await computer.drain(tester);
  await puzzle.settle(tester);
  expect(find.text('Great job!'), findsOneWidget);
}

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  for (final aspect in ['notation', 'last move', 'capture feedback']) {
    testWidgets('a multi lesson uses the accepted move for $aspect rather than its script', (
      tester,
    ) async {
      final sound = RecordingTrainingSound();
      final transport = await pumpTrainingLesson(tester, chapter: multiChapter(), sound: sound);
      await acceptAlternative(tester, transport);
      switch (aspect) {
        case 'notation':
          expect(find.textContaining('车一进四'), findsOneWidget);
          expect(find.textContaining('车一平二'), findsNothing);
        case 'last move':
          expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).lastMove?.iccs, 'i0i4');
        case 'capture feedback':
          expect(sound.events, [Sound.capture]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'consecutive red teaching steps remain visible without changing their recorded turn',
    (tester) async {
      final chapter = lesson.chapter(
        fen: trainingFen,
        steps: IList([
          lesson.step(null),
          lesson.step('i0i1', nextMove: 'b'),
          lesson.step('i1i2', nextMove: 'b'),
        ]),
      );
      await pumpTrainingLesson(tester, chapter: chapter);
      await lesson.tapSquare(tester, 'i0');
      await lesson.tapSquare(tester, 'i1');
      await lesson.tapSquare(tester, 'i1');
      await lesson.tapSquare(tester, 'i2');
      expect(find.text('Great job!'), findsOneWidget);
      expect(find.textContaining('车一进一'), findsNWidgets(2));
      expect(
        tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position.turn,
        XiangqiSide.black,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a completed multi lesson hands the accepted history to analysis and keeps its save',
    (tester) async {
      final requests = <http.Request>[];
      final transport = await pumpTrainingLesson(
        tester,
        chapter: multiChapter(),
        requests: requests,
      );
      await acceptAlternative(tester, transport);
      final before = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
      expect(find.byIcon(Icons.menu), findsOneWidget);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analysis board'));
      await exits.finishRoute(tester, find.byType(XiangqiAnalysisScreen, skipOffstage: false));
      final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
      final state = container.read(xiangqiAnalysisControllerProvider);
      expect(state.moves.map((move) => move.iccs), ['i0i4']);
      expect(state.position.toFen(), before.position.toFen());
      expect(
        tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation,
        before.orientation,
      );
      final route = ModalRoute.of(tester.element(find.byType(XiangqiAnalysisScreen)))!;
      Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
      await tester.pump();
      await tester.pump(route.reverseTransitionDuration + const Duration(milliseconds: 50));
      await puzzle.settle(tester);
      expect(find.text('Great job!'), findsOneWidget);
      expect(requests.where((request) => request.url.path.endsWith('/complete')), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed puzzle history navigation does not change or resubmit the solved attempt',
    (tester) async {
      final server = puzzle.PuzzleServer();
      await puzzle.pumpPuzzleScreen(tester, server: server, failOnOverflow: true);
      await puzzle.playTheLine(tester);
      final solved = puzzle.attemptState(tester);
      final backwards = find.byWidgetPredicate(
        (widget) => widget is HistoryNavigationButton && !widget.forward,
      );
      expect(backwards, findsOneWidget);
      await tester.tap(backwards);
      await tester.pump();
      expect(
        puzzle.board(tester).position.toFen(),
        solved.positions[solved.positions.length - 2].toFen(),
      );
      expect(puzzle.attemptState(tester), solved);
      expect(
        server.requests.where((request) => request.url.path.endsWith('/complete')),
        hasLength(1),
      );
      expect(
        server.requests.where((request) => request.url.path == '/api/puzzle/search'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
