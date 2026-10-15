import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

/// A xiangqi side's general drawn as an avatar: one piece, the same piece the board draws.
///
/// The chess screens' answer to "who is this row" is a `UserAvatar`; a xiangqi player has no
/// uploaded picture to show, and a circle with a letter in it would be a chess player's avatar
/// with the chess taken out. What a xiangqi side has instead is its general — red's 帅 or black's
/// 将 — so that is what this draws, through the same [paintXiangqiPiece] the board itself uses:
/// an avatar that looked any different from the pieces on the board would be a second idea of
/// what a xiangqi piece is.
class const XiangqiPieceAvatar({
  /// The side whose general is drawn.
  required final XiangqiSide side,

  /// The width and height of the avatar, in logical pixels.
  final double size = 40,

  /// The style the piece is drawn in; the board's default when not given.
  final XiangqiBoardStyle style = const XiangqiBoardStyle(),

  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _XiangqiPieceAvatarPainter(side, style)),
    );
  }
}

class const _XiangqiPieceAvatarPainter(final XiangqiSide side, final XiangqiBoardStyle style)
    extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // The circle clips to the avatar's box, so the piece is sized to sit inside it with its
    // resting shadow still visible: the board's radius is `cell * 0.44`, and the cell here is
    // whatever makes that radius half the box with a little room to spare.
    canvas.clipRect(Offset.zero & size);
    final cell = size.shortestSide / 0.96;
    paintXiangqiPiece(
      canvas,
      size.center(Offset.zero),
      XiangqiPiece(side, XiangqiPieceType.king),
      cell: cell,
      style: style,
    );
  }

  @override
  bool shouldRepaint(_XiangqiPieceAvatarPainter oldPainter) {
    return oldPainter.side != side || oldPainter.style != style;
  }
}
