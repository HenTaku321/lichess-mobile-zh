import 'package:chessground/chessground.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/view/puzzle/puzzle_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:lichess_mobile/src/widgets/pgn.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';
import '../xiangqi/xiangqi_puzzle_screen_test.dart' as xiangqi;
import 'example_data.dart' as chess;

void main() {
  TestLichessBinding.ensureInitialized();

  for (final isXiangqi in [false, true]) {
    for (final size in [const Size(390, 844), const Size(1280, 720)]) {
      testWidgets('${isXiangqi ? 'xiangqi' : 'chess'} gives the solver feedback first at $size', (
        tester,
      ) async {
        if (isXiangqi) {
          await xiangqi.pumpPuzzleScreen(
            tester,
            server: xiangqi.PuzzleServer(),
            surfaceSize: size,
            failOnOverflow: true,
          );
        } else {
          await tester.pumpWidget(
            await makeTestProviderScopeApp(
              tester,
              home: PuzzleScreen(
                angle: const PuzzleTheme(PuzzleThemeKey.mix),
                puzzle: chess.puzzle,
              ),
              surfaceSize: size,
              failOnOverflow: true,
            ),
          );
          await tester.pumpAndSettle();
        }
        final feedback = tester.getRect(find.text('Your turn'));
        final board = tester.getRect(
          isXiangqi ? find.byType(XiangqiBoard) : find.byType(Chessboard),
        );
        final actions = tester.getRect(find.byType(BottomBar));
        if (size.height > size.width) {
          expect(feedback.bottom, lessThanOrEqualTo(board.top));
          expect(board.bottom, lessThanOrEqualTo(actions.top));
        } else {
          final history = tester.getRect(
            isXiangqi ? find.byType(MoveList) : find.byType(DebouncedPgnTreeView),
          );
          expect(feedback.left, greaterThanOrEqualTo(board.right));
          expect(feedback.bottom, lessThanOrEqualTo(history.top));
          expect(feedback.bottom, lessThanOrEqualTo(actions.top));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
