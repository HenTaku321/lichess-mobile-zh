import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/review/xiangqi_review_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_database_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/database/xiangqi_master_game_test.dart' as master;
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' as auth;
import '../../test_provider_scope.dart';
import 'xiangqi_analysis_exit_contract_test.dart' as exits;
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_desktop_pages_test.dart' as desktop;
import 'xiangqi_over_the_board_screen_test.dart' as otb;
import 'xiangqi_review_screen_test.dart' as review;

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  testWidgets('master-game analysis transfers the whole history, cursor and orientation', (
    tester,
  ) async {
    final (:engine, :transport) = analysis.fakeXiangqiEngine();
    final client = MockClient((request) async {
      if (request.url.path != '/api/master-games/games/a-vs-b') return http.Response('', 404);
      return http.Response.bytes(
        utf8.encode(jsonEncode(master.game(moves: ['h2e2', 'h9g7', 'b0c2']))),
        200,
        headers: const {'Content-Type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(1280, 720),
        failOnOverflow: true,
        home: const XiangqiMasterGameScreen(slug: 'a-vs-b'),
        defaultPreferences: analysis.evaluationPreferences(isEnabled: false),
        overrides: {
          xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((ref) => engine),
          xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
            auth.FakeXiangqiAuthStorage(auth.signedInSession),
          ),
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(() => client),
          ),
        },
      ),
    );
    await desktop.settleDesktop(tester);
    expect(find.byType(XiangqiBoard), findsOneWidget);
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    final standalone = root.listen(xiangqiAnalysisControllerProvider, (_, _) {});
    addTearDown(standalone.close);
    root.read(xiangqiAnalysisControllerProvider.notifier).play(analysis.moveAt('h2e2'));

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is HistoryNavigationButton && widget.forward),
    );
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.arrow_2_squarepath));
    await tester.pump();
    final before = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    expect(before.orientation, XiangqiSide.black);
    await tester.tap(
      find.descendant(of: find.byType(BottomBar), matching: find.byIcon(Icons.menu)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Analysis board'));
    await tester.pump();
    final route = ModalRoute.of(
      tester.element(find.byType(XiangqiAnalysisScreen, skipOffstage: false)),
    )!;
    await tester.pump(route.transitionDuration + const Duration(milliseconds: 50));

    expect(find.byType(XiangqiAnalysisScreen), findsOneWidget);
    final scoped = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    final state = scoped.read(xiangqiAnalysisControllerProvider);
    expect(state.positions.first, XiangqiPosition.initial());
    expect(state.moves.map((move) => move.iccs), ['h2e2', 'h9g7', 'b0c2']);
    expect(state.cursor, 1);
    expect(state.position, before.position);
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, before.orientation);
    expect(root.read(xiangqiAnalysisControllerProvider).moves, hasLength(1));
    expect(transport.takeCommands().where((command) => command.startsWith('go ')), isEmpty);
    Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
    await tester.pump();
    await tester.pump(route.reverseTransitionDuration + const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position, before.position);
    expect(root.read(xiangqiAnalysisControllerProvider).moves, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('finished OTB analysis transfers all moves, the visible cursor and orientation', (
    tester,
  ) async {
    await otb.pumpOtbScreen(tester, surfaceSize: const Size(1280, 720), failOnOverflow: true);
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    if (root.read(engineEvaluationPreferencesProvider).isEnabled) {
      await root.read(engineEvaluationPreferencesProvider.notifier).toggle();
    }
    final controller = root.read(xiangqiGameControllerProvider.notifier);
    for (final iccs in ['h2e2', 'h9g7', 'b0c2']) {
      final move = analysis.moveAt(iccs);
      controller.movePiece(move.from, move.to);
    }
    controller.resign();
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    controller.goTo(1);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flip board'));
    await tester.pumpAndSettle();
    final before = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    final game = root.read(xiangqiGameControllerProvider);
    final clock = root.read(xiangqiClockProvider);
    expect(before.orientation, XiangqiSide.black);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Analysis'), findsOneWidget);
    await tester.tap(find.text('Analysis'));
    await exits.finishRoute(tester, find.byType(XiangqiAnalysisScreen, skipOffstage: false));

    final scoped = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    final state = scoped.read(xiangqiAnalysisControllerProvider);
    expect(state.positions, game.positions);
    expect(state.moves, game.moves);
    expect(state.cursor, game.viewCursor);
    expect(state.position, before.position);
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, before.orientation);
    final route = ModalRoute.of(tester.element(find.byType(XiangqiAnalysisScreen)))!;
    Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
    await tester.pump();
    await tester.pump(route.reverseTransitionDuration + const Duration(milliseconds: 50));
    await tester.pump();
    expect(root.read(xiangqiGameControllerProvider).moves, game.moves);
    expect(root.read(xiangqiGameControllerProvider).viewCursor, game.viewCursor);
    expect(root.read(xiangqiClockProvider).redTimeLeft, clock.redTimeLeft);
    expect(root.read(xiangqiClockProvider).blackTimeLeft, clock.blackTimeLeft);
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, before.orientation);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unfinished OTB menus keep the finished-game analysis exit unavailable', (
    tester,
  ) async {
    await otb.pumpOtbScreen(tester, failOnOverflow: true);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Analysis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review analysis transfers the displayed history without requesting review again', (
    tester,
  ) async {
    final (:engine, :transport) = analysis.fakeXiangqiEngine();
    final factory = await review.pumpReview(tester, engine: engine, failOnOverflow: true);
    await review.loadReview(tester, factory);
    final root = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    if (root.read(engineEvaluationPreferencesProvider).isEnabled) {
      await root.read(engineEvaluationPreferencesProvider.notifier).toggle();
    }
    final gameId = review.snapshotPayload()['id']! as String;
    final reviewed = root.read(xiangqiReviewProvider(gameId)).value!;
    final requests = factory.channel.sent
        .whereType<String>()
        .where((frame) => frame.contains('"g_v2.review"'))
        .length;
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is HistoryNavigationButton && !widget.forward),
    );
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.arrow_2_squarepath));
    await tester.pump();
    final before = review.board(tester);
    expect(before.orientation, XiangqiSide.black);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analysis board'));
    await exits.finishRoute(tester, find.byType(XiangqiAnalysisScreen, skipOffstage: false));

    final scoped = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));
    final state = scoped.read(xiangqiAnalysisControllerProvider);
    expect(state.positions, reviewed.positions);
    expect(state.moves, reviewed.moves);
    expect(state.cursor, reviewed.moves.length - 1);
    expect(state.position, before.position);
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, before.orientation);
    expect(
      factory.channel.sent.whereType<String>().where((frame) => frame.contains('"g_v2.review"')),
      hasLength(requests),
    );
    expect(transport.takeCommands().where((command) => command.startsWith('go ')), isEmpty);
    final route = ModalRoute.of(tester.element(find.byType(XiangqiAnalysisScreen)))!;
    Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
    await tester.pump();
    await tester.pump(route.reverseTransitionDuration + const Duration(milliseconds: 50));
    await tester.pump();
    expect(review.board(tester).position, before.position);
    expect(review.board(tester).orientation, before.orientation);
    expect(tester.takeException(), isNull);
  });
}
