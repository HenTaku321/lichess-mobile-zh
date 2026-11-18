import 'dart:ui' as ui;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';

/// Record the painter's text placement before font rasterization. Test fonts often draw every
/// digit with the same glyph, which makes a screenshot insufficient for this check.
class _CoordinatePainter(XiangqiSide side) extends XiangqiBoardPainter {
  this
    : super(
        geometry: const XiangqiBoardGeometry(40, showCoordinates: true),
        position: XiangqiPosition.initial(),
        orientation: side,
        selected: null,
        moves: const IListConst([]),
        lastMove: null,
        premove: null,
        isPremoveSelection: false,
        isCheck: false,
        style: const XiangqiBoardStyle(),
        showLastMove: false,
        showBorder: true,
        hint: null,
        wrongMove: null,
        marked: const IListConst([]),
        arrows: const IListConst([]),
        shapes: const IListConst([]),
        magnifyDraggedPiece: false,
        dragTargetKind: .none,
        blindfoldMode: false,
        translating: const IListConst([]),
        fading: const IListConst([]),
        translation: const AlwaysStoppedAnimation(1),
        fade: const AlwaysStoppedAnimation(1),
        dragFrom: null,
        dragPosition: null,
        draggingPiece: false,
      );

  final labels = <double, String>{};

  @override
  void paintText(Canvas canvas, String text, TextStyle style, Offset centre) {
    labels[centre.dx] = text;
  }
}

void main() {
  for (final side in XiangqiSide.values) {
    test('$side file labels match notation at the drawn piece centres', () {
      final painter = _CoordinatePainter(side);
      final recorder = ui.PictureRecorder();
      painter.paintCoordinates(Canvas(recorder));
      recorder.endRecording().dispose();
      final expected = side == XiangqiSide.red ? '九八七六五四三二一' : '123456789';
      for (var file = 0; file < 9; file++) {
        final square = XiangqiSquare.at(file, side == XiangqiSide.red ? 0 : 9);
        final x = painter.geometry.centerOf(square, side).dx;
        expect(painter.labels[x], expected[file], reason: '$side at ${square.name}');
      }
    });
  }
}
