import 'package:chessground/chessground.dart' show EditorPointerMode;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:meta/meta.dart';

/// A provider for [XiangqiBoardEditorController], keyed by the position the editor was opened on.
///
/// The key is the FEN to open on, or null for the position every game starts from. Two editors on
/// two different positions are two different boards and must not share one, which is what the family
/// is for; opening the same position twice — the More tab's row and the analysis board's own action
/// can both do it — finds the same board again.
final xiangqiBoardEditorControllerProvider = NotifierProvider.autoDispose
    .family<XiangqiBoardEditorController, XiangqiBoardEditorState, String?>(
      XiangqiBoardEditorController.new,
      name: 'XiangqiBoardEditorControllerProvider',
    );

/// A position being taken apart on the board editor, and the three things about it that are not
/// part of the position: which way up the board is drawn, what the next touch does, and which piece
/// that touch puts down.
///
/// The position is a [XiangqiPosition] and not a bag of squares, because that is what the editor is
/// editing: every question the screen asks of this state — what is on this square, what does the
/// FEN say, is the board empty — is a question the position already answers, and toFen is total, so
/// there is no state here that has no position behind it. The chess editor keeps its pieces as a map
/// of squares because dartchess's board is one; a xiangqi board is ninety squares in a row and is
/// already the shape to be edited in place.
@immutable
final class const XiangqiBoardEditorState({
  /// The position on the board.
  required final XiangqiPosition position,

  /// The side drawn at the bottom of the screen.
  ///
  /// A way of looking at the board and not a fact about the position, exactly as it is in the game
  /// and analysis screens: red moves first and sits at the bottom until the board is turned round.
  final XiangqiSide orientation = .red,

  /// What a touch on a square does: pick a piece up and drag it, or put one down and take one away.
  final EditorPointerMode editorPointerMode = .drag,

  /// The piece a touch puts on a square in edit mode, or null for a touch that takes a piece away.
  ///
  /// Null means the eraser rather than nothing at all, which is why [copyWith] has a sentinel for it
  /// — see [_keepPieceToAddOnEdit].
  final XiangqiPiece? pieceToAddOnEdit,
}) {
  /// The side to move, which is the position's own and not the editor's.
  XiangqiSide get sideToPlay => position.turn;

  /// The position written the way FEN writes it.
  ///
  /// Total: there is no board this cannot be asked of, so nothing downstream has to check for one —
  /// which is the whole of why the analysis exit can be gated on the board not being empty alone.
  String get fen => position.toFen();

  /// How many pieces are on the board.
  int get pieceCount => position.board.where((piece) => piece != null).length;

  /// The piece a touch in edit mode puts down, or null when a touch takes a piece away.
  XiangqiPiece? get activePieceOnEdit => editorPointerMode == .edit ? pieceToAddOnEdit : null;

  /// Whether the next touch takes a piece off the board.
  bool get deletePiecesActive => editorPointerMode == .edit && pieceToAddOnEdit == null;

  /// This state with the given fields replaced.
  ///
  /// [pieceToAddOnEdit] is an `Object?` rather than a `XiangqiPiece?` for the reason every generated
  /// `copyWith` is: a field left out and a field passed as null cannot be told apart, and this one
  /// has a real use for null — it is the eraser, and picking it up is picking something up that has
  /// to be cleared. Pass [_keepPieceToAddOnEdit] to leave it alone, which is what leaving the
  /// argument out does.
  XiangqiBoardEditorState copyWith({
    XiangqiPosition? position,
    XiangqiSide? orientation,
    EditorPointerMode? editorPointerMode,
    Object? pieceToAddOnEdit = _keepPieceToAddOnEdit,
  }) => XiangqiBoardEditorState(
    position: position ?? this.position,
    orientation: orientation ?? this.orientation,
    editorPointerMode: editorPointerMode ?? this.editorPointerMode,
    pieceToAddOnEdit: identical(pieceToAddOnEdit, _keepPieceToAddOnEdit)
        ? this.pieceToAddOnEdit
        : pieceToAddOnEdit as XiangqiPiece?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XiangqiBoardEditorState &&
          other.position == position &&
          other.orientation == orientation &&
          other.editorPointerMode == editorPointerMode &&
          other.pieceToAddOnEdit == pieceToAddOnEdit;

  @override
  int get hashCode => Object.hash(position, orientation, editorPointerMode, pieceToAddOnEdit);
}

/// The value [XiangqiBoardEditorState.copyWith] treats as "and leave this field alone".
///
/// A constant of its own kind, so that nothing a caller can pass — not even the null that means the
/// eraser — is ever identical to it.
const _keepPieceToAddOnEdit = Object();

/// The state behind the xiangqi board editor: the board it edits, and the few things it does to it.
///
/// The chess editor's controller takes dartchess through and through — variants, castling rights, en
/// passant squares, the legality of a position — and none of that is here because none of it is a
/// xiangqi idea. What is left is small: a position, a side to hand the move to, and four things that
/// change the board. Nothing here knows a rule of the game and nothing here validates anything, for
/// the same reason the chess one does not: the editor's job is to hold a position a player builds,
/// including one no game could reach.
class XiangqiBoardEditorController(final String? initialFen)
    extends Notifier<XiangqiBoardEditorState> {
  @override
  XiangqiBoardEditorState build() {
    final openingFen = initialFen;
    return XiangqiBoardEditorState(
      position: openingFen == null
          ? XiangqiPosition.initial()
          : XiangqiPosition.fromFen(openingFen),
      orientation: .red,
      editorPointerMode: .drag,
      pieceToAddOnEdit: null,
    );
  }

  /// Changes what a touch on a square does.
  ///
  /// [pieceToAddOnEdit] is the piece edit mode puts down, and leaving it out is the eraser. It is
  /// cleared in drag mode too, where it means nothing at all, so that putting a piece down in edit
  /// mode and then dragging one about cannot leave a piece in hand that the next touch would use.
  void updateMode(EditorPointerMode mode, [XiangqiPiece? pieceToAddOnEdit]) {
    state = state.copyWith(editorPointerMode: mode, pieceToAddOnEdit: pieceToAddOnEdit);
  }

  /// Puts a piece on [square], or takes one away.
  ///
  /// A touch with a piece in hand writes that piece, over whatever was there; a touch that finds
  /// that same piece already on the square takes it off instead, so that a second touch undoes the
  /// first. A touch with the eraser in hand always takes a piece off. This is the chess editor's
  /// `editSquare` piece for piece, minus the variant that has to be re-derived when the pieces
  /// change.
  void editSquare(XiangqiSquare square) {
    final piece = state.pieceToAddOnEdit;
    if (piece == null) {
      discardPiece(square);
    } else if (state.position.pieceAt(square) == piece) {
      discardPiece(square);
    } else {
      _setPosition(board: state.position.board.replace(square.index, piece));
    }
  }

  /// Takes whatever is on [square] off the board.
  ///
  /// Taking a piece off an empty square is not an error and changes nothing: the board comes out
  /// equal to the one it started as, and an equal state is one the screen is not rebuilt for.
  void discardPiece(XiangqiSquare square) {
    _setPosition(board: state.position.board.replace(square.index, null));
  }

  /// A drop places a piece; unlike a palette tap it never toggles an identical piece off.
  void placePiece(XiangqiSquare square, XiangqiPiece piece) {
    if (state.position.pieceAt(square) == piece) return;
    _setPosition(board: state.position.board.replace(square.index, piece));
  }

  /// Moves whatever is on [from] to [to].
  ///
  /// The piece is put on [to] whatever is standing there, because a capture and a replacement are
  /// the same thing to an editor that has no rules. A drag that ends where it began is not reported
  /// by the board at all, and is a no-op here as well.
  void movePiece(XiangqiSquare from, XiangqiSquare to) {
    final piece = state.position.pieceAt(from);
    if (piece == null || from == to) return;
    _setPosition(board: state.position.board.replace(from.index, null).replace(to.index, piece));
  }

  /// Turns the board round.
  ///
  /// Only the drawing turns: the position is what it always was, and the side to move is the same
  /// side.
  void flipBoard() {
    state = state.copyWith(orientation: state.orientation.opposite);
  }

  /// Hands the move to [side].
  ///
  /// The one thing the editor can say about the position that putting pieces down cannot, and the
  /// only reason it writes to the side to move at all: everything else about a position is its
  /// board.
  void setSideToPlay(XiangqiSide side) {
    if (side == state.sideToPlay) return;
    _setPosition(turn: side);
  }

  /// Loads [fen].
  ///
  /// A board on its own — ten ranks and their files, with no side to move — is taken as well, and
  /// keeps the side and the counters the editor already had, which is what a player copying a
  /// diagram out of a book has to hand. The chess editor reads a partial FEN the same way. Throws a
  /// [FormatException] on anything else, which is what the FEN dialog catches.
  ///
  /// What is loaded is what was written: unlike the chess editor there is no normalising pass
  /// through a position that drops what cannot be true, because a [XiangqiPosition] has no such
  /// fields to drop. A position that parses is loaded exactly as it parses, counters and all.
  void loadFen(String fen) {
    final fields = fen.trim().split(RegExp(r'\s+'));
    state = state.copyWith(
      position: fields.length == 1
          ? XiangqiPosition.fromFen(
              '${fields[0]} ${state.sideToPlay == .red ? 'w' : 'b'} - - '
              '${state.position.halfmoveClock} ${state.position.fullmoveNumber}',
            )
          : XiangqiPosition.fromFen(fen),
    );
  }

  /// Takes every piece off the board, and changes nothing else.
  ///
  /// The side to move, the counters and which way up the board is are all left as they were: a
  /// cleared board is a board with nothing on it, not a board that has been reset. Putting the
  /// pieces back is [loadFen] with the opening position, which is what the screen's own Start
  /// position does.
  void clearBoard() {
    _setPosition(board: List<XiangqiPiece?>.filled(kXiangqiSquares, null).lock);
  }

  /// The state's position with [board] and [turn] replaced, everything else about it kept.
  ///
  /// The half-move clock and the move number come from whatever position the editor was opened on or
  /// last loaded, and stay there for as long as it is edited: an editor is not a game, there is no
  /// move being played to count, and a position pasted in with a move number should come back out
  /// with the same one.
  void _setPosition({IList<XiangqiPiece?>? board, XiangqiSide? turn}) {
    state = state.copyWith(
      position: XiangqiPosition(
        board: board ?? state.position.board,
        turn: turn ?? state.position.turn,
        halfmoveClock: state.position.halfmoveClock,
        fullmoveNumber: state.position.fullmoveNumber,
      ),
    );
  }
}
