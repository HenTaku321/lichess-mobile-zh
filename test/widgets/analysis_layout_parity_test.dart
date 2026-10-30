import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_analysis_layout.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  for (final xiangqi in [false, true]) {
    testWidgets('analysis headers honour double text scale, xiangqi: $xiangqi', (tester) async {
      const header = Text('Depth 18', key: Key('scaled-analysis-header'));
      const size = Size(1100, 700);
      final Widget layout = xiangqi
          ? XiangqiAnalysisLayout(
              boardBuilder: (_, _, _) => const SizedBox(),
              boardHeader: header,
              panels: const [Text('Moves')],
            )
          : DefaultTabController(
              length: 1,
              child: AnalysisLayout(
                boardBuilder: (_, size, _) => SizedBox(width: size, height: size),
                pov: Side.white,
                sideToMove: Side.white,
                boardHeader: header,
                children: const [Text('Moves')],
              ),
            );
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: size,
          failOnOverflow: true,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
              child: layout,
            ),
          ),
        ),
      );

      expect(tester.getRect(find.byKey(const Key('scaled-analysis-header'))).height, atLeast(52));
      expect(tester.takeException(), isNull);
    });
  }
}
