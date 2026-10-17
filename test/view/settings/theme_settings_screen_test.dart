import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/settings/theme_settings_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('the xiangqi theme preview draws the engine arrow it shows on the board', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const ThemeSettingsScreen(),
        surfaceSize: const Size(900, 1200),
      ),
    );
    await tester.pumpAndSettle();

    final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    const move = XiangqiMove(XiangqiSquare.at(7, 2), XiangqiSquare.at(4, 2));
    expect(board.hint, move);
    expect(board.arrows.single.move, move);
    expect(board.arrows.single.color, const Color(0xAA15781B));
  });
}
