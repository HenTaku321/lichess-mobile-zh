import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:material_ui/material_ui.dart';

import '../test_provider_scope.dart';

/// One row of a move list, the way every caller hands moves over: the index of each move in the
/// game, and the string to write for it.
List<List<MapEntry<int, String>>> sliced(String first, String second) => [
  [MapEntry(0, first), MapEntry(1, second)],
];

void main() {
  group('MoveList', () {
    testWidgets("follows the user's piece notation when the caller leaves it alone", (
      tester,
    ) async {
      // The default path, and the one every existing caller is on: nothing is passed, so the list
      // still draws moves in the chess font when the user asked for symbols.
      final app = await makeTestProviderScopeApp(
        tester,
        home: const MoveList(
          type: MoveListType.stacked,
          slicedMoves: [
            [MapEntry(0, 'e4'), MapEntry(1, 'e5')],
          ],
          currentMoveIndex: 1,
        ),
        overrides: {
          pieceNotationProvider: pieceNotationProvider.overrideWith((ref) => PieceNotation.symbol),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('e4')).style?.fontFamily, 'ChessFont');
    });

    testWidgets('leaves the moves in the default face when the user asked for letters', (
      tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const MoveList(
          type: MoveListType.stacked,
          slicedMoves: [
            [MapEntry(0, 'e4'), MapEntry(1, 'e5')],
          ],
          currentMoveIndex: 1,
        ),
        overrides: {
          pieceNotationProvider: pieceNotationProvider.overrideWith((ref) => PieceNotation.letter),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('e4')).style?.fontFamily, isNull);
    });

    testWidgets("a caller's own notation is drawn as it is, over the user's preference", (
      tester,
    ) async {
      // Xiangqi's move strings are characters, not algebraic, so a caller that supplies them passes
      // [PieceNotation.letter] to keep the chess font away — even though the user's preference is
      // symbols.
      final app = await makeTestProviderScopeApp(
        tester,
        home: MoveList(
          type: MoveListType.stacked,
          slicedMoves: sliced('炮二平五', '马8进7'),
          currentMoveIndex: 1,
          pieceNotation: PieceNotation.letter,
        ),
        overrides: {
          pieceNotationProvider: pieceNotationProvider.overrideWith((ref) => PieceNotation.symbol),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('炮二平五')).style?.fontFamily, isNull);
      expect(find.text('马8进7'), findsOneWidget);
    });

    testWidgets('renders pre-computed strings in the inline layout too', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: MoveList(
          type: MoveListType.inline,
          slicedMoves: sliced('车九平八', '卒7进1'),
          currentMoveIndex: 0,
          pieceNotation: PieceNotation.letter,
        ),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('车九平八'), findsOneWidget);
      expect(find.text('卒7进1'), findsOneWidget);
    });
  });
}
