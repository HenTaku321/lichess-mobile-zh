import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_analysis_layout.dart';
import 'package:material_ui/material_ui.dart';

import '../test_provider_scope.dart';

void main() {
  testWidgets('portrait analysis panels do not nest move-list cards', (tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(375, 812),
        home: XiangqiAnalysisLayout(boardBuilder: (_, _, _) => const SizedBox()),
      ),
    );
    expect(tester.widget<MoveList>(find.byType(MoveList)).wrapInCard, isFalse);
    expect(find.byType(Card), findsNothing);
  });
  for (final size in const [Size(320, 568), Size(375, 812), Size(812, 375), Size(1100, 700)]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('analysis stays bounded at $size with text scale $scale', (tester) async {
        await tester.pumpWidget(
          await makeTestProviderScopeApp(
            tester,
            surfaceSize: size,
            home: MediaQuery(
              data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
              child: XiangqiAnalysisLayout(
                boardBuilder: (_, _, _) => const SizedBox(key: Key('analysis-board')),
                boardHeader: const Text('Depth 18'),
                engineLines: const SizedBox(height: 72),
                evalGauge: const ColoredBox(color: Colors.grey),
                panels: const [Text('Moves')],
              ),
            ),
          ),
        );
        final board = tester.getRect(find.byKey(const Key('analysis-board')));
        expect(board.width, greaterThan(0));
        expect(board.height, greaterThan(0));
        expect(board.left, greaterThanOrEqualTo(0));
        expect(board.right, lessThanOrEqualTo(size.width));
        expect(board.bottom, lessThanOrEqualTo(size.height));
        expect(find.byType(TabBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('multiple analysis panels expose tabs', (tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: XiangqiAnalysisLayout(
          boardBuilder: (_, _, _) => const SizedBox(),
          tabs: const [
            Tab(text: 'Moves'),
            Tab(text: 'Summary'),
          ],
          panels: const [Text('Move panel'), Text('Summary panel')],
        ),
      ),
    );
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Move panel'), findsOneWidget);
  });
}
