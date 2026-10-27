import 'package:chessground/chessground.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';

import 'xiangqi_board_test.dart' show painterOf, pumpBoard;

void main() {
  final from = XiangqiSquare.parse('e3')!;
  final to = XiangqiSquare.parse('e4')!;

  testWidgets('only an explicit editor release outside the board discards a piece', (tester) async {
    final discarded = <XiangqiSquare>[];
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(
        position: XiangqiPosition.initial(),
        onDragMove: (_, _) {},
        onPieceDiscarded: discarded.add,
      ),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    final origin = rect.topLeft + geometry.centerOf(from, .red);
    final cancelled = await tester.startGesture(origin);
    await cancelled.moveTo(origin + const Offset(0, -30));
    await cancelled.cancel();
    expect(discarded, isEmpty);
    final released = await tester.startGesture(origin);
    await released.moveTo(rect.topLeft - const Offset(20, 20));
    await released.up();
    expect(discarded, [from]);
  });

  testWidgets(
    'OTB orientation is passed to every piece painter and repaints on preference change',
    (tester) async {
      await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.initial(),
          pieceOrientationBehavior: .opponentUpsideDown,
        ),
      );
      final before = painterOf(tester);
      expect(before.pieceOrientationBehavior, PieceOrientationBehavior.opponentUpsideDown);
      await pumpBoard(
        tester,
        XiangqiBoard(position: XiangqiPosition.initial(), pieceOrientationBehavior: .sideToPlay),
      );
      final after = painterOf(tester);
      expect(after.pieceOrientationBehavior, PieceOrientationBehavior.sideToPlay);
      expect(after.shouldRepaint(before), isTrue);
    },
  );

  for (final method in PieceShiftMethod.values) {
    testWidgets('$method only accepts its configured move gesture', (tester) async {
      final taps = <XiangqiSquare>[];
      final drags = <(XiangqiSquare, XiangqiSquare)>[];
      final rect = await pumpBoard(
        tester,
        XiangqiBoard(
          position: XiangqiPosition.initial(),
          pieceShiftMethod: method,
          onTapSquare: taps.add,
          onDragMove: (from, to) => drags.add((from, to)),
        ),
      );
      final geometry = XiangqiBoardGeometry.fit(rect.size);
      final origin = rect.topLeft + geometry.centerOf(from, .red);
      await tester.tapAt(origin);
      // Drag-only mode may select the origin to show targets, but only the drag callback may move.
      expect(taps, [from]);
      taps.clear();
      final gesture = await tester.startGesture(origin);
      await gesture.moveTo(rect.topLeft + geometry.centerOf(to, .red));
      await gesture.up();
      expect(drags, method == .tapTwoSquares ? isEmpty : [(from, to)]);
    });
  }

  testWidgets('release-to-move tracks the destination and commits only on release', (tester) async {
    final taps = <XiangqiSquare>[];
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(
        position: XiangqiPosition.initial(),
        selected: from,
        moveOnRelease: true,
        enableShapeDrawings: true,
        onTapSquare: taps.add,
      ),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    final gesture = await tester.startGesture(rect.topLeft + geometry.centerOf(to, .red));
    await tester.pump();
    expect(taps, isEmpty);
    expect(painterOf(tester).dragTargetBounds, isNotNull);
    final other = XiangqiSquare.parse('g4')!;
    await gesture.moveTo(rect.topLeft + geometry.centerOf(other, .red));
    await gesture.up();
    expect(taps, [other]);
  });

  testWidgets('a destination commits on pointer down when moveOnRelease is off', (tester) async {
    final taps = <XiangqiSquare>[];
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(position: XiangqiPosition.initial(), selected: from, onTapSquare: taps.add),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    final gesture = await tester.startGesture(rect.topLeft + geometry.centerOf(to, .red));
    expect(taps, [to]);
    await gesture.up();
    expect(taps, [to]);
  });

  testWidgets('an input policy cannot drag the opponent piece', (tester) async {
    final drags = <(XiangqiSquare, XiangqiSquare)>[];
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(
        position: XiangqiPosition.initial(),
        canStartDrag: (piece) => piece.side == .black,
        onDragMove: (from, to) => drags.add((from, to)),
      ),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    final gesture = await tester.startGesture(rect.topLeft + geometry.centerOf(from, .red));
    await gesture.moveTo(rect.topLeft + geometry.centerOf(to, .red));
    await gesture.up();
    expect(drags, isEmpty);
  });

  testWidgets('a second pointer cancels play without committing a move', (tester) async {
    final drags = <(XiangqiSquare, XiangqiSquare)>[];
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(
        position: XiangqiPosition.initial(),
        onDragMove: (from, to) => drags.add((from, to)),
      ),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    final first = await tester.startGesture(
      rect.topLeft + geometry.centerOf(from, .red),
      pointer: 1,
    );
    await first.moveTo(rect.topLeft + geometry.centerOf(to, .red));
    final second = await tester.startGesture(rect.center, pointer: 2);
    await first.up();
    await second.up();
    await tester.pump();
    expect(drags, isEmpty);
    expect(painterOf(tester).dragFrom, isNull);
  });

  testWidgets('empty-square taps do not create annotations', (tester) async {
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(position: XiangqiPosition.initial(), enableShapeDrawings: true),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    await tester.tapAt(rect.topLeft + geometry.centerOf(to, .red));
    await tester.pump();
    expect(painterOf(tester).shapes, isEmpty);
  });

  testWidgets('two-finger annotation never plays a move and double tap clears it', (tester) async {
    final taps = <XiangqiSquare>[];
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(
        position: XiangqiPosition.initial(),
        enableShapeDrawings: true,
        onTapSquare: taps.add,
      ),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    final at = rect.topLeft + geometry.centerOf(to, .red);
    final lock = await tester.startGesture(at, pointer: 1);
    final draw = await tester.startGesture(
      rect.topLeft + geometry.centerOf(from, .red),
      pointer: 2,
    );
    await draw.moveTo(at);
    await draw.up();
    await lock.up();
    await tester.pump();
    expect(painterOf(tester).shapes.single.from, from);
    expect(painterOf(tester).shapes.single.to, to);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pump();
    expect(painterOf(tester).shapes, isEmpty);
    await tester.pump(const Duration(milliseconds: 201));
  });

  testWidgets('mouse drags use an unscaled piece and square target', (tester) async {
    final rect = await pumpBoard(
      tester,
      XiangqiBoard(
        position: XiangqiPosition.initial(),
        magnifyDraggedPiece: true,
        onDragMove: (from, to) {},
      ),
    );
    final geometry = XiangqiBoardGeometry.fit(rect.size);
    final gesture = await tester.startGesture(
      rect.topLeft + geometry.centerOf(from, .red),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(rect.topLeft + geometry.centerOf(to, .red));
    await tester.pump();
    expect(painterOf(tester).draggedPieceScale, 1.0);
    expect(painterOf(tester).dragTargetKind, DragTargetKind.square);
    await gesture.up();
  });

  testWidgets('external marks remain distinct from user annotations', (tester) async {
    await pumpBoard(
      tester,
      XiangqiBoard(
        position: XiangqiPosition.initial(),
        marked: IList([to]),
        enableShapeDrawings: true,
      ),
    );
    expect(painterOf(tester).marked, [to]);
    expect(painterOf(tester).shapes, isEmpty);
  });
}
