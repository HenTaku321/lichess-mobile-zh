import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
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
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_desktop_pages_test.dart' as desktop;

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
}
