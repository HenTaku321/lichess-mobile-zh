// Tests for the card the game layout draws its board in.
//
// The chess screens draw a board that fills the screen edge to edge on a portrait phone, and a
// board in a rounded card anywhere the board is smaller than the screen — a tablet, or any
// landscape — and the xiangqi layout is given the same split. What is under test is that the split
// is made in one place, at the same rounding the chess screens' own cards are drawn with.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:material_ui/material_ui.dart';

import '../test_provider_scope.dart';

/// The board, found inside whatever card the layout has drawn around it.
const board = SizedBox(key: Key('the-board'));

/// Pumps the layout at [size].
Future<void> pumpLayout(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const XiangqiGameLayout(board: board, moves: null),
      ),
    ),
  );
}

/// The rounding of the card the board is clipped by, or null when the board sits flush.
BorderRadius? cardRadius(WidgetTester tester) {
  final clip = find.ancestor(
    of: find.byKey(const Key('the-board')),
    matching: find.byType(ClipRRect),
  );
  if (clip.evaluate().isEmpty) return null;
  return tester.widget<ClipRRect>(clip.first).borderRadius as BorderRadius;
}

void main() {
  testWidgets('a board smaller than the screen is drawn as a card', (tester) async {
    // A landscape screen is never filled by a portrait board, so the board is carded.
    await pumpLayout(tester, const Size(1100, 700));
    expect(cardRadius(tester), Styles.boardBorderRadius);
  });

  testWidgets('a portrait phone gets the flush board the chess screens give it', (tester) async {
    await pumpLayout(tester, const Size(400, 800));
    expect(cardRadius(tester), isNull);
  });
}
