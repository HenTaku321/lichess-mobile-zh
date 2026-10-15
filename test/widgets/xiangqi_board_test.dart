import 'package:chessground/chessground.dart';
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

/// The painter the board is drawing itself with.
///
/// The pieces here are canvas output rather than widgets, so there is nothing to find by key and
/// this is the only door onto what the board has drawn — including, for a move in flight, the
/// pieces it has travelling.
XiangqiBoardPainter painterOf(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(of: find.byType(XiangqiBoard), matching: find.byType(CustomPaint)),
            )
            .painter!
        as XiangqiBoardPainter;

/// Drags the point at [from] by [delta], in steps, and lets go.
///
/// The steps matter: a pan is only recognised once the finger has travelled further than the touch
/// slop, so a drag has to be walked rather than jumped, exactly as a finger would walk it.
Future<void> dragFrom(
  WidgetTester tester,
  Rect board,
  XiangqiBoardGeometry geometry,
  XiangqiSquare from,
  List<Offset> steps,
) async {
  final gesture = await tester.startGesture(board.topLeft + geometry.centerOf(from, .red));
  for (final step in steps) {
    await gesture.moveBy(step);
  }
  await gesture.up();
  await tester.pump();
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

    test('leaves the board exactly as it was when the coordinates are off', () {
      // The whole point of the flag being optional: a caller that does not ask for coordinates
      // gets the board that has always been drawn, to the pixel.
      expect(XiangqiBoardGeometry.fit(const Size(360, 400)).showCoordinates, isFalse);
      expect(XiangqiBoardGeometry.fit(const Size(360, 400)).pad, 20);
    });

    test('reserves a whole extra cell of margin for the file coordinates', () {
      // Ten cells across and eleven up: the same grid, with a whole cell of frame instead of half
      // of one, so the digits have a clear band below the bottom rank to be printed in. A piece
      // reaches 0.44 of a cell past the line it stands on, which is most of a half-cell margin and
      // comfortably less than a whole one.
      final numbered = XiangqiBoardGeometry.fit(const Size(400, 440), showCoordinates: true);
      expect(numbered.showCoordinates, isTrue);
      expect(numbered.cell, 40);
      expect(numbered.width, 400);
      expect(numbered.height, 440);
      expect(numbered.pad, 40);

      // The same room fits a smaller board once the frame has to be wider, and the grid inside it
      // is the same grid, a cell further in.
      final crowded = XiangqiBoardGeometry.fit(const Size(360, 400), showCoordinates: true);
      expect(crowded.cell, 36);
      expect(crowded.width, 360);
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

  group('xiangqiPieceAnimation', () {
    final before = XiangqiPosition.fromFen('3ak4/9/9/9/9/9/9/R3r4/9/3AK4 w - - 0 1');
    final after = XiangqiPosition.fromFen('3ak4/9/9/9/9/9/9/4R4/9/3AK4 w - - 0 1');
    final capture = XiangqiMove.parseIccs('a2e2')!;

    test('has the piece that moved travelling, and the piece it took fading out', () {
      final animation = xiangqiPieceAnimation(before, after, capture);
      expect(animation.translating.toList(), [
        (
          from: XiangqiSquare.parse('a2')!,
          to: XiangqiSquare.parse('e2')!,
          piece: before.pieceAt(XiangqiSquare.parse('a2')!)!,
        ),
      ]);
      expect(animation.fading.toList(), [
        (square: XiangqiSquare.parse('e2')!, piece: before.pieceAt(XiangqiSquare.parse('e2')!)!),
      ]);
    });

    test('has nothing fading for a move that takes nothing', () {
      final quiet = XiangqiMove.parseIccs('a2b2')!;
      final quietAfter = XiangqiPosition.fromFen('3ak4/9/9/9/9/9/9/1R2r4/9/3AK4 w - - 0 1');
      final animation = xiangqiPieceAnimation(before, quietAfter, quiet);
      expect(animation.translating, hasLength(1));
      expect(animation.fading, isEmpty);
    });

    test('has nothing moving when the move does not explain the change', () {
      // An undo is the case that matters: the board goes back to where it was while the last move
      // is still the one that was taken back, and the piece it names is no longer on its square.
      expect(xiangqiPieceAnimation(after, before, capture).translating, isEmpty);

      // A move that is not the one played at all.
      expect(
        xiangqiPieceAnimation(before, after, XiangqiMove.parseIccs('a2a3')).translating,
        isEmpty,
      );

      // A whole position swap, as a new game or a board set up by hand is.
      expect(
        xiangqiPieceAnimation(before, XiangqiPosition.initial(), capture).translating,
        isEmpty,
      );
    });

    test('has nothing moving when there is no move at all', () {
      expect(xiangqiPieceAnimation(before, after, null).translating, isEmpty);
      expect(xiangqiPieceAnimation(before, after, null).fading, isEmpty);
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

      // With no drag handler the board does not pick a piece up either: there is nothing a drag
      // could report, so the piece stays where it is.
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      final gesture = await tester.startGesture(
        rect.topLeft + geometry.centerOf(XiangqiSquare.parse('e3')!, .red),
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(painterOf(tester).dragFrom, isNull);
      await gesture.up();
      await tester.pump();
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

    testWidgets('draws the whole set of options at once too', (tester) async {
      // Every new option on, on a board that is being dragged and hinted at the same time as it is
      // animating a move: the arrangement the painter has the most ways to throw from.
      final before = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('h2e2')!;
      final replied = XiangqiMove.parseIccs('h9g7')!;
      final position = play(play(before, move), replied);
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: position,
          lastMove: replied,
          showCoordinates: true,
          hint: XiangqiMove.parseIccs('b2e2'),
          selected: XiangqiSquare.parse('e2'),
          moves: legalMovesFrom(position, XiangqiSquare.parse('e2')!),
          onDragMove: (from, to) {},
          style: const XiangqiBoardStyle(ink: Color(0xFF112233)),
        ),
        size: const Size(400, 440),
      );
      expect(tester.takeException(), isNull);
      final geometry = XiangqiBoardGeometry.fit(rect.size, showCoordinates: true);
      await dragFrom(tester, rect, geometry, XiangqiSquare.parse('e2')!, const [Offset(0, -40)]);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'reports a drag from the square it was picked up on to the square it was let go on',
      (tester) async {
        final dragged = <(XiangqiSquare, XiangqiSquare)>[];
        final rect = await pumpBoard(
          tester,
          XiangqiBoard(
            position: XiangqiPosition.initial(),
            onDragMove: (from, to) => dragged.add((from, to)),
          ),
        );
        final geometry = XiangqiBoardGeometry.fit(rect.size);
        final e3 = XiangqiSquare.parse('e3')!;
        // One cell up: red's soldier steps forward, and both ends of the drag are named.
        await dragFrom(tester, rect, geometry, e3, const [Offset(0, -40)]);
        expect(dragged, [(e3, XiangqiSquare.parse('e4'))]);
      },
    );

    testWidgets('reports a one-rank drag on a board narrower than the pan slop', (tester) async {
      // A pan normally waits for 36 logical pixels of travel, and a narrow board puts one rank
      // inside that: 30 points here, which is a phone of about 320 points with the padding a game
      // screen puts around the board. The pan still gets the gesture, because the finger has moved
      // further than the tap allows, so the tap bows out and the pan is the only one left in the
      // arena to win it on the way up. The move the player made is the move that is reported.
      final dragged = <(XiangqiSquare, XiangqiSquare)>[];
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.initial(),
          onDragMove: (from, to) => dragged.add((from, to)),
        ),
        size: const Size(270, 300),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      expect(geometry.cell, 30);
      final e3 = XiangqiSquare.parse('e3')!;
      await dragFrom(tester, rect, geometry, e3, const [Offset(0, -30)]);
      expect(dragged, [(e3, XiangqiSquare.parse('e4'))]);
    });

    testWidgets('reports nothing when the drag is let go back where it started', (tester) async {
      final dragged = <(XiangqiSquare, XiangqiSquare)>[];
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.initial(),
          onDragMove: (from, to) => dragged.add((from, to)),
        ),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      final e3 = XiangqiSquare.parse('e3')!;
      // Off the square and back onto it: the piece was picked up and put down again, which is not
      // a move, and the board does not invent a tap out of it either.
      await dragFrom(tester, rect, geometry, e3, const [Offset(0, -40), Offset(0, 40)]);
      expect(dragged, isEmpty);
    });

    testWidgets('reports nothing when the drag is let go beside the board', (tester) async {
      final dragged = <(XiangqiSquare, XiangqiSquare)>[];
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.initial(),
          onDragMove: (from, to) => dragged.add((from, to)),
        ),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      // Dragged clean off the right-hand edge of the board, where there is no square to land on.
      await dragFrom(tester, rect, geometry, XiangqiSquare.parse('e3')!, const [Offset(200, 0)]);
      expect(dragged, isEmpty);
    });

    testWidgets('picks up only a piece of the side to move', (tester) async {
      final dragged = <(XiangqiSquare, XiangqiSquare)>[];
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.initial(),
          onDragMove: (from, to) => dragged.add((from, to)),
        ),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      // Red to move, so black's chariot is not the player's to pick up, and an empty square has
      // nothing on it to pick up at all.
      await dragFrom(tester, rect, geometry, XiangqiSquare.parse('a9')!, const [Offset(0, 40)]);
      await dragFrom(tester, rect, geometry, XiangqiSquare.parse('e5')!, const [Offset(0, 40)]);
      expect(dragged, isEmpty);
    });

    testWidgets('draws the piece that moved travelling, and only while it is moving', (
      tester,
    ) async {
      final before = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('e3e4')!;
      final after = play(before, move);
      final pawn = before.pieceAt(XiangqiSquare.parse('e3')!)!;
      await pumpBoard(tester, XiangqiBoard(position: before));
      expect(painterOf(tester).translating, isEmpty);

      await pumpBoard(tester, XiangqiBoard(position: after, lastMove: move));
      // One frame in, the piece is travelling and the board has not yet drawn it on its
      // destination.
      expect(painterOf(tester).translating.toList(), [
        (from: XiangqiSquare.parse('e3')!, to: XiangqiSquare.parse('e4')!, piece: pawn),
      ]);
      expect(painterOf(tester).fading, isEmpty);

      // And once it has arrived the board is a board again, drawing the position itself.
      await tester.pumpAndSettle();
      expect(painterOf(tester).translating, isEmpty);
      expect(painterOf(tester).fading, isEmpty);
    });

    testWidgets('draws the captured piece fading out under the piece that took it', (tester) async {
      // A position built for the capture alone, so that the move is unambiguous: red's chariot on
      // a2 takes black's on e2 down the second rank.
      final before = XiangqiPosition.fromFen('3ak4/9/9/9/9/9/9/R3r4/9/3AK4 w - - 0 1');
      final move = XiangqiMove.parseIccs('a2e2')!;
      final after = play(before, move);
      final taken = before.pieceAt(XiangqiSquare.parse('e2')!)!;
      await pumpBoard(tester, XiangqiBoard(position: before));
      await pumpBoard(tester, XiangqiBoard(position: after, lastMove: move));
      expect(painterOf(tester).translating, hasLength(1));
      expect(painterOf(tester).fading.toList(), [
        (square: XiangqiSquare.parse('e2')!, piece: taken),
      ]);
      await tester.pumpAndSettle();
      expect(painterOf(tester).fading, isEmpty);
    });

    testWidgets('draws the move already arrived when the duration is zero', (tester) async {
      final before = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('e3e4')!;
      final after = play(before, move);
      await pumpBoard(tester, XiangqiBoard(position: before));
      await pumpBoard(
        tester,
        XiangqiBoard(position: after, lastMove: move, animationDuration: Duration.zero),
      );
      expect(painterOf(tester).translating, isEmpty);
    });

    testWidgets('draws nothing travelling when the move does not explain the change', (
      tester,
    ) async {
      // An undo, which is the case that matters: the board goes back to where it was while the last
      // move is still the one that was taken back.
      final before = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('e3e4')!;
      final after = play(before, move);
      await pumpBoard(tester, XiangqiBoard(position: after, lastMove: move));
      await pumpBoard(tester, XiangqiBoard(position: before, lastMove: move));
      expect(painterOf(tester).translating, isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('draws nothing travelling when the board is turned around', (tester) async {
      // A move and a flip at once is noise, and the flip wins: the piece would otherwise travel
      // across a board it never started on.
      final before = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('e3e4')!;
      final after = play(before, move);
      await pumpBoard(tester, XiangqiBoard(position: before));
      await pumpBoard(tester, XiangqiBoard(position: after, lastMove: move, orientation: .black));
      expect(painterOf(tester).translating, isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('marks the square a dragged piece is over, the way the setting asks', (
      tester,
    ) async {
      final e3 = XiangqiSquare.parse('e3')!;
      final e4 = XiangqiSquare.parse('e4')!;
      for (final kind in DragTargetKind.values) {
        final rect = await pumpBoard(
          tester,
          XiangqiBoard(
            position: XiangqiPosition.initial(),
            dragTargetKind: kind,
            onDragMove: (from, to) {},
          ),
        );
        final geometry = XiangqiBoardGeometry.fit(rect.size);

        // Nothing is under a finger yet, so there is no square to mark.
        expect(painterOf(tester).dragTargetBounds, isNull, reason: '$kind before the drag');

        final gesture = await tester.startGesture(rect.topLeft + geometry.centerOf(e3, .red));
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();

        final bounds = painterOf(tester).dragTargetBounds;
        if (kind == .none) {
          expect(bounds, isNull, reason: '$kind draws nothing');
        } else {
          // A circle is two squares across and a square is one, both centred on the point the
          // finger has reached — the soldier's step from e3 up to e4.
          final side = kind == .circle ? geometry.cell * 2 : geometry.cell;
          expect(bounds, isNotNull, reason: '$kind draws a target');
          expect(bounds!.center, geometry.centerOf(e4, .red), reason: '$kind is centred right');
          expect(bounds.width, side, reason: '$kind is as wide as the setting says');
          expect(bounds.height, side, reason: '$kind is as tall as the setting says');
        }

        await gesture.up();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('draws the dragged piece magnified and lifted, or plain under the finger', (
      tester,
    ) async {
      final e3 = XiangqiSquare.parse('e3')!;

      // A drag held open, so the painter can be read while the piece is still under the finger.
      // The painter is a snapshot, so it stays readable after the finger is lifted.
      Future<XiangqiBoardPainter> holdDrag({required bool magnify}) async {
        final rect = await pumpBoard(
          tester,
          XiangqiBoard(
            position: XiangqiPosition.initial(),
            magnifyDraggedPiece: magnify,
            onDragMove: (from, to) {},
          ),
        );
        final geometry = XiangqiBoardGeometry.fit(rect.size);
        final gesture = await tester.startGesture(rect.topLeft + geometry.centerOf(e3, .red));
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        final painter = painterOf(tester);
        expect(painter.magnifyDraggedPiece, magnify);
        await gesture.up();
        await tester.pumpAndSettle();
        return painter;
      }

      final magnified = await holdDrag(magnify: true);
      final plain = await holdDrag(magnify: false);

      // The magnified piece is the larger of the two and is drawn a whole cell above the finger;
      // the plain one is its usual size, centred exactly on the finger.
      expect(magnified.draggedPieceScale, 1.15);
      expect(plain.draggedPieceScale, 1.0);
      expect(magnified.dragPosition! - magnified.draggedPieceCentre!, Offset(0, magnified.cell));
      expect(plain.draggedPieceCentre, plain.dragPosition);
    });
  });

  group('XiangqiBoard options', () {
    testWidgets('hands the painter the flags it was given', (tester) async {
      final move = XiangqiMove.parseIccs('e3e4')!;
      final position = play(XiangqiPosition.initial(), move);
      const style = XiangqiBoardStyle(surface: Color(0xFF000000), redInk: Color(0xFFFF00FF));
      final hint = XiangqiMove.parseIccs('b2e2');
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: position,
          lastMove: move,
          showCoordinates: true,
          showLastMove: false,
          showBorder: false,
          hint: hint,
          style: style,
        ),
        size: const Size(400, 440),
      );
      final painter = painterOf(tester);
      expect(painter.showLastMove, isFalse);
      expect(painter.showBorder, isFalse);
      expect(painter.hint, hint);
      expect(painter.style, style);
      expect(painter.geometry.showCoordinates, isTrue);
      final expected = XiangqiBoardGeometry.fit(rect.size, showCoordinates: true);
      expect(painter.geometry.cell, expected.cell);
      expect(painter.geometry.pad, expected.pad);
      expect(painter.geometry.width, expected.width);
      expect(painter.geometry.height, expected.height);
      await tester.pumpAndSettle();
    });

    testWidgets('draws the same board with the defaults as the board that was always drawn', (
      tester,
    ) async {
      await pumpBoard(tester, XiangqiBoard(position: XiangqiPosition.initial()));
      final painter = painterOf(tester);
      expect(painter.showLastMove, isTrue);
      expect(painter.showBorder, isTrue);
      expect(painter.hint, isNull);
      expect(painter.style, const XiangqiBoardStyle());
      expect(painter.geometry.showCoordinates, isFalse);
      expect(painter.geometry.cell, 40);
    });

    testWidgets('counts the pieces it draws, and the one in flight is not among them', (
      tester,
    ) async {
      // The initial position is sixteen pieces a side, and the count is of what the board is
      // drawing right now rather than of what is on it.
      final before = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('e3e4')!;
      await pumpBoard(tester, XiangqiBoard(position: before));
      expect(painterOf(tester).drawnPieceSquares, hasLength(32));

      // Mid-move the pawn is off the board and being drawn travelling instead: the square it is
      // arriving on is the translating piece's to draw, and the one it left is empty.
      await pumpBoard(tester, XiangqiBoard(position: play(before, move), lastMove: move));
      expect(painterOf(tester).translating, hasLength(1));
      expect(painterOf(tester).drawnPieceSquares, hasLength(31));
      expect(painterOf(tester).drawnPieceSquares, isNot(contains(XiangqiSquare.parse('e4'))));

      await tester.pumpAndSettle();
      expect(painterOf(tester).drawnPieceSquares, hasLength(32));
    });

    testWidgets('draws no piece at all when blindfold is on', (tester) async {
      await pumpBoard(tester, XiangqiBoard(position: XiangqiPosition.initial()));
      expect(painterOf(tester).blindfoldMode, isFalse);
      expect(painterOf(tester).drawnPieceSquares, hasLength(32));

      await pumpBoard(
        tester,
        XiangqiBoard(position: XiangqiPosition.initial(), blindfoldMode: true),
      );
      expect(painterOf(tester).blindfoldMode, isTrue);
      expect(painterOf(tester).drawnPieceSquares, isEmpty);
    });

    testWidgets('leaves everything but the pieces on the blindfolded board', (tester) async {
      // Blindfold is a position that has to be remembered, not a blank board: the frame, the
      // coordinates, the marks the last move left and the square a dragged piece is over are all
      // still drawn, and the pieces are the only thing missing. The two passes that would
      // otherwise put one back — a move in flight, and a drag under the finger — are both read
      // here.
      final before = XiangqiPosition.initial();
      final move = XiangqiMove.parseIccs('h2e2')!;
      await pumpBoard(tester, XiangqiBoard(position: before, blindfoldMode: true));
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: play(before, move),
          lastMove: move,
          showCoordinates: true,
          blindfoldMode: true,
          onDragMove: (from, to) {},
        ),
        size: const Size(400, 440),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size, showCoordinates: true);

      // The cannon that moved is travelling, and neither it nor anything else is drawn.
      expect(painterOf(tester).translating, hasLength(1));
      expect(painterOf(tester).drawnPieceSquares, isEmpty);

      // A piece picked up — black's soldier, black being the side to move — is not drawn either,
      // while the square under the finger still is.
      final from = XiangqiSquare.parse('e6')!;
      final gesture = await tester.startGesture(rect.topLeft + geometry.centerOf(from, .red));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(painterOf(tester).dragFrom, from);
      expect(painterOf(tester).drawnPieceSquares, isEmpty);
      expect(painterOf(tester).dragTargetBounds, isNotNull);
      expect(tester.takeException(), isNull);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('XiangqiBoardStyle', () {
    test(
      'extracts photographic background from textured chessboard themes and leaves solid ones null',
      () {
        final marbleStyle = XiangqiBoardStyle.fromChessboardColorScheme(
          ChessboardColorScheme.marble,
        );
        expect(marbleStyle.backgroundImage, isNotNull);
        expect(marbleStyle.pieceFace, const Color(0xFFFDFBF7));

        final brownStyle = XiangqiBoardStyle.fromChessboardColorScheme(ChessboardColorScheme.brown);
        expect(brownStyle.backgroundImage, isNull);
        expect(brownStyle.pieceFace, const Color(0xFFFDFBF7));
      },
    );
  });
}
