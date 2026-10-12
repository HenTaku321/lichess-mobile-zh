import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';
import 'package:material_ui/material_ui.dart';

/// The colours the board is drawn in: a wooden board, which looks the same in a light room and a
/// dark one, so none of these come from the theme.
const _surface = Color(0xFFF1DCB0);
const _frame = Color(0xFF8A5A2B);
const _ink = Color(0xFF6B4A20);
const _riverInk = Color(0xFFA98A55);
const _pieceFace = Color(0xFFFDF3DC);
const _pieceRing = Color(0xFF7A5326);
const _redInk = Color(0xFFB7282E);
const _blackInk = Color(0xFF23262B);
const _lastMove = Color(0x59D98A18);
const _selected = Color(0xCCD98A18);
const _target = Color(0x66333A2B);
const _check = Color(0x33D0342C);
const _checkRing = Color(0xE6D0342C);

/// The faces a board's characters are looked for in, in order, before the platform's own last
/// resort. A serif face is what a board is printed in; the platform's own CJK font, whatever it
/// turns out to be, draws them if none of these is installed. The order is only a preference.
const _cjkFallback = ['Noto Serif CJK SC', 'Source Han Serif SC', 'Songti SC', 'SimSun'];

/// The points the board prints its little corner brackets around: the cannons' and the soldiers'
/// starting points, the same four and ten on each side of the river.
const _markPoints = [
  (1, 2),
  (7, 2),
  (0, 3),
  (2, 3),
  (4, 3),
  (6, 3),
  (8, 3),
  (1, 7),
  (7, 7),
  (0, 6),
  (2, 6),
  (4, 6),
  (6, 6),
  (8, 6),
];

/// Where a xiangqi board's lines fall, and where a touch on it lands.
///
/// The board is nine cells wide and ten cells tall — eight gaps between its nine files, nine
/// between its ten ranks, and half a cell of wooden frame around each — so it is not a square and
/// neither is the room it is given. [fit] takes the room and returns the geometry of the largest
/// board that fits in it, which is what the widget draws, centred.
///
/// One cell is the whole of the geometry: every distance on the board is a multiple of it, so a
/// board of any size is the same board.
@immutable
final class const XiangqiBoardGeometry(final double cell) {
  /// The geometry of the largest board that fits in [available].
  ///
  /// A side of [available] that is not finite is treated as no constraint at all, so a board in a
  /// column — no height to speak of — simply fills the width. Both sides infinite is not something
  /// that can be drawn and is refused.
  factory fit(Size available) {
    final cell = math.min(
      available.width.isFinite ? available.width / 9 : double.infinity,
      available.height.isFinite ? available.height / 10 : double.infinity,
    );
    if (!cell.isFinite) {
      throw FlutterError(
        'XiangqiBoard cannot size itself from $available: it needs a bounded width or height.',
      );
    }
    return XiangqiBoardGeometry(cell);
  }

  /// The distance from the outer line to the edge of the board, half a cell of wooden frame.
  double get pad => cell / 2;

  /// The board's own width, frame included.
  double get width => cell * 9;

  /// The board's own height, frame included.
  double get height => cell * 10;

  /// The radius of a piece drawn on the board.
  double get pieceRadius => cell * 0.44;

  /// The centre of the point [file] across and [rank] up, both counted in the board's own frame:
  /// file 0 is the leftmost line as it is drawn and rank 0 the bottom one.
  ///
  /// Every part of the board itself — its lines, its palaces, its river, its printed marks — is the
  /// same in both orientations and is drawn in these coordinates; only the pieces and the moves of
  /// them care which side is at the bottom, which is what [centerOf] is for.
  Offset pointAt(int file, int rank) => Offset(pad + file * cell, height - pad - rank * cell);

  /// The centre of [square] when [orientation] plays from the bottom of the board.
  Offset centerOf(XiangqiSquare square, XiangqiSide orientation) => pointAt(
    orientation == .red ? square.file : 8 - square.file,
    orientation == .red ? square.rank : 9 - square.rank,
  );

  /// The square [local] — a point in the board's own frame — falls on, or null if it falls off the
  /// board.
  ///
  /// A touch lands on the nearest point and not on a cell: a board is played by putting a finger on
  /// an intersection, and the frame around it is exactly half a cell, so every point inside the
  /// board is within reach of one of the ninety.
  XiangqiSquare? squareAt(Offset local, XiangqiSide orientation) {
    final file = ((local.dx - pad) / cell).round();
    final rank = ((height - pad - local.dy) / cell).round();
    if (file < 0 || file > 8 || rank < 0 || rank > 9) return null;
    return XiangqiSquare.at(
      orientation == .red ? file : 8 - file,
      orientation == .red ? rank : 9 - rank,
    );
  }
}

/// A xiangqi board, drawn rather than assembled.
///
/// This is a picture and not a tree of boxes: nine files crossing ten ranks at ninety points, which
/// is not a thing boxes are good at, and the chess board the app already has cannot be bent into it
/// — `chessground` is eight by eight down to its `File` and `Rank`, with a single square size for
/// its whole geometry. So this repeats its trick instead: one `CustomPaint` for the board and the
/// pieces on it, one gesture handler that turns a touch into a square.
///
/// Everything is drawn, the pieces included. A xiangqi piece is a circle with a character on it,
/// and that character is [XiangqiPiece.glyph], so there is no art to ship and no pieces to lay out:
/// the board scales to any size and the characters come from whatever CJK font the platform has.
///
/// The board fills the room it is given, which does not have to be square — see
/// [XiangqiBoardGeometry.fit].
class const XiangqiBoard({
  required final XiangqiPosition position,

  /// The side that plays from the bottom of the screen.
  final XiangqiSide orientation = .red,

  /// The piece that has been picked up, if any. Drawn with a ring around it.
  final XiangqiSquare? selected,

  /// The moves that piece may play, each dotted where it lands — or, where it lands on a piece,
  /// drawn as a ring around that piece.
  final IList<XiangqiMove> moves = const IListConst([]),

  /// The move that was played last, its from and to both marked.
  final XiangqiMove? lastMove,

  /// Called with the square a touch landed on. Not called when the touch lands beside the board.
  final void Function(XiangqiSquare square)? onTapSquare,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tap = onTapSquare;
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = XiangqiBoardGeometry.fit(constraints.biggest);
        return Center(
          child: GestureDetector(
            behavior: .opaque,
            onTapUp: tap == null
                ? null
                : (details) {
                    final square = geometry.squareAt(details.localPosition, orientation);
                    if (square != null) tap(square);
                  },
            child: CustomPaint(
              size: Size(geometry.width, geometry.height),
              painter: _XiangqiBoardPainter(
                geometry: geometry,
                position: position,
                orientation: orientation,
                selected: selected,
                moves: moves,
                lastMove: lastMove,
                isCheck: isCheck(position),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _XiangqiBoardPainter({
  required final XiangqiBoardGeometry geometry,
  required final XiangqiPosition position,
  required final XiangqiSide orientation,
  required final XiangqiSquare? selected,
  required final IList<XiangqiMove> moves,
  required final XiangqiMove? lastMove,
  required final bool isCheck,
}) extends CustomPainter {
  double get cell => geometry.cell;

  @override
  void paint(Canvas canvas, Size size) {
    paintSurface(canvas);
    paintGrid(canvas);
    paintMarks(canvas);
    paintLastMove(canvas);
    paintCheck(canvas);
    paintPieces(canvas);
    paintTargets(canvas);
    paintSelection(canvas);
  }

  /// The wooden board itself: a darker frame around a lighter field.
  void paintSurface(Canvas canvas) {
    final board = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, geometry.width, geometry.height),
      Radius.circular(cell * 0.16),
    );
    canvas.drawRRect(board, Paint()..color = _frame);
    canvas.drawRRect(
      RRect.fromRectAndRadius(board.outerRect.deflate(cell * 0.12), Radius.circular(cell * 0.08)),
      Paint()..color = _surface,
    );
  }

  /// The ninety points and the eight lines through them: nine files, ten ranks, the two palaces'
  /// diagonals, and the seven inner files cut in two by the river.
  void paintGrid(Canvas canvas) {
    final line = Paint()
      ..color = _ink
      ..strokeWidth = math.max(1, cell * 0.022)
      ..strokeCap = StrokeCap.round;

    for (var rank = 0; rank <= 9; rank++) {
      canvas.drawLine(geometry.pointAt(0, rank), geometry.pointAt(8, rank), line);
    }
    for (var file = 0; file <= 8; file++) {
      // The river is not a line that is missing: it is a band between ranks 4 and 5, and the inner
      // files do not cross it, which is what leaves the room for 楚河汉界.
      if (file == 0 || file == 8) {
        canvas.drawLine(geometry.pointAt(file, 0), geometry.pointAt(file, 9), line);
      } else {
        canvas.drawLine(geometry.pointAt(file, 0), geometry.pointAt(file, 4), line);
        canvas.drawLine(geometry.pointAt(file, 5), geometry.pointAt(file, 9), line);
      }
    }

    // The board's edge is drawn twice, a thinner line just outside the grid's own: that double line
    // is what tells a printed board apart from a sheet of paper with lines on it.
    canvas.drawRect(
      Rect.fromPoints(geometry.pointAt(0, 9), geometry.pointAt(8, 0)).inflate(cell * 0.1),
      Paint()
        ..color = _ink
        ..style = .stroke
        ..strokeWidth = math.max(1, cell * 0.014),
    );

    // Both palaces: the two diagonals of each, drawn from the corners of the three by three they
    // sit in.
    for (final corner in [0, 7]) {
      canvas.drawLine(geometry.pointAt(3, corner), geometry.pointAt(5, corner + 2), line);
      canvas.drawLine(geometry.pointAt(5, corner), geometry.pointAt(3, corner + 2), line);
    }
  }

  /// 楚河 and 汉界 in the river, and the corner brackets the board prints at the cannons' and
  /// soldiers' starting points.
  ///
  /// The river reads left to right in both orientations, because it is part of the board's own
  /// decoration rather than a label on a side's half of it: a board turned around is a board read
  /// upside down, and there is no way to write 楚河 that is more right than another.
  void paintMarks(Canvas canvas) {
    final riverStyle = TextStyle(
      color: _riverInk,
      fontSize: cell * 0.46,
      fontWeight: FontWeight.bold,
      letterSpacing: cell * 0.2,
      fontFamilyFallback: _cjkFallback,
    );
    final riverY = geometry.height - geometry.pad - 4.5 * cell;
    paintText(canvas, '楚河', riverStyle, Offset(geometry.pad + 2 * cell, riverY));
    paintText(canvas, '汉界', riverStyle, Offset(geometry.pad + 6 * cell, riverY));

    // Each bracket is a corner turned to face the point: its vertex sits on the diagonal, half a
    // bracket's length further out, and its two arms reach back towards the lines through the
    // point without ever touching them. Only the quadrants whose neighbour is still on the board
    // get one, which is why a soldier in the corner has two and the rest have four.
    final bracket = Paint()
      ..color = _ink
      ..strokeWidth = math.max(1, cell * 0.022)
      ..strokeCap = StrokeCap.round;
    const reach = 0.13;
    const arm = 0.11;
    for (final (file, rank) in _markPoints) {
      final point = geometry.pointAt(file, rank);
      for (final (dfile, drank) in const [(-1, 1), (1, 1), (-1, -1), (1, -1)]) {
        if (!_onBoard(file + dfile, rank + drank)) continue;
        final vertex = Offset(point.dx + dfile * cell * reach, point.dy - drank * cell * reach);
        canvas.drawLine(
          vertex,
          Offset(point.dx + dfile * cell * (reach - arm), vertex.dy),
          bracket,
        );
        canvas.drawLine(
          vertex,
          Offset(vertex.dx, point.dy - drank * cell * (reach - arm)),
          bracket,
        );
      }
    }
  }

  /// The from and the to of the last move, under the pieces so that a piece hides the half of its
  /// own marker.
  void paintLastMove(Canvas canvas) {
    final move = lastMove;
    if (move == null) return;
    final paint = Paint()..color = _lastMove;
    for (final square in [move.from, move.to]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: geometry.centerOf(square, orientation),
            width: cell * 0.9,
            height: cell * 0.9,
          ),
          Radius.circular(cell * 0.12),
        ),
        paint,
      );
    }
  }

  /// A red ring around the general that is in check, and a wash of the same red behind it.
  void paintCheck(Canvas canvas) {
    if (!isCheck) return;
    final king = XiangqiPiece(position.turn, .king);
    for (var index = 0; index < kXiangqiSquares; index++) {
      if (position.board[index] == king) {
        final centre = geometry.centerOf(XiangqiSquare(index), orientation);
        canvas.drawCircle(centre, geometry.pieceRadius * 1.2, Paint()..color = _check);
        canvas.drawCircle(
          centre,
          geometry.pieceRadius * 1.2,
          Paint()
            ..color = _checkRing
            ..style = .stroke
            ..strokeWidth = cell * 0.06,
        );
        return;
      }
    }
  }

  void paintPieces(Canvas canvas) {
    for (var index = 0; index < kXiangqiSquares; index++) {
      final piece = position.board[index];
      if (piece == null) continue;
      final centre = geometry.centerOf(XiangqiSquare(index), orientation);
      final ink = piece.side == .red ? _redInk : _blackInk;

      canvas.drawCircle(centre, geometry.pieceRadius, Paint()..color = _pieceFace);
      canvas.drawCircle(
        centre,
        geometry.pieceRadius - cell * 0.0225,
        Paint()
          ..color = _pieceRing
          ..style = .stroke
          ..strokeWidth = cell * 0.045,
      );
      canvas.drawCircle(
        centre,
        geometry.pieceRadius * 0.84,
        Paint()
          ..color = ink
          ..style = .stroke
          ..strokeWidth = cell * 0.014,
      );
      paintText(
        canvas,
        piece.glyph,
        TextStyle(
          color: ink,
          fontSize: cell * 0.6,
          fontWeight: FontWeight.bold,
          fontFamilyFallback: _cjkFallback,
        ),
        centre,
      );
    }
  }

  /// What the selected piece may play: a dot on an empty point, a ring around a piece that would be
  /// taken.
  void paintTargets(Canvas canvas) {
    for (final move in moves) {
      final centre = geometry.centerOf(move.to, orientation);
      if (position.pieceAt(move.to) == null) {
        canvas.drawCircle(centre, cell * 0.13, Paint()..color = _target);
      } else {
        canvas.drawCircle(
          centre,
          geometry.pieceRadius * 1.08,
          Paint()
            ..color = _target
            ..style = .stroke
            ..strokeWidth = cell * 0.07,
        );
      }
    }
  }

  void paintSelection(Canvas canvas) {
    final square = selected;
    if (square == null) return;
    canvas.drawCircle(
      geometry.centerOf(square, orientation),
      geometry.pieceRadius * 1.1,
      Paint()
        ..color = _selected
        ..style = .stroke
        ..strokeWidth = cell * 0.07,
    );
  }

  /// Writes [text] centred on [centre].
  void paintText(Canvas canvas, String text, TextStyle style, Offset centre) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, centre - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _XiangqiBoardPainter oldDelegate) =>
      oldDelegate.geometry.cell != geometry.cell ||
      oldDelegate.position != position ||
      oldDelegate.orientation != orientation ||
      oldDelegate.selected != selected ||
      oldDelegate.moves != moves ||
      oldDelegate.lastMove != lastMove ||
      oldDelegate.isCheck != isCheck;
}

bool _onBoard(int file, int rank) => file >= 0 && file <= 8 && rank >= 0 && rank <= 9;
