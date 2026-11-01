import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_options.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart'
    show xiangqiEngineProvider;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';
import 'xiangqi_analysis_exit_contract_test.dart' as exits;
import 'xiangqi_analysis_screen_test.dart' as analysis;

XiangqiAnalysisOptions sourceOptions({required String sourceId, bool engineAllowed = true}) =>
    XiangqiAnalysisOptions.line(
      sourceId: sourceId,
      initialPosition: XiangqiPosition.initial(),
      moves: IList([analysis.moveAt('h2e2'), analysis.moveAt('h9g7'), analysis.moveAt('b0c2')]),
      initialCursor: 1,
      engineAllowed: engineAllowed,
    );

Future<void> pumpAnalysisEntry(
  WidgetTester tester,
  XiangqiAnalysisOptions Function() readOptions,
) async {
  final (:engine, :transport) = analysis.fakeXiangqiEngine();
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      surfaceSize: const Size(1280, 720),
      failOnOverflow: true,
      defaultPreferences: analysis.evaluationPreferences(isEnabled: false),
      overrides: {xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((ref) => engine)},
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(XiangqiAnalysisScreen.buildRoute(options: readOptions())),
              child: const Text('Open analysis'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(transport.takeCommands().where((command) => command.startsWith('go ')), isEmpty);
}

Future<void> openAnalysis(WidgetTester tester) async {
  await tester.tap(find.text('Open analysis'));
  await exits.finishRoute(tester, find.byType(XiangqiAnalysisScreen, skipOffstage: false));
}

Future<void> leaveAnalysis(WidgetTester tester) async {
  final route = ModalRoute.of(tester.element(find.byType(XiangqiAnalysisScreen)))!;
  Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
  await tester.pump();
  await tester.pump(route.reverseTransitionDuration + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  expect(find.text('Open analysis'), findsOneWidget);
}

ProviderContainer analysisContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(XiangqiBoard)));

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  testWidgets('reopening a source keeps its selected sideline, cursor and folded branches', (
    tester,
  ) async {
    final options = sourceOptions(sourceId: 'selected-branch');
    await pumpAnalysisEntry(tester, () => options);
    await openAnalysis(tester);
    final container = analysisContainer(tester);
    final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
    controller.play(analysis.moveAt('g6g5'));
    controller.play(analysis.moveAt('b0c2'));
    controller.goBack();
    controller.collapseVariations(IList([analysis.moveAt('h2e2')]));
    final before = container.read(xiangqiAnalysisControllerProvider);
    final exported = controller.makeLineExport();
    await tester.pump();
    await leaveAnalysis(tester);
    await openAnalysis(tester);

    final restored = analysisContainer(tester);
    final state = restored.read(xiangqiAnalysisControllerProvider);
    expect(state.moves, before.moves);
    expect(state.cursor, before.cursor);
    expect(state.position, before.position);
    expect(state.canGoForward, isTrue);
    expect(restored.read(xiangqiAnalysisControllerProvider.notifier).makeLineExport(), exported);
    expect(
      state.variationTree!
          .nodeAt(IList([analysis.moveAt('h2e2'), analysis.moveAt('g6g5')]))
          .isCollapsed,
      isTrue,
    );
    await leaveAnalysis(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening a source keeps the board orientation selected by the reader', (
    tester,
  ) async {
    final options = sourceOptions(sourceId: 'orientation');
    await pumpAnalysisEntry(tester, () => options);
    await openAnalysis(tester);
    await tester.tap(find.byIcon(CupertinoIcons.arrow_2_squarepath));
    await tester.pump();
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.black);
    await leaveAnalysis(tester);
    await openAnalysis(tester);
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.black);
    await leaveAnalysis(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening a source does not resurrect explicitly deleted continuations', (
    tester,
  ) async {
    final options = sourceOptions(sourceId: 'deleted-continuation');
    await pumpAnalysisEntry(tester, () => options);
    await openAnalysis(tester);
    final path = IList([analysis.moveAt('h2e2'), analysis.moveAt('h9g7')]);
    analysisContainer(tester).read(xiangqiAnalysisControllerProvider.notifier).deleteFromHere(path);
    await tester.pump();
    await leaveAnalysis(tester);
    await openAnalysis(tester);
    final state = analysisContainer(tester).read(xiangqiAnalysisControllerProvider);
    expect(state.moves, [analysis.moveAt('h2e2')]);
    expect(state.cursor, 1);
    expect(state.canGoForward, isFalse);
    expect(state.variationTree!.hasPath(path), isFalse);
    await leaveAnalysis(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restricted source cannot restore edits cached under broader permissions', (
    tester,
  ) async {
    var options = sourceOptions(sourceId: 'permission-boundary');
    await pumpAnalysisEntry(tester, () => options);
    await openAnalysis(tester);
    analysisContainer(tester)
        .read(xiangqiAnalysisControllerProvider.notifier)
        .play(analysis.moveAt('g6g5'));
    await tester.pump();
    await leaveAnalysis(tester);
    options = sourceOptions(sourceId: 'permission-boundary', engineAllowed: false);
    await openAnalysis(tester);
    final state = analysisContainer(tester).read(xiangqiAnalysisControllerProvider);
    expect(
      state.variationTree!
          .nodeAt(IList([analysis.moveAt('h2e2')]))
          .children
          .map((node) => node.move),
      [analysis.moveAt('h9g7')],
    );
    await leaveAnalysis(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restricted analysis node menus cannot bypass the export restriction', (
    tester,
  ) async {
    final options = sourceOptions(sourceId: 'restricted-node-menu', engineAllowed: false);
    await pumpAnalysisEntry(tester, () => options);
    await openAnalysis(tester);
    await tester.longPress(find.text('炮二平五'));
    await tester.pumpAndSettle();
    expect(find.text('Delete from here'), findsOneWidget);
    expect(find.text('Copy to clipboard'), findsNothing);
    Navigator.of(tester.element(find.text('Delete from here'))).pop();
    await tester.pumpAndSettle();
    await leaveAnalysis(tester);
    expect(tester.takeException(), isNull);
  });
}
