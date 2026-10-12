import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

/// Paints [board] in a room of [size] and hands back where the board ended up, which is what a
/// touch has to be aimed at.
Future<Rect> pumpBoard(
  WidgetTester tester,
  XiangqiBoard board, {
  Size size = const Size(360, 400),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(size: size, child: board),
        ),
      ),
    ),
  );
  return tester.getRect(find.byType(XiangqiBoard));
}

void main() {
  group('XiangqiBoardGeometry', () {
    test('takes the largest board that fits the room, whichever side runs out first', () {
      // Ten cells of height for every nine of width, so a room that is wider than it is tall runs
      // out of height, and one that is narrower runs out of width.
      final wide = XiangqiBoardGeometry.fit(const Size(900, 400));
      expect(wide.cell, 40);
      expect(wide.width, 360);
      expect(wide.height, 400);

      final tall = XiangqiBoardGeometry.fit(const Size(90, 4000));
      expect(tall.cell, 10);
      expect(tall.width, 90);
      expect(tall.height, 100);

      // Exactly the board's own shape, and the board is the room.
      final exact = XiangqiBoardGeometry.fit(const Size(360, 400));
      expect(exact.cell, 40);
      expect(exact.width, 360);
      expect(exact.height, 400);
    });

    test('treats an unbounded side as no constraint, and refuses a room with no bounds at all', () {
      // A board in a column has all the height there is and the width of the screen.
      final inAColumn = XiangqiBoardGeometry.fit(const Size(360, double.infinity));
      expect(inAColumn.cell, 40);
      expect(inAColumn.height, 400);
      expect(() => XiangqiBoardGeometry.fit(Size.infinite), throwsFlutterError);
    });

    test('puts a0 in the bottom left corner and i9 in the top right', () {
      final geometry = XiangqiBoardGeometry.fit(const Size(360, 400));
      expect(geometry.centerOf(XiangqiSquare.parse('a0')!, .red), const Offset(20, 380));
      expect(geometry.centerOf(XiangqiSquare.parse('i9')!, .red), const Offset(340, 20));
      expect(geometry.centerOf(XiangqiSquare.parse('e0')!, .red), const Offset(180, 380));
    });

    test('turns the whole board around when black plays from the bottom', () {
      final geometry = XiangqiBoardGeometry.fit(const Size(360, 400));
      // Rotated through the middle of the board, so every square is where the one 180° from it was.
      for (var index = 0; index < kXiangqiSquares; index++) {
        final square = XiangqiSquare(index);
        expect(
          geometry.centerOf(square, .black),
          const Offset(360, 400) - geometry.centerOf(square, .red),
          reason: square.name,
        );
      }
    });

    test('lands every touch on the point it is nearest', () {
      // The one property a touch board has to have: tap anywhere on a piece and you get that piece.
      // Half a cell either way is still the same point, and the frame is half a cell wide, so the
      // whole board is reachable.
      for (final orientation in XiangqiSide.values) {
        final geometry = XiangqiBoardGeometry.fit(const Size(450, 500));
        for (var index = 0; index < kXiangqiSquares; index++) {
          final square = XiangqiSquare(index);
          final centre = geometry.centerOf(square, orientation);
          for (final nudge in const [
            Offset.zero,
            Offset(-19, -19),
            Offset(19, 19),
            Offset(-19, 19),
            Offset(19, -19),
          ]) {
            expect(
              geometry.squareAt(centre + nudge, orientation),
              square,
              reason: '${square.name} $orientation $nudge',
            );
          }
        }
      }
    });

    test('is null for a touch beside the board', () {
      final geometry = XiangqiBoardGeometry.fit(const Size(360, 400));
      expect(geometry.squareAt(const Offset(-1, -1), .red), isNull);
      expect(geometry.squareAt(const Offset(361, 200), .red), isNull);
      expect(geometry.squareAt(const Offset(200, 401), .red), isNull);
    });
  });

  group('XiangqiBoard', () {
    testWidgets('reports the square that was tapped', (tester) async {
      final tapped = <XiangqiSquare>[];
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(position: XiangqiPosition.initial(), onTapSquare: tapped.add),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      await tester.tapAt(rect.topLeft + geometry.centerOf(XiangqiSquare.parse('e3')!, .red));
      await tester.tapAt(rect.topLeft + geometry.centerOf(XiangqiSquare.parse('i9')!, .red));
      expect(tapped, [XiangqiSquare.parse('e3'), XiangqiSquare.parse('i9')]);
    });

    testWidgets('reports the square that was tapped when black is at the bottom', (tester) async {
      final tapped = <XiangqiSquare>[];
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.initial(),
          orientation: .black,
          onTapSquare: tapped.add,
        ),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      // a0 is the far side's corner in this orientation, and it is the point nearest the touch.
      await tester.tapAt(rect.topLeft + geometry.centerOf(XiangqiSquare.parse('a0')!, .black));
      expect(tapped, [XiangqiSquare.parse('a0')]);
    });

    testWidgets('says nothing when the touch lands beside the board', (tester) async {
      final tapped = <XiangqiSquare>[];
      // A room far taller than the board: the board is centred in it, so its corners are off the
      // board and not squares.
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(position: XiangqiPosition.initial(), onTapSquare: tapped.add),
        size: const Size(360, 600),
      );
      await tester.tapAt(rect.topLeft + const Offset(2, 2));
      expect(tapped, isEmpty);
    });

    testWidgets('says nothing and does nothing when it is not listening', (tester) async {
      final rect = await pumpBoard(tester, XiangqiBoard(position: XiangqiPosition.initial()));
      await tester.tapAt(rect.center);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a position that has everything on it at once', (tester) async {
      // A selected piece with the moves it may play, the two squares of the last move, and a
      // general in check — the whole of what the painter has to draw, so that a position which
      // reaches into an empty square or a piece that is not there would throw here.
      var position = XiangqiPosition.initial();
      for (final iccs in ['h2e2', 'h9g7', 'b0c2']) {
        position = play(position, XiangqiMove.parseIccs(iccs)!);
      }
      final selected = XiangqiSquare.parse('c2')!;
      await pumpBoard(
        tester,
        XiangqiBoard(
          position: position,
          selected: selected,
          moves: legalMovesFrom(position, selected),
          lastMove: XiangqiMove.parseIccs('b0c2'),
        ),
      );
      expect(tester.takeException(), isNull);

      // The mate of the rules tests: a general in check with nowhere to go, which is the one
      // position that paints the check disc.
      await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.fromFen('3rk4/9/9/9/9/9/9/6n2/4r4/4K4 w - - 0 1'),
          moves: const IListConst([]),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
