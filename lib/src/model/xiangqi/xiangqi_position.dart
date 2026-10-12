import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:meta/meta.dart';

/// Nine files (a to i) by ten ranks (0 to 9).
const int kXiangqiSquares = 90;

/// The position every game starts from.
const String kXiangqiInitialFen =
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

/// Which side a piece belongs to, and whose turn it is.
///
/// Red and black rather than white and black: those are the names the two sides have in Chinese
/// (红方 and 黑方), they are what the pieces are called, and they are the convention the whole of
/// the game's written material — FEN, notation, the board's usual orientation — is in. Red moves
/// first.
enum XiangqiSide() {
  red,
  black;

  /// The other side, which is also the side that moves next.
  XiangqiSide get opposite => this == red ? black : red;

  /// What the side is called where a player has to be told about it — the side picker, and the
  /// sentences that say who was mated, who resigned, and which side was left without a move.
  ///
  /// Translated, unlike the characters on the pieces: those are the game's own letters (帅 and 将,
  /// 兵 and 卒) and cannot be spelled any other way, while this is the app speaking about a side and
  /// so is written in the reader's language, exactly as the difficulty labels beside it are
  /// (`mobileXiangqiEasy` and its neighbours). The localizations are taken as an argument because a
  /// model cannot read a `BuildContext`; `dragTargetKindLabel` in `board_preferences.dart` takes
  /// them the same way.
  String label(AppLocalizations l10n) =>
      this == red ? l10n.mobileXiangqiSideRed : l10n.mobileXiangqiSideBlack;
}

/// The seven kinds of piece.
///
/// The names are English so that code reads, the characters on the board are Chinese — see
/// [XiangqiPiece.glyph]. A piece never changes kind: there is no promotion and nothing is ever
/// dropped back onto the board, so its kind and its side describe it completely.
enum XiangqiPieceType() {
  /// The general (帅/将): one step orthogonally, and never out of the palace.
  king,

  /// The advisor (仕/士): one step diagonally, and never out of the palace.
  advisor,

  /// The elephant (相/象): two steps diagonally, and never across the river.
  bishop,

  /// The horse (马): the knight's move, except that a piece beside it can block the jump.
  knight,

  /// The chariot (车): the rook, in all respects.
  rook,

  /// The cannon (炮): the rook's move, except that it captures only over exactly one screen.
  cannon,

  /// The soldier (兵/卒): one step forward, and sideways as well once it has crossed the river.
  pawn,
}

/// One piece: a kind and the side it belongs to.
@immutable
final class const XiangqiPiece(final XiangqiSide side, final XiangqiPieceType type) {
  /// The piece written by [char] in FEN — `K` to `P` for red, `k` to `p` for black — or null if
  /// the character is not a piece at all.
  static XiangqiPiece? fromFenChar(String char) {
    final type = switch (char.toLowerCase()) {
      'k' => XiangqiPieceType.king,
      'a' => XiangqiPieceType.advisor,
      'b' => XiangqiPieceType.bishop,
      'n' => XiangqiPieceType.knight,
      'r' => XiangqiPieceType.rook,
      'c' => XiangqiPieceType.cannon,
      'p' => XiangqiPieceType.pawn,
      _ => null,
    };
    if (type == null) return null;
    return XiangqiPiece(char == char.toLowerCase() ? .black : .red, type);
  }

  /// This piece as FEN writes it: red's pieces in capitals, black's in lower case.
  String get fenChar {
    final letter = switch (type) {
      .king => 'k',
      .advisor => 'a',
      .bishop => 'b',
      .knight => 'n',
      .rook => 'r',
      .cannon => 'c',
      .pawn => 'p',
    };
    return side == .red ? letter.toUpperCase() : letter;
  }

  /// The character drawn on the piece.
  ///
  /// The two sides write four of the seven kinds differently — a red general is 帅 and a black one
  /// is 将, a red soldier 兵 and a black one 卒 — which is why this is a property of the piece
  /// rather than of its kind, and why a board painter reads it and nothing else.
  String get glyph => switch (type) {
    .king => side == .red ? '帅' : '将',
    .advisor => side == .red ? '仕' : '士',
    .bishop => side == .red ? '相' : '象',
    .knight => '马',
    .rook => '车',
    .cannon => '炮',
    .pawn => side == .red ? '兵' : '卒',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is XiangqiPiece && other.side == side && other.type == type;

  @override
  int get hashCode => Object.hash(side, type);

  @override
  String toString() => fenChar;
}

/// One of the ninety intersections a piece can stand on.
///
/// Files run a to i, left to right as red sees it; ranks run 0 to 9, from red's back row up to
/// black's. So a square name is two characters (`d0`, `e9`) and is at once the FEN convention and
/// ICCS — a move prints as `h2e2` with nothing translated anywhere.
///
/// FEN is the one thing that disagrees: it writes the ranks top down, black's back rank first.
/// [XiangqiPosition.toFen] is the only place that has to remember it.
@immutable
final class const XiangqiSquare(final int index) {
  /// The square [file] (0 to 8, a to i) along and [rank] (0 to 9) up.
  const new at(int file, int rank) : this(rank * 9 + file);

  /// The square named [name], `a0` to `i9`, or null if it is not one.
  static XiangqiSquare? parse(String name) {
    if (name.length != 2) return null;
    final file = name.codeUnitAt(0) - 0x61;
    final rank = name.codeUnitAt(1) - 0x30;
    if (file < 0 || file > 8 || rank < 0 || rank > 9) return null;
    return XiangqiSquare.at(file, rank);
  }

  /// 0 to 89, counting [file] fastest — the index [XiangqiPosition.board] is kept in.
  ///
  /// Every square this class hands out comes from [XiangqiSquare.at] or [parse], both of which
  /// stay inside the ninety, so nothing here checks the range. The field is public because the
  /// rules work in these indices directly; nothing outside them has a reason to build one.
  ///
  /// 0 to 8, a to i.
  int get file => index % 9;

  /// 0 to 9, red's back row being 0.
  int get rank => index ~/ 9;

  /// The square's name, `a0` to `i9`.
  String get name => '${String.fromCharCode(0x61 + file)}$rank';

  /// Whether the square is in [side]'s palace: the three centre files, and the side's three back
  /// ranks. Nothing but a general or an advisor ever stands there, and both are confined to it.
  bool inPalaceOf(XiangqiSide side) =>
      file >= 3 && file <= 5 && (side == .red ? rank <= 2 : rank >= 7);

  /// Whether the square is in [side]'s half of the river. The river itself is the gap between
  /// ranks 4 and 5, so a piece has crossed it exactly when it is not on its own half.
  ///
  /// This one test answers three questions the rules ask: where an elephant may go, whether a
  /// soldier may step sideways, and which way is forward.
  bool onOwnHalf(XiangqiSide side) => side == .red ? rank <= 4 : rank >= 5;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is XiangqiSquare && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => name;
}

/// A xiangqi position: where every piece is, whose turn it is, and how far the game has got.
///
/// A value, and immutable: two positions with the same pieces and the same side to move are equal.
/// That equality is what the repetition rule is written against, so the move counters are
/// deliberately *not* part of it — the same position reached on move 12 and on move 40 is still
/// the same position, and the third time it appears the game is drawn.
///
/// The board is a flat list of ninety indexed by [XiangqiSquare.index] rather than a map, because
/// nearly every question the rules ask is "what is on this square?" and a list answers that in one
/// load.
@immutable
final class const XiangqiPosition({
  /// The ninety squares, by [XiangqiSquare.index].
  ///
  /// Every way of making a position — [initial], [fromFen], and the moves of a game — keeps it
  /// ninety long and keeps both generals on it. Nothing here checks either, because the rules read
  /// a missing general as a general that cannot be attacked.
  required final IList<XiangqiPiece?> board,

  /// The side to move.
  required final XiangqiSide turn,

  /// How many half-moves since the last capture.
  final int halfmoveClock = 0,

  /// The move number, counting both sides' moves as one — it goes up after black has moved.
  final int fullmoveNumber = 1,
}) {
  /// The position every game starts from, red to move.
  factory initial() => XiangqiPosition.fromFen(kXiangqiInitialFen);

  /// Parses [fen].
  ///
  /// The format is the one every xiangqi engine writes and reads — Pikafish's, and so the one to
  /// log positions in: the ten ranks from black's back rank down, then `w` or `b` for the side to
  /// move, then the two chess-only fields left as `-`, then the half-move and move counters.
  ///
  /// Throws a [FormatException] on anything that is not a board and a side. It deliberately does
  /// not police the *position*, which is a different matter: an engine rejects a board with three
  /// cannons or with the side not to move already in check, because it has to evaluate one, while
  /// this only ever has to move pieces around. Every position that parses here is a position that
  /// can be played, and every position that can be played is worth being able to set up.
  factory fromFen(String fen) {
    final fields = fen.trim().split(RegExp(r'\s+'));
    if (fields.length < 2) {
      throw FormatException('A position needs a board and a side to move', fen);
    }

    final ranks = fields[0].split('/');
    if (ranks.length != 10) {
      throw FormatException('Expected 10 ranks, got ${ranks.length}', fen);
    }

    final board = List<XiangqiPiece?>.filled(kXiangqiSquares, null);
    for (var i = 0; i < ranks.length; i++) {
      // FEN writes black's back rank first and this board counts ranks from red's back rank up.
      final rank = 9 - i;
      var file = 0;
      for (final char in ranks[i].split('')) {
        final digit = int.tryParse(char);
        if (digit != null) {
          file += digit;
          continue;
        }
        final piece = XiangqiPiece.fromFenChar(char);
        if (piece == null) throw FormatException('Not a piece: "$char"', fen);
        if (file >= 9) throw FormatException('Rank $rank runs past the ninth file', fen);
        board[XiangqiSquare.at(file, rank).index] = piece;
        file++;
      }
      if (file != 9) throw FormatException('Rank $rank has $file files, not 9', fen);
    }

    final turn = switch (fields[1]) {
      'w' => XiangqiSide.red,
      'b' => XiangqiSide.black,
      _ => throw FormatException('Not a side to move: "${fields[1]}"', fen),
    };

    return XiangqiPosition(
      board: board.lock,
      turn: turn,
      // The two fields before these are chess-only and are written as `-`; they are skipped.
      halfmoveClock: fields.length > 4 ? int.tryParse(fields[4]) ?? 0 : 0,
      fullmoveNumber: fields.length > 5 ? int.tryParse(fields[5]) ?? 1 : 1,
    );
  }

  /// What is on [square], or null if it is empty.
  XiangqiPiece? pieceAt(XiangqiSquare square) => board[square.index];

  /// The position written the way FEN writes it.
  String toFen() {
    final ranks = <String>[];
    for (var rank = 9; rank >= 0; rank--) {
      final buffer = StringBuffer();
      var empty = 0;
      for (var file = 0; file < 9; file++) {
        final piece = board[XiangqiSquare.at(file, rank).index];
        if (piece == null) {
          empty++;
          continue;
        }
        if (empty > 0) {
          buffer.write(empty);
          empty = 0;
        }
        buffer.write(piece.fenChar);
      }
      if (empty > 0) buffer.write(empty);
      ranks.add(buffer.toString());
    }
    final side = turn == .red ? 'w' : 'b';
    return '${ranks.join('/')} $side - - $halfmoveClock $fullmoveNumber';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XiangqiPosition && other.board == board && other.turn == turn;

  @override
  int get hashCode => Object.hash(board, turn);

  @override
  String toString() => toFen();
}
