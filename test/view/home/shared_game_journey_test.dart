import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/view/home/home_tab_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';
import '../xiangqi/xiangqi_analysis_screen_test.dart' as analysis;
import '../xiangqi/xiangqi_game_screen_test.dart' as game;

// Only the filesystem boundary is replaced. Read the installed release's record through the
// production decoder each time so a return visit cannot reuse the first route's controller.
class _LegacySlot(var Map<String, dynamic>? record) implements XiangqiGameStorage {
  @override
  Future<SavedXiangqiGame?> fetchGame() async =>
      record == null ? null : SavedXiangqiGame.fromJson(record!);

  @override
  Future<void> save(SavedXiangqiGame game) async => record = game.toJson();

  @override
  Future<void> delete() async => record = null;
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('home resumes a legacy computer game, saves a played turn and reviews the result', (
    tester,
  ) async {
    final initial = XiangqiPosition.initial();
    final first = rules.play(initial, game.moveAt('h2e2'));
    final second = rules.play(first, game.moveAt('h9g7'));
    final slot = _LegacySlot({
      'playerSide': 'red',
      'difficulty': 'level3',
      'positions': [initial.toFen(), first.toFen(), second.toFen()],
      'moves': ['h2e2', 'h9g7'],
      'timeIncrement': {'time': 0, 'increment': 0},
    });
    final (:engine, :transport) = analysis.fakeXiangqiEngine();
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const HomeTabScreen(),
        surfaceSize: const Size(1280, 720),
        failOnOverflow: true,
        defaultPreferences: analysis.evaluationPreferences(isEnabled: false),
        overrides: {
          engineAvailabilityProvider: engineAvailabilityProvider.overrideWithValue(
            EngineAvailability.phone,
          ),
          xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((ref) => engine),
          xiangqiGameStorageProvider: xiangqiGameStorageProvider.overrideWith((ref) => slot),
        },
      ),
    );
    await tester.pumpAndSettle();
    final resume = find.byKey(const ValueKey('home-computer-xiangqi'));
    expect(resume, findsOneWidget);
    expect(find.descendant(of: resume, matching: find.text('Resume')), findsOneWidget);
    expect(find.text('About Lichess...'), findsNothing);
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    XiangqiBoard board() => tester.widget<XiangqiBoard>(find.byType(XiangqiBoard).last);
    expect(board().position, second);
    await game.tapSquare(tester, 'b0');
    await game.tapSquare(tester, 'c2');
    await game.answer(tester, transport, 'b9c7');
    final played = rules.play(rules.play(second, game.moveAt('b0c2')), game.moveAt('b9c7'));
    expect(board().position, played);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(board().position, played);
    await tester.tap(find.byIcon(CupertinoIcons.flag));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    final result = find.byType(XiangqiGameResultDialog);
    await tester.tap(find.descendant(of: result, matching: find.text('Analysis board')));
    await tester.pumpAndSettle();
    expect(find.byType(XiangqiAnalysisScreen), findsOneWidget);
    expect(board().position, played);
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard).last));
    expect(container.read(xiangqiAnalysisControllerProvider).moves.map((move) => move.iccs), [
      'h2e2',
      'h9g7',
      'b0c2',
      'b9c7',
    ]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(board().position, played);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.descendant(of: resume, matching: find.text('Resume')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
