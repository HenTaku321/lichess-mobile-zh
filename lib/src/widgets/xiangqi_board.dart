import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessground/chessground.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';
import 'package:material_ui/material_ui.dart';

/// The colours a board is drawn in.
///
/// The defaults are the wooden board this widget has always drawn — a board that looks the same
/// in a light room and a dark one, so none of these comes from the theme — lifted out of the
/// painter so that a caller can recolour it. A board can instead be dressed in one of the app's
/// chessboard themes: see [XiangqiBoardStyle.fromChessboardColorScheme].
@immutable
final class const XiangqiBoardStyle({
  /// The light field the grid is drawn on.
  final Color surface = const Color(0xFFEFE4CF),

  /// The darker frame around the field.
  final Color frame = const Color(0xFF6A4524),

  /// The grid's lines and the board's printed marks.
  final Color ink = const Color(0xFF4E3723),

  /// 楚河 and 汉界, printed more faintly than the grid.
  final Color riverInk = const Color(0xFF9E845A),

  /// The face of a piece, at its centre: the face shades from this to [pieceFaceEnd] at the rim,
  /// the way a turned wooden disc catches the light at its middle.
  final Color pieceFace = const Color(0xFFFDFBF7),

  /// The face of a piece at its rim, the shade [pieceFace] darkens to at the edge.
  final Color pieceFaceEnd = const Color(0xFFF5EBD7),

  /// The soft shadow a piece casts on the field under it, drawn a touch lower than the piece so
  /// that the disc reads as sitting above the board rather than printed on it.
  final Color pieceShadow = const Color(0x33000000),

  /// The ring around a piece's face.
  final Color pieceRing = const Color(0xFF7D5936),

  /// The character and inner ring of red's pieces.
  final Color redInk = const Color(0xFFB8282E),

  /// The character and inner ring of black's pieces.
  final Color blackInk = const Color(0xFF1D2024),

  /// The two points a move was played between, painted in the same square-sized shape and at the
  /// same strength as the chess board's last-move highlight.
  final HighlightDetails lastMove = const HighlightDetails(solidColor: Color(0x809CC700)),

  /// The point the picked-up piece stands on, in the same square-sized shape as the chess board's
  /// selection highlight.
  final HighlightDetails selected = const HighlightDetails(solidColor: Color(0x6014551E)),

  /// The dot on an empty point a selected piece may play to, and the ring around a piece it may
  /// take. These are the chess board's valid-move colour and drawing rules.
  final Color target = const Color(0x4014551E),

  /// The glow at the centre of the mark behind a general that is in check, shading out to nothing
  /// at the rim: a glow rather than a flat wash, the way the chess board's own check mark is a
  /// blurred radial gradient and not a disc.
  final Color checkGlow = const Color(0x66D0342C),

  /// The ring around a general that is in check.
  final Color checkRing = const Color(0x99D0342C),

  /// The circle drawn on the square a hinted move would be played from. Blue rather than a colour
  /// from the board's own palette, because a hint is the app speaking and not part of the board.
  final Color hint = const Color(0x990099C8),

  /// The photographic background image asset for the board, if any.
  final ImageProvider? backgroundImage,
}) {
  /// The colours of [colorScheme], one of the app's chessboard themes, laid over this board.
  ///
  /// The xiangqi board is a single field with lines drawn across it, not a chequered grid, so only
  /// the two flat colours of a theme can be taken from it: its light square becomes the field and its
  /// dark square the frame. [ink] is the dark square too, which is the darkest flat colour the theme
  /// offers and so the one that stays legible drawn over its own light field; [riverInk] is that ink
  /// faded towards the field, the way 楚河汉界 are printed faintly today. The two move highlights keep
  /// the theme's full [HighlightDetails], solid colour or image, and [target] is its valid-move
  /// colour. A theme that paints an interaction mark with an image therefore paints it here too.
  ///
  /// The pieces follow the field: [pieceFace] is the field lifted towards white (a disc cut from
  /// the board's own wood, polished) and its rim shade [pieceFaceEnd] a touch darker; [pieceRing]
  /// is the ink faded towards the field. [redInk] and
  /// [blackInk] are not taken from any theme — the two armies' colours are part of the game itself,
  /// not of the decoration. [checkGlow], [checkRing] and [hint] keep this board's own defaults too:
  /// a theme has no check colour to read, and a hint is the app speaking, not part of the board.
  /// [pieceShadow] is a shadow, so it stays black at the same faintness on every board.
  ///
  /// The theme's material is taken whole where it has one. Twenty of the app's twenty-four themes
  /// paint their squares from a photograph — marble, four woods, canvas, leather and the rest — and
  /// the chessboard shows that photograph through an image background. This board shows the same
  /// photograph the same way, through [backgroundImage]: the field is the theme's own material and
  /// not a flat colour standing in for it, so a board in marble is marble and a board in walnut is
  /// walnut. The remaining themes are flat colours and are drawn as flat colours, which is what they
  /// are.
  ///
  /// A photograph has no grid drawn on it, so the printed marks have to be able to sit on one: over
  /// an image theme the ink is deepened away from the theme's own dark square, which is picked to
  /// read against a chequered board and not against a busy photograph. The two armies' colours, the
  /// pieces' material and the check and hint marks are this board's own on every theme, as above.
  factory fromChessboardColorScheme(ChessboardColorScheme colorScheme) {
    const plain = XiangqiBoardStyle();
    final surface = colorScheme.lightSquare;
    final dark = colorScheme.darkSquare;

    ImageProvider? backgroundImage;
    final bg = colorScheme.background;
    if (bg is ImageChessboardBackground) {
      backgroundImage = bg.image;
    }

    // Over a photograph the grid is read against grain and veining rather than against a flat
    // colour, so it is drawn darker than the theme's dark square; over a flat colour the theme's own
    // dark square is already the most legible ink the theme offers and is left alone.
    final ink = backgroundImage == null ? dark : Color.lerp(dark, const Color(0xFF000000), 0.34)!;
    final frame = backgroundImage == null ? dark : Color.lerp(dark, const Color(0xFF000000), 0.5)!;

    return XiangqiBoardStyle(
      surface: surface,
      frame: frame,
      ink: ink,
      riverInk: Color.lerp(ink, surface, 0.45)!,
      pieceFace: plain.pieceFace,
      pieceFaceEnd: plain.pieceFaceEnd,
      pieceRing: plain.pieceRing,
      lastMove: colorScheme.lastMove,
      selected: colorScheme.selected,
      target: colorScheme.validMoves,
      backgroundImage: backgroundImage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XiangqiBoardStyle &&
          other.surface == surface &&
          other.frame == frame &&
          other.ink == ink &&
          other.riverInk == riverInk &&
          other.pieceFace == pieceFace &&
          other.pieceFaceEnd == pieceFaceEnd &&
          other.pieceShadow == pieceShadow &&
          other.pieceRing == pieceRing &&
          other.redInk == redInk &&
          other.blackInk == blackInk &&
          other.lastMove == lastMove &&
          other.selected == selected &&
          other.target == target &&
          other.checkGlow == checkGlow &&
          other.checkRing == checkRing &&
          other.hint == hint &&
          other.backgroundImage == backgroundImage;

  @override
  int get hashCode => Object.hash(
    surface,
    frame,
    ink,
    riverInk,
    pieceFace,
    pieceFaceEnd,
    pieceShadow,
    pieceRing,
    redInk,
    blackInk,
    lastMove,
    selected,
    target,
    checkGlow,
    checkRing,
    hint,
    backgroundImage,
  );
}

/// The faces a board's characters are looked for in, in order, before the platform's own last
/// resort. A serif face is what a board is printed in; the platform's own CJK font, whatever it
/// turns out to be, draws them if none of these is installed. The order is only a preference.
const _cjkFallback = ['Noto Serif CJK SC', 'Source Han Serif SC', 'Songti SC', 'SimSun'];

/// A piece lifted by the finger is drawn larger and casts a deeper, softer shadow than the resting
/// pieces — it is further from the board than any of them.
const _draggedScale = 1.15;
const _dragShadowColor = Color(0x55000000);
const _dragShadowBlur = 0.08;

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

/// The room a board leaves around its grid, measured in cells: half a cell, the margin the board
/// has always had, or a whole one when the file coordinates are on and need somewhere to stand.
const _xiangqiInset = 0.5;
const _xiangqiCoordinateInset = 1.0;

double _xiangqiMargin(bool showCoordinates) =>
    showCoordinates ? _xiangqiCoordinateInset : _xiangqiInset;

/// Where a xiangqi board's lines fall, and where a touch on it lands.
///
/// The board is nine cells wide and ten cells tall — eight gaps between its nine files, nine
/// between its ten ranks, and half a cell of wooden frame around each — so it is not a square and
/// neither is the room it is given. [fit] takes the room and returns the geometry of the largest
/// board that fits in it, which is what the widget draws, centred.
///
/// When [showCoordinates] is set the board reserves a whole cell of frame instead of half, so that
/// the file digits have a margin below the pieces to stand in. The grid, the pieces and the
/// measuring are otherwise the same board, one cell bigger; with the flag off — as it is by
/// default — nothing below is any different from what it has always been.
///
/// One cell is the whole of the geometry: every distance on the board is a multiple of it, so a
/// board of any size is the same board.
@immutable
final class const XiangqiBoardGeometry(
  final double cell, {

  /// Whether the board is laying out the wider frame the file coordinates are printed in.
  final bool showCoordinates = false,
}) {
  /// The geometry of the largest board that fits in [available].
  ///
  /// A side of [available] that is not finite is treated as no constraint at all, so a board in a
  /// column — no height to speak of — simply fills the width. Both sides infinite is not something
  /// that can be drawn and is refused.
  factory fit(Size available, {bool showCoordinates = false}) {
    final margin = _xiangqiMargin(showCoordinates);
    final cell = math.min(
      available.width.isFinite ? available.width / (8 + 2 * margin) : double.infinity,
      available.height.isFinite ? available.height / (9 + 2 * margin) : double.infinity,
    );
    if (!cell.isFinite) {
      throw FlutterError(
        'XiangqiBoard cannot size itself from $available: it needs a bounded width or height.',
      );
    }
    return XiangqiBoardGeometry(cell, showCoordinates: showCoordinates);
  }

  /// The distance from the outer line to the edge of the board: half a cell of wooden frame, or a
  /// whole one when the file coordinates need the room.
  double get pad => cell * _xiangqiMargin(showCoordinates);

  /// The board's own width, frame included.
  double get width => cell * (8 + 2 * _xiangqiMargin(showCoordinates));

  /// The board's own height, frame included.
  double get height => cell * (9 + 2 * _xiangqiMargin(showCoordinates));

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

/// One piece travelling between two squares while a move is being drawn.
typedef XiangqiTranslatingPiece = ({XiangqiSquare from, XiangqiSquare to, XiangqiPiece piece});

/// One piece fading out of the square it was captured on while a move is being drawn.
typedef XiangqiFadingPiece = ({XiangqiSquare square, XiangqiPiece piece});

/// What to animate when the position on a board has changed from [from] to [to], given [move],
/// the move that was played.
///
/// The whole correctness of the animation is that a move explains exactly one change: a piece
/// leaves one square and arrives on another. [move] explains the change between the two positions
/// only when the piece that stood on `move.from` is now on `move.to` and `move.from` is now empty;
/// when all three hold, one translating piece comes back and, if something stood on `move.to` in
/// [from], one fading piece for the capture. In every other case both lists are empty, and empty
/// means "draw [to] and animate nothing".
///
/// That single test is also what makes undo, a new game, and a board turned around animate nothing
/// at all, with no separate flag to keep in step: undo leaves a different piece on `move.from` and
/// the moved piece still on `move.to`, so the equality fails and the board simply snaps.
///
/// This is a pure top-level function deliberately. The rule above is the whole feature, and keeping
/// it out of the widget means it can be held against two positions directly, with no widget to pump
/// and no frame to advance.
///
/// The nearest-piece heuristic chessground uses to pair up two positions is not needed here (see
/// its `preparePieceAnimations`): a chessground board is handed a new position and no move, so it
/// has to guess which piece went where, while this one is always given the exact [move] and moves
/// exactly one piece.
({IList<XiangqiTranslatingPiece> translating, IList<XiangqiFadingPiece> fading})
xiangqiPieceAnimation(XiangqiPosition from, XiangqiPosition to, XiangqiMove? move) {
  final piece = move == null ? null : from.pieceAt(move.from);
  if (move == null ||
      piece == null ||
      to.pieceAt(move.to) != piece ||
      to.pieceAt(move.from) != null) {
    return (
      translating: const IListConst<XiangqiTranslatingPiece>([]),
      fading: const IListConst<XiangqiFadingPiece>([]),
    );
  }
  final captured = from.pieceAt(move.to);
  return (
    translating: [(from: move.from, to: move.to, piece: piece)].lock,
    fading: captured == null
        ? const IListConst<XiangqiFadingPiece>([])
        : [(square: move.to, piece: captured)].lock,
  );
}

/// One piece drawn at [centre], the way a board draws it: face, ring, inner ring and character.
///
/// A top-level function rather than a method of [XiangqiBoardPainter], because a piece is not drawn
/// only on a board. The board editor's palette draws the same pieces to be picked from, and a palette
/// that drew them any other way would be offering the player a piece the board would not then show.
/// Both go through here, so the two cannot drift apart.
///
/// [cell] is the board's own cell — see [XiangqiBoardGeometry] — and every dimension below is a
/// multiple of it, so a piece is the same piece at any size. [scale] enlarges it about [centre],
/// which is what a board does to the piece under the player's finger. [dropShadow] is the piece's
/// resting shadow; the board turns it off for the dragged piece, which casts a deeper shadow of
/// its own instead.
void paintXiangqiPiece(
  Canvas canvas,
  Offset centre,
  XiangqiPiece piece, {
  required double cell,
  required XiangqiBoardStyle style,
  double scale = 1,
  bool dropShadow = true,
}) {
  final radius = cell * 0.44 * scale;
  final ink = piece.side == .red ? style.redInk : style.blackInk;
  // The piece sits above the board rather than on it: a soft shadow dropped a little below, the
  // face shading from a lit centre to a darker rim like a turned wooden disc.
  if (dropShadow) {
    canvas.drawCircle(
      centre.translate(0, cell * 0.012 * scale),
      radius,
      Paint()
        ..color = const Color(0x28000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.014 * scale),
    );
    canvas.drawCircle(
      centre.translate(0, cell * 0.035 * scale),
      radius,
      Paint()
        ..color = const Color(0x1F000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.055 * scale),
    );
  }
  canvas.drawCircle(
    centre,
    radius,
    Paint()
      ..shader = ui.Gradient.radial(centre - Offset(radius * 0.28, radius * 0.28), radius * 1.3, [
        style.pieceFace,
        style.pieceFaceEnd,
      ]),
  );
  canvas.drawCircle(
    centre,
    radius - cell * 0.012 * scale,
    Paint()
      ..color = style.pieceRing.withValues(alpha: 0.45)
      ..style = .stroke
      ..strokeWidth = cell * 0.024 * scale,
  );
  canvas.drawCircle(
    centre,
    radius * 0.82,
    Paint()
      ..color = ink.withValues(alpha: 0.8)
      ..style = .stroke
      ..strokeWidth = cell * 0.016 * scale,
  );
  _paintXiangqiText(
    canvas,
    piece.glyph,
    TextStyle(
      color: ink.withValues(alpha: 0.22),
      fontSize: cell * 0.58 * scale,
      fontWeight: FontWeight.w600,
      fontFamilyFallback: _cjkFallback,
    ),
    centre.translate(0, cell * 0.008 * scale),
  );
  _paintXiangqiText(
    canvas,
    piece.glyph,
    TextStyle(
      color: ink,
      fontSize: cell * 0.58 * scale,
      fontWeight: FontWeight.w600,
      fontFamilyFallback: _cjkFallback,
    ),
    centre,
  );
}

/// Writes [text] centred on [centre]: the one place a board or a palette draws text.
void _paintXiangqiText(Canvas canvas, String text, TextStyle style, Offset centre) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, centre - Offset(painter.width / 2, painter.height / 2));
}

/// One arrow drawn over a xiangqi board: the move [move], in [color] when given.
///
/// The engine speaks in moves, and an arrow is a move drawn rather than played. [color] is null
/// for the board's own hint colour; an analysis board with several lines passes a colour per line
/// so the reader can tell which arrow belongs to which score.
@immutable
final class const XiangqiBoardArrow({
  required final XiangqiMove move,
  final Color? color,
  final double opacity = 0.82,
}) {
  @override
  bool operator ==(Object other) =>
      other is XiangqiBoardArrow &&
      other.move == move &&
      other.color == color &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(move, color, opacity);
}

/// A xiangqi board, drawn rather than assembled, and played by hand.
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
/// A move can be animated: give [lastMove] and a new [position] and the piece that moved is drawn
/// travelling from the square it left to the square it arrived on. The move's [animationDuration]
/// of zero means no animation at all.
///
/// With [blindfoldMode] on, no piece is drawn at all — the player's own included — while every
/// other part of the board is drawn as it always is.
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

  /// The move that was played last, its from and to both marked, and the piece that moved drawn
  /// travelling between the two when the position changes.
  final XiangqiMove? lastMove,

  /// Called with the square a touch landed on. Not called when the touch lands beside the board.
  final void Function(XiangqiSquare square)? onTapSquare,

  /// Called with the square a drag began on and the square it was released over, when the two are
  /// different squares. A drag released back on the square it started from, or off the board, is
  /// not a move and is not reported.
  ///
  /// This is also what makes the board draggable: with no handler there is nothing a drag could
  /// report, so the board does not pick a piece up at all.
  final void Function(XiangqiSquare from, XiangqiSquare to)? onDragMove,

  /// Whether a drag may pick a piece of either side up, rather than only the side to move.
  ///
  /// Off is what a game wants: a player moves their own pieces, and the other side's are refused.
  /// On is for the board editor, where both sides are the same person's and a piece of either
  /// colour has to be movable. Which side may be moved is chess-rule logic and not geometry logic —
  /// the editor is legitimately asking the board for something a game refuses to do — which is why
  /// it is a flag here rather than something the board works out for itself.
  final bool dragAnyPiece = false,

  /// How long a move takes to be drawn travelling. [Duration.zero] draws it already arrived.
  final Duration animationDuration = const Duration(milliseconds: 150),

  /// Whether to print the files' digits along the bottom edge, in the numbering of the side that
  /// is playing from the bottom.
  final bool showCoordinates = false,

  /// Whether to mark the from and the to of [lastMove].
  final bool showLastMove = true,

  /// Whether to draw the outer frame around the board.
  final bool showBorder = true,

  /// Whether to leave every piece off the board, the player's own included.
  ///
  /// Blindfold is not a board that has gone blank: the squares, the lines, the coordinates, the
  /// highlights, the legal-move targets, the selection and the hint are all still drawn, and only
  /// the pieces are gone, so the position has to be remembered rather than read off the board. This
  /// is what chessground's own blindfold mode does — every one of its piece passes returns early
  /// while it is set — and the two boards behave the same way here.
  final bool blindfoldMode = false,

  /// A move to hint at, drawn as a translucent circle on the square it would be played from.
  final XiangqiMove? hint,

  /// Moves to draw as arrows over the board, best line first.
  ///
  /// An arrow is what the engine's own answer looks like on the chess board: a line from the
  /// piece to move to the point it is going to. The hint's circle below still says which piece is
  /// being pointed at, and the arrow says where it goes. Analysis lines use the same drawing so a
  /// second and third line can be shown in their own colours.
  final IList<XiangqiBoardArrow> arrows = const IListConst([]),

  /// Whether the piece under the finger is drawn larger than the rest, with a soft shadow, and
  /// lifted clear of the touch point so that the finger does not cover it.
  ///
  /// With this off the piece is drawn at its usual size, with no shadow, exactly under the finger,
  /// which is what the board has always done. The chess board's setting of the same name governs
  /// the same two looks there.
  final bool magnifyDraggedPiece = true,

  /// What is drawn on the square a dragged piece is over, while a drag is in flight: the chess
  /// board's own choice of a circle twice a square wide, a square the size of one, or nothing at
  /// all.
  final DragTargetKind dragTargetKind = .circle,

  /// The colours the board is drawn in.
  final XiangqiBoardStyle style = const XiangqiBoardStyle(),
}) extends StatefulWidget {
  @override
  State<XiangqiBoard> createState() => _XiangqiBoardState();
}

class _XiangqiBoardState() extends State<XiangqiBoard> with SingleTickerProviderStateMixin {
  /// The pieces being drawn travelling and fading out, empty when no move is being drawn.
  IList<XiangqiTranslatingPiece> _translating = const IListConst([]);
  IList<XiangqiFadingPiece> _fading = const IListConst([]);

  /// The square a drag began on, and where the finger is now, while one is in flight.
  XiangqiSquare? _dragFrom;
  Offset? _dragPosition;

  late final AnimationController _controller;
  late final CurvedAnimation _translation;
  late final CurvedAnimation _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
      animationBehavior: .preserve,
    )..addStatusListener(_onAnimationStatus);
    _translation = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInQuad);
  }

  @override
  void dispose() {
    _controller.dispose();
    _translation.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// Empties the pieces being drawn, so that a finished animation leaves the board drawing the
  /// position itself: the travelling piece has arrived, and there is nothing left to interpolate.
  void _clearAnimation() {
    _translating = const IListConst([]);
    _fading = const IListConst([]);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == .completed) {
      setState(_clearAnimation);
    }
  }

  void _stopAnimation() {
    _controller.stop();
    _clearAnimation();
  }

  @override
  void didUpdateWidget(covariant XiangqiBoard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.animationDuration != widget.animationDuration) {
      _controller.duration = widget.animationDuration;
    }

    // A move caught mid-flight by the board being turned around is noise: the piece would travel
    // across a board it did not start on. The turn wins and the move is dropped.
    if (oldWidget.orientation != widget.orientation) {
      _stopAnimation();
      return;
    }

    if (oldWidget.position == widget.position) return;

    final animation = xiangqiPieceAnimation(oldWidget.position, widget.position, widget.lastMove);
    if (widget.animationDuration == Duration.zero ||
        (animation.translating.isEmpty && animation.fading.isEmpty)) {
      _stopAnimation();
      return;
    }

    // Restarting from zero truncates an animation that has not finished, and that is deliberate:
    // at its easiest the engine answers in about a millisecond, so a new position often arrives
    // well inside the 150 ms the last move is still being drawn for. Queueing the remainder of a
    // sub-150 ms animation is not worth the bookkeeping, so the new one takes over, as chessground
    // lets its own.
    _translating = animation.translating;
    _fading = animation.fading;
    _controller.forward(from: 0.0);
  }

  /// Begins a drag if the finger has come down on a piece the board may pick up: one of the side to
  /// move, or, with [XiangqiBoard.dragAnyPiece] set, either side's. Which moves are legal is the
  /// caller's business: the board does not know the rules, and a square with a piece on it is the
  /// only thing it can be sure of.
  void _startDrag(XiangqiBoardGeometry geometry, Offset local) {
    final square = geometry.squareAt(local, widget.orientation);
    if (square == null) return;
    final piece = widget.position.pieceAt(square);
    if (piece == null || (!widget.dragAnyPiece && piece.side != widget.position.turn)) return;
    setState(() {
      _dragFrom = square;
      _dragPosition = local;
    });
  }

  void _updateDrag(Offset local) {
    if (_dragFrom == null) return;
    setState(() => _dragPosition = local);
  }

  /// Ends a drag: the piece is dropped, and the caller is told where it went if that is a square
  /// other than the one it was picked up on. Releasing on the origin square or off the board reports
  /// nothing, and no tap is invented in its place — the finger did not tap.
  void _endDrag(XiangqiBoardGeometry geometry) {
    final from = _dragFrom;
    final at = _dragPosition;
    if (from != null || at != null) {
      setState(() {
        _dragFrom = null;
        _dragPosition = null;
      });
    }
    final onDragMove = widget.onDragMove;
    if (from == null || at == null || onDragMove == null) return;
    final to = geometry.squareAt(at, widget.orientation);
    if (to != null && to != from) onDragMove(from, to);
  }

  void _cancelDrag() {
    if (_dragFrom == null && _dragPosition == null) return;
    setState(() {
      _dragFrom = null;
      _dragPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tap = widget.onTapSquare;
    final drag = widget.onDragMove;
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = XiangqiBoardGeometry.fit(
          constraints.biggest,
          showCoordinates: widget.showCoordinates,
        );
        return Center(
          child: GestureDetector(
            behavior: .opaque,
            // The drag begins where the finger came down and not where the pan was recognised,
            // which is a third of a square away: the piece picked up is the one under the touch.
            dragStartBehavior: .down,
            onTapUp: tap == null
                ? null
                : (details) {
                    final square = geometry.squareAt(details.localPosition, widget.orientation);
                    if (square != null) tap(square);
                  },
            // A board that cannot report where a piece was dropped does not pick one up: with no
            // [XiangqiBoard.onDragMove] there is nothing a drag could do, and a piece rising under
            // the finger and sinking again would be a gesture with no meaning.
            onPanStart: drag == null
                ? null
                : (details) => _startDrag(geometry, details.localPosition),
            onPanUpdate: drag == null ? null : (details) => _updateDrag(details.localPosition),
            onPanEnd: drag == null ? null : (details) => _endDrag(geometry),
            onPanCancel: drag == null ? null : _cancelDrag,
            child: () {
              final boardWidget = CustomPaint(
                size: Size(geometry.width, geometry.height),
                painter: XiangqiBoardPainter(
                  geometry: geometry,
                  position: widget.position,
                  orientation: widget.orientation,
                  selected: widget.selected,
                  moves: widget.moves,
                  lastMove: widget.lastMove,
                  isCheck: isCheck(widget.position),
                  style: widget.style,
                  showLastMove: widget.showLastMove,
                  showBorder: widget.showBorder,
                  hint: widget.hint,
                  arrows: widget.arrows,
                  magnifyDraggedPiece: widget.magnifyDraggedPiece,
                  dragTargetKind: widget.dragTargetKind,
                  blindfoldMode: widget.blindfoldMode,
                  translating: _translating,
                  fading: _fading,
                  translation: _translation,
                  fade: _fade,
                  dragFrom: _dragFrom,
                  dragPosition: _dragPosition,
                ),
              );
              final bgImage = widget.style.backgroundImage;
              if (bgImage != null) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(widget.showBorder ? geometry.cell * 0.16 : 0),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        // The board assets are complete 8x8 chessboards, not seamless material
                        // tiles. A xiangqi board is one continuous field, so showing the whole
                        // photograph would put an eight-by-eight checker pattern underneath a
                        // nine-by-ten grid. Show only the top-left light square instead: an
                        // OverflowBox lays the complete image out at eight times the board's size,
                        // and the Stack clips away everything except that first square.
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: geometry.width * 8,
                            maxWidth: geometry.width * 8,
                            minHeight: geometry.height * 8,
                            maxHeight: geometry.height * 8,
                            child: Image(
                              image: bgImage,
                              width: geometry.width * 8,
                              height: geometry.height * 8,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      boardWidget,
                    ],
                  ),
                );
              }
              return boardWidget;
            }(),
          ),
        );
      },
    );
  }
}

/// Draws a board and everything on it, the pieces that are being animated included.
///
/// Public, with the pieces being animated opened up, for the same reason chessground's painters
/// are: pieces here are `CustomPaint` output and not widgets, so a test has no key to find them by
/// and this is its only door onto what is halfway through a move.
class XiangqiBoardPainter({
  required final XiangqiBoardGeometry geometry,
  required final XiangqiPosition position,
  required final XiangqiSide orientation,
  required final XiangqiSquare? selected,
  required final IList<XiangqiMove> moves,
  required final XiangqiMove? lastMove,
  required final bool isCheck,
  required final XiangqiBoardStyle style,
  required final bool showLastMove,
  required final bool showBorder,
  required final XiangqiMove? hint,
  required final IList<XiangqiBoardArrow> arrows,
  required final bool magnifyDraggedPiece,
  required final DragTargetKind dragTargetKind,
  required final bool blindfoldMode,
  required final IList<XiangqiTranslatingPiece> _translating,
  required final IList<XiangqiFadingPiece> _fading,
  required final Animation<double> _translation,
  required final Animation<double> _fade,
  required final XiangqiSquare? dragFrom,
  required final Offset? dragPosition,
}) extends CustomPainter {
  this : super(repaint: Listenable.merge([_translation, _fade]));

  /// The pieces travelling between squares in the move being drawn, empty when none is.
  @visibleForTesting
  IList<XiangqiTranslatingPiece> get translating => _translating;

  /// The pieces fading out of the squares they were captured on.
  @visibleForTesting
  IList<XiangqiFadingPiece> get fading => _fading;

  double get cell => geometry.cell;

  @override
  void paint(Canvas canvas, Size size) {
    paintSurface(canvas);
    paintGrid(canvas);
    paintCoordinates(canvas);
    paintMarks(canvas);
    paintLastMove(canvas);
    paintCheck(canvas);
    paintTargets(canvas);
    paintSelection(canvas);
    paintPieces(canvas);
    paintTranslating(canvas);
    paintFading(canvas);
    paintHint(canvas);
    paintArrows(canvas);
    paintDragTarget(canvas);
    paintDraggedPiece(canvas);
  }

  /// The wooden board itself: a darker frame around a lighter field, or, with no frame wanted, one
  /// field filling the lot.
  void paintSurface(Canvas canvas) {
    final board = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, geometry.width, geometry.height),
      Radius.circular(cell * 0.16),
    );
    // A theme with a photograph is the board's own material and is left showing: nothing is laid
    // over it but the lines, exactly as the chessboard shows the same photograph behind its pieces.
    // The frame is the one thing added, a line around the edge so the board has a border of its own
    // rather than the photograph running off it.
    if (style.backgroundImage != null) {
      if (showBorder) {
        canvas.drawRRect(
          board,
          Paint()
            ..color = style.frame.withValues(alpha: 0.75)
            ..style = .stroke
            ..strokeWidth = math.max(1.5, cell * 0.05),
        );
      }
      return;
    }

    if (!showBorder) {
      canvas.drawRRect(board, Paint()..color = style.surface);
      return;
    }
    canvas.drawRRect(board, Paint()..color = style.frame);
    canvas.drawRRect(
      RRect.fromRectAndRadius(board.outerRect.deflate(cell * 0.12), Radius.circular(cell * 0.08)),
      Paint()..color = style.surface,
    );
  }

  /// The ninety points and the eight lines through them: nine files, ten ranks, the two palaces'
  /// diagonals, and the seven inner files cut in two by the river.
  void paintGrid(Canvas canvas) {
    final line = Paint()
      ..color = style.ink
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
    // is what tells a printed board apart from a sheet of paper with lines on it. It belongs to the
    // frame, so turning the frame off leaves the grid's own boundary and takes the second line with
    // it — otherwise the switch would change the wood underneath while leaving the outline that
    // reads as the border still drawn.
    if (showBorder) {
      canvas.drawRect(
        Rect.fromPoints(geometry.pointAt(0, 9), geometry.pointAt(8, 0)).inflate(cell * 0.1),
        Paint()
          ..color = style.ink
          ..style = .stroke
          ..strokeWidth = math.max(1, cell * 0.014),
      );
    }

    // Both palaces: the two diagonals of each, drawn from the corners of the three by three they
    // sit in.
    for (final corner in [0, 7]) {
      canvas.drawLine(geometry.pointAt(3, corner), geometry.pointAt(5, corner + 2), line);
      canvas.drawLine(geometry.pointAt(5, corner), geometry.pointAt(3, corner + 2), line);
    }
  }

  /// The digits for the nine files, printed under the bottom rank.
  ///
  /// Each digit is [xiangqiFileDigit] for the side at the bottom, so it is that side's own way of
  /// naming the file, and the reversal between the two sides — red counts 一 from its right, black
  /// counts 1 from its own, and the board counts a to i from the left — is made there and nowhere
  /// else. The digits are laid out in file order, left to right, so the whole line is read in file
  /// order as printed on the board.
  ///
  /// There is no matching axis down the sides. A traditional board numbers the files alone; the
  /// ranks have no convention to follow, and inventing one would have the app tell the player
  /// something about the game that is not true, so the sides carry nothing.
  void paintCoordinates(Canvas canvas) {
    if (!geometry.showCoordinates) return;
    final textStyle = TextStyle(
      color: style.ink,
      fontSize: cell * 0.38,
      fontWeight: FontWeight.bold,
      fontFamilyFallback: _cjkFallback,
    );
    // The middle of the clear band between the bottom rank and the frame's lower edge: below the
    // bottom pieces, which reach a piece radius past the rank line, and above the board's edge.
    final y = geometry.height - (geometry.pad - geometry.pieceRadius) / 2;
    for (var file = 0; file <= 8; file++) {
      paintText(
        canvas,
        xiangqiFileDigit(orientation, file),
        textStyle,
        Offset(geometry.pointAt(file, 0).dx, y),
      );
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
      color: style.riverInk,
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
      ..color = style.ink
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
  /// own marker. The shape and colours are the chess board's last-move highlight, mapped onto a
  /// board whose squares meet at points rather than filling a grid.
  void paintLastMove(Canvas canvas) {
    final move = lastMove;
    if (!showLastMove || move == null) return;
    for (final square in [move.from, move.to]) {
      _paintSquareHighlight(canvas, geometry.centerOf(square, orientation), style.lastMove);
    }
  }

  /// Draws one chess-board highlight over one xiangqi point.
  ///
  /// The square is centred on the point, because that is where a xiangqi piece stands. At an edge
  /// the square is clipped to the board, exactly as the chess board clips a highlight at its own
  /// edge. Theme images are supported too, so image-only chessboard themes keep their material.
  void _paintSquareHighlight(Canvas canvas, Offset centre, HighlightDetails details) {
    final board = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, geometry.width, geometry.height),
      Radius.circular(cell * 0.16),
    );
    final rect = Rect.fromCenter(center: centre, width: cell, height: cell);
    canvas.save();
    canvas.clipRRect(board);
    if (details.solidColor case final color?) {
      canvas.drawRect(rect, Paint()..color = color);
    }
    if (details.image case final image?) {
      final loaded = ChessgroundImages.instance.get(image);
      if (loaded != null) {
        final src = Rect.fromLTWH(0, 0, loaded.width.toDouble(), loaded.height.toDouble());
        canvas.drawImageRect(loaded, src, rect, Paint()..filterQuality = FilterQuality.medium);
      }
    }
    canvas.restore();
  }

  /// A red glow behind the general that is in check — bright at the piece and fading out — with a
  /// fine ring at its rim. The glow is the chess board's own blurred radial check mark, translated
  /// into this board's palette.
  void paintCheck(Canvas canvas) {
    if (!isCheck) return;
    final king = XiangqiPiece(position.turn, .king);
    for (var index = 0; index < kXiangqiSquares; index++) {
      if (position.board[index] == king) {
        final centre = geometry.centerOf(XiangqiSquare(index), orientation);
        final radius = geometry.pieceRadius * 1.25;
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..shader = ui.Gradient.radial(centre, radius, [
              style.checkGlow,
              style.checkGlow.withValues(alpha: 0),
            ]),
        );
        canvas.drawCircle(
          centre,
          geometry.pieceRadius * 1.08,
          Paint()
            ..color = style.checkRing
            ..style = .stroke
            ..strokeWidth = cell * 0.025,
        );
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..color = style.checkRing.withValues(alpha: 0.4)
            ..style = .stroke
            ..strokeWidth = cell * 0.012,
        );
        return;
      }
    }
  }

  /// The squares whose pieces the board draws from the position itself, in board order: every
  /// occupied square that the move being drawn and the piece under the finger are not drawing
  /// somewhere else. Empty while [blindfoldMode] is set.
  ///
  /// The pieces are `CustomPaint` output with no key to find them by, so this is the door a test
  /// has onto them, and it is the same set [paintPieces] walks.
  @visibleForTesting
  IList<XiangqiSquare> get drawnPieceSquares {
    if (blindfoldMode) return const IListConst([]);
    // The two pieces that are being drawn somewhere else this frame: the one arriving on its
    // destination is the translating piece, and the one under the finger is the dragged piece.
    // Drawing them here as well would show two of each.
    final arrivingAt = {for (final moving in _translating) moving.to};
    final dragFrom = this.dragFrom;
    return [
      for (var index = 0; index < kXiangqiSquares; index++)
        if (!arrivingAt.contains(XiangqiSquare(index)) &&
            XiangqiSquare(index) != dragFrom &&
            position.board[index] != null)
          XiangqiSquare(index),
    ].lock;
  }

  void paintPieces(Canvas canvas) {
    for (final square in drawnPieceSquares) {
      paintPiece(canvas, geometry.centerOf(square, orientation), position.pieceAt(square)!);
    }
  }

  /// One piece, centred on [centre] and drawn at [scale] of its usual size.
  ///
  /// A one-line delegate to [paintXiangqiPiece], which is where the drawing lives: the board editor's
  /// palette draws pieces too, and a palette that drew them any other way would be showing the player
  /// a piece the board would not.
  void paintPiece(
    Canvas canvas,
    Offset centre,
    XiangqiPiece piece, {
    double scale = 1,
    bool dropShadow = true,
  }) => paintXiangqiPiece(
    canvas,
    centre,
    piece,
    cell: cell,
    style: style,
    scale: scale,
    dropShadow: dropShadow,
  );

  /// The pieces a move has travelling: each is the one piece that moved, drawn partway between the
  /// square it left and the square it is arriving on. Every other piece is drawn straight from the
  /// position, so this is the only thing the animation moves.
  void paintTranslating(Canvas canvas) {
    if (blindfoldMode) return;
    final t = _translation.value;
    for (final moving in _translating) {
      paintPiece(
        canvas,
        Offset.lerp(
          geometry.centerOf(moving.from, orientation),
          geometry.centerOf(moving.to, orientation),
          t,
        )!,
        moving.piece,
      );
    }
  }

  /// The piece a capture is taking. It is already gone from the position, so it is drawn from the
  /// record of the move instead, fading out where it stood while the taking piece arrives on top
  /// of it.
  void paintFading(Canvas canvas) {
    if (blindfoldMode) return;
    if (_fading.isEmpty) return;
    final opacity = 1 - _fade.value;
    if (opacity <= 0) return;
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, geometry.width, geometry.height),
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    for (final gone in _fading) {
      paintPiece(canvas, geometry.centerOf(gone.square, orientation), gone.piece);
    }
    canvas.restore();
  }

  /// What the selected piece may play: the chess board's own two destination marks, mapped from
  /// squares to points. An empty point gets the same filled dot; an occupied one gets the same
  /// clipped ring around the piece.
  void paintTargets(Canvas canvas) {
    final fillPaint = Paint()..color = style.target;
    final strokePaint = Paint()
      ..color = style.target
      ..strokeWidth = cell / 5
      ..style = .stroke;
    for (final move in moves) {
      final centre = geometry.centerOf(move.to, orientation);
      final rect = Rect.fromCenter(center: centre, width: cell, height: cell);
      if (position.pieceAt(move.to) == null) {
        canvas.drawCircle(centre, cell / 6, fillPaint);
      } else {
        canvas.save();
        canvas.clipRect(rect);
        canvas.drawCircle(centre, cell - (cell / 3), strokePaint);
        canvas.restore();
      }
    }
  }

  /// The chess board's selection highlight, under the picked-up piece and under the point a drag
  /// began on: both say the same thing, that this is the piece the player is holding.
  void paintSelection(Canvas canvas) {
    for (final square in [selected, dragFrom]) {
      if (square == null) continue;
      _paintSquareHighlight(canvas, geometry.centerOf(square, orientation), style.selected);
    }
  }

  /// A translucent circle on the square a hinted move would be played from, over the pieces so
  /// that it is never hidden.
  ///
  /// A circle and not an arrow: the chess game's own hint is a single circle on one square (see
  /// `offline_computer_game_screen.dart`), and a xiangqi hint matching it is the whole point of
  /// this one.
  void paintHint(Canvas canvas) {
    final hint = this.hint;
    if (hint == null) return;
    // When the hint is also drawn as an arrow, the circle borrows that arrow's colour: the two are
    // one annotation, and a blue circle under a green arrow would look like two different hints.
    var color = style.hint;
    for (final arrow in arrows) {
      if (arrow.move == hint) {
        color = (arrow.color ?? style.hint).withValues(alpha: arrow.opacity);
        break;
      }
    }
    final centre = geometry.centerOf(hint.from, orientation);
    final radius = geometry.pieceRadius * 1.18;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(centre, radius, [
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0.0),
        ]),
    );
    canvas.drawCircle(
      centre,
      geometry.pieceRadius * 1.08,
      Paint()
        ..color = color
        ..style = .stroke
        ..strokeWidth = cell * 0.03,
    );
  }

  /// The engine's moves as arrows: a shaft from the piece to move and a solid head at its
  /// destination.
  ///
  /// The endpoints are shortened by a fraction of a piece so that an arrow begins on the piece and
  /// ends at the point it is going to, rather than running through both characters. They are
  /// measured with [XiangqiBoardGeometry.centerOf], so turning the board turns the arrows with it.
  void paintArrows(Canvas canvas) {
    for (final arrow in arrows) {
      final from = geometry.centerOf(arrow.move.from, orientation);
      final to = geometry.centerOf(arrow.move.to, orientation);
      final delta = to - from;
      final distance = delta.distance;
      if (distance < cell * 0.2) continue;

      final direction = delta / distance;
      final start = from + direction * (geometry.pieceRadius * 0.75);
      final tip = to - direction * (geometry.pieceRadius * 0.82);
      final shaftLength = (tip - start).distance;
      if (shaftLength < cell * 0.08) continue;

      final headLength = math.min(cell * 0.30, shaftLength * 0.38);
      final headHalfWidth = math.min(cell * 0.20, shaftLength * 0.24);
      final shaftEnd = tip - direction * headLength;
      final normal = Offset(-direction.dy, direction.dx);
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(shaftEnd.dx + normal.dx * headHalfWidth, shaftEnd.dy + normal.dy * headHalfWidth)
        ..lineTo(shaftEnd.dx - normal.dx * headHalfWidth, shaftEnd.dy - normal.dy * headHalfWidth)
        ..close();

      final color = (arrow.color ?? style.hint).withValues(alpha: arrow.opacity);
      final shadow = Paint()
        ..color = const Color(0x33000000)
        ..strokeWidth = cell * 0.085
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.025);
      final shadowOffset = Offset(0, cell * 0.018);
      canvas.drawLine(start + shadowOffset, shaftEnd + shadowOffset, shadow);
      canvas.save();
      canvas.translate(shadowOffset.dx, shadowOffset.dy);
      canvas.drawPath(head, Paint()..color = const Color(0x33000000));
      canvas.restore();

      final line = Paint()
        ..color = color
        ..strokeWidth = cell * 0.072
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, shaftEnd, line);
      canvas.drawPath(head, Paint()..color = color);
    }
  }

  /// The box the drag target fills: two cells across for a [DragTargetKind.circle] and one for a
  /// [DragTargetKind.square], centred on the point the finger is over. Null when there is no drag
  /// in flight, the finger is off the board, or [dragTargetKind] is [DragTargetKind.none], and
  /// nothing is drawn.
  ///
  /// Both shapes are described by the box around them, which is what lets a test hold the drawn
  /// target against the kind and the size the setting asked for with no canvas to read.
  @visibleForTesting
  Rect? get dragTargetBounds {
    final kind = dragTargetKind;
    final at = dragPosition;
    if (kind == .none || dragFrom == null || at == null) return null;
    final square = geometry.squareAt(at, orientation);
    if (square == null) return null;
    final side = kind == .circle ? cell * 2 : cell;
    return Rect.fromCenter(
      center: geometry.centerOf(square, orientation),
      width: side,
      height: side,
    );
  }

  /// The highlight on the square a dragged piece is over, under the piece but over the board and
  /// everything drawn on it.
  ///
  /// This is chessground's drag target: the same translucent black, the same circle or square, and
  /// the same size. It is deliberately not the legal-move colour; on both boards, a drag target is
  /// the finger's shadow while a legal destination is the game's own mark.
  void paintDragTarget(Canvas canvas) {
    final bounds = dragTargetBounds;
    if (bounds == null) return;
    final paint = Paint()..color = const Color(0x33000000);
    if (dragTargetKind == DragTargetKind.circle) {
      canvas.drawCircle(bounds.center, cell, paint);
    } else {
      canvas.drawRect(bounds, paint);
    }
  }

  /// The scale the dragged piece is drawn at: the board's own enlarged size while
  /// [magnifyDraggedPiece] is set, its usual size otherwise.
  @visibleForTesting
  double get draggedPieceScale => magnifyDraggedPiece ? _draggedScale : 1.0;

  /// The point the dragged piece is centred on: the touch point itself, or a cell above it while
  /// the piece is magnified and lifted clear of the finger. Null when no drag is in flight.
  @visibleForTesting
  Offset? get draggedPieceCentre {
    final at = dragPosition;
    if (at == null || dragFrom == null) return null;
    return magnifyDraggedPiece ? at - Offset(0, cell) : at;
  }

  /// The piece under the player's finger: a little larger than the rest and lifted clear of the
  /// finger, or, with [magnifyDraggedPiece] off, its usual size exactly under the touch.
  ///
  /// A dragged piece is not a translating one. Dragging is the player's hand moving a piece and
  /// animating is the engine drawing a move the board has already been given, and the two are never
  /// happening at once: nothing arrives from a drag until the caller plays it back as a position.
  ///
  /// The lift is a whole cell, this board's own square: the chess board lifts the piece under the
  /// finger by one of its squares, so both games leave the piece clear of the touch point by the
  /// same one-square step.
  void paintDraggedPiece(Canvas canvas) {
    if (blindfoldMode) return;
    final from = dragFrom;
    final centre = draggedPieceCentre;
    if (from == null || centre == null) return;
    final piece = position.pieceAt(from);
    if (piece == null) return;
    final scale = draggedPieceScale;
    if (magnifyDraggedPiece) {
      canvas.drawCircle(
        centre,
        geometry.pieceRadius * scale,
        Paint()
          ..color = _dragShadowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * _dragShadowBlur),
      );
    }
    // The lifted piece casts the deeper shadow above; its resting shadow is left off so the two
    // never stack.
    paintPiece(canvas, centre, piece, scale: scale, dropShadow: !magnifyDraggedPiece);
  }

  /// Writes [text] centred on [centre].
  void paintText(Canvas canvas, String text, TextStyle style, Offset centre) =>
      _paintXiangqiText(canvas, text, style, centre);

  @override
  bool shouldRepaint(covariant XiangqiBoardPainter oldDelegate) =>
      oldDelegate.geometry.cell != geometry.cell ||
      oldDelegate.geometry.showCoordinates != geometry.showCoordinates ||
      oldDelegate.position != position ||
      oldDelegate.orientation != orientation ||
      oldDelegate.selected != selected ||
      oldDelegate.moves != moves ||
      oldDelegate.lastMove != lastMove ||
      oldDelegate.isCheck != isCheck ||
      oldDelegate.style != style ||
      oldDelegate.showLastMove != showLastMove ||
      oldDelegate.showBorder != showBorder ||
      oldDelegate.hint != hint ||
      oldDelegate.arrows != arrows ||
      oldDelegate.magnifyDraggedPiece != magnifyDraggedPiece ||
      oldDelegate.dragTargetKind != dragTargetKind ||
      oldDelegate.blindfoldMode != blindfoldMode ||
      oldDelegate.dragFrom != dragFrom ||
      oldDelegate.dragPosition != dragPosition ||
      oldDelegate._translating != _translating ||
      oldDelegate._fading != _fading;
}

bool _onBoard(int file, int rank) => file >= 0 && file <= 8 && rank >= 0 && rank <= 9;
