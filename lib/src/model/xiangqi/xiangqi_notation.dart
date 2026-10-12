import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// Chinese notation: the way a move is written down, and read aloud, by everyone who plays the game.
///
/// A move is written as four things in a row — a piece, the file it stood on, which way it went, and
/// where it ended up — so 炮二平五 is "the cannon on file two, across to file five" and 马8进7 is
/// "the horse on file 8, forward to file 7". There is no capture mark and no ambiguity between a
/// quiet move and a taking one: the square it lands on says that, and nothing else could have been
/// meant.
///
/// This is the notation the app writes, rather than the ICCS coordinates a move already prints as
/// (`h2e2`), because it is the one a Chinese-speaking player reads without decoding. The two never
/// have to be kept in step: ICCS is [XiangqiMove.iccs] and is what the engine gets, and this is what
/// the move list shows.

/// The digits a side writes for the files of its own half of the board, in the order of its own
/// counting.
///
/// Red counts 一 to 九 and black 1 to 9, and both count from their own right — the side of the board
/// each one sits at. The two arrays are the same nine places read from opposite ends, which is why
/// they are not simply the same order: red's file 8 is its 一, black's file 0 is its 1, and neither
/// starts at the file the other starts at. Read a file through [xiangqiFileDigit], which is where
/// that reversal is made; do not index these arrays with a [XiangqiSquare.file] by hand.
///
/// They share one definition with the board: the file axis is [XiangqiSquare.file], 0 to 8, a to i,
/// and these are only how each player names the files on it.
const kXiangqiDigitsRed = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
const kXiangqiDigitsBlack = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

/// The digit [side] writes for [file], one of the files [XiangqiSquare.file] counts.
///
/// This is the one place the board's file axis is turned into a player's numbering, and it needs the
/// reversal the arrays above do not do on their own. The board counts files a to i left to right as
/// red sees it — `a0` is red's left-hand corner — while red counts its own files 一 to 九 from its
/// *right*, so red's file 8 is 一 and its file 0 is 九; the lookup therefore runs the array the
/// other way. Black sits opposite and so counts from the other end: black's file 0 is already its 1,
/// and its lookup is the plain one.
String xiangqiFileDigit(XiangqiSide side, int file) => switch (side) {
  .red => kXiangqiDigitsRed[8 - file],
  .black => kXiangqiDigitsBlack[file],
};

/// The digit [side] writes for the number [count] — how many ranks a piece went, one to nine.
///
/// A count is a number and not a place, so it is the same 一 to 九 on both sides of the river and
/// the arrays are read in their own order: six ranks are 六, whatever side moved.
String xiangqiNumberDigit(XiangqiSide side, int count) => switch (side) {
  .red => kXiangqiDigitsRed[count - 1],
  .black => kXiangqiDigitsBlack[count - 1],
};

/// [move], as it is played in [before], written in Chinese notation.
///
/// [before] is the position **before** the move is played — the notation names the file the piece
/// stood on and which way it went from there, so both the piece and the side that moved are read
/// from the board as it was, and [before].turn is the side that is moving.
///
/// A move that is not a move — `from` and `to` the same square, no piece on `from`, or a piece
/// there that does not belong to [before].turn — comes back as the empty string rather than
/// throwing. It names nothing, and a move list that meets one shows nothing for it instead of
/// stopping: the shape and the string are the only things here, and neither has a piece of truth to
/// fall back on.
String xiangqiMoveNotation(XiangqiPosition before, XiangqiMove move) {
  if (move.from == move.to) return '';
  final piece = before.pieceAt(move.from);
  if (piece == null || piece.side != before.turn) return '';

  // What the piece is called, which is exactly the character the board draws on it: the two sides
  // write four of the seven kinds differently — 帅/将, 仕/士, 相/象, 兵/卒 — and that is a
  // difference the name carries and the board shows, so the two can never disagree.
  final name = piece.glyph;

  // How many of this same piece of this same side stand on the file it is leaving. Two or more of
  // them and the file is not written at all: 前炮平五, not 炮五平五, because the file alone would
  // not say which cannon is meant.
  final sameFileRanks = <int>[];
  for (var rank = 0; rank <= 9; rank++) {
    final other = before.pieceAt(XiangqiSquare.at(move.from.file, rank));
    if (other != null && other.side == piece.side && other.type == piece.type) {
      sameFileRanks.add(rank);
    }
  }

  final String head;
  if (sameFileRanks.length >= 2) {
    // 前 is the piece nearer the opponent, so the file is read from the far end back: red's front is
    // its highest rank, black's its lowest, and the order is the order the player is facing.
    final ordered = piece.side == .red
        ? sameFileRanks.reversed.toList(growable: false)
        : sameFileRanks;
    final index = ordered.indexOf(move.from.rank);
    head = '${_xiangqiFileOrderLabel(index, sameFileRanks.length)}$name';
  } else {
    head = '$name${xiangqiFileDigit(piece.side, move.from.file)}';
  }

  final deltaRank = move.to.rank - move.from.rank;

  // 平 is a move that keeps its rank, and it always says where the piece ends up, on the file it
  // now stands on. A soldier that has crossed the river steps sideways this way, and so does a
  // chariot or a cannon sliding across.
  if (deltaRank == 0) return '$head平${xiangqiFileDigit(piece.side, move.to.file)}';

  // 进 goes towards the opponent and 退 comes back, which is up the board for red and down it for
  // black: forward is the direction each side's own soldiers face.
  final forward = piece.side == .red ? 1 : -1;
  final direction = deltaRank * forward > 0 ? '进' : '退';

  // A piece that leaves its file says where it lands, so the two files it moved between are the
  // whole of the move: 马二进三. A piece that keeps to its file says how far it went instead, and
  // the file is already in the head: 车二进六.
  final target = _xiangqiMovesAcrossFiles(piece.type)
      ? xiangqiFileDigit(piece.side, move.to.file)
      : xiangqiNumberDigit(piece.side, deltaRank.abs());
  return '$head$direction$target';
}

/// The notation for a whole game: one string per move, in order, each written against the position
/// it was played in.
///
/// [positions] holds the position before the first move, then the one before each move after it, so
/// a game of N moves is N + 1 positions; [moves] holds those N moves. The two lists are checked
/// against each other rather than trusted, and a length that is off by anything throws
/// [ArgumentError]: a list of moves and a list of positions that do not line up describe no game,
/// and reading the wrong position for a move would write some other game's notation in silence.
IList<String> xiangqiGameNotation(IList<XiangqiPosition> positions, IList<XiangqiMove> moves) {
  if (positions.length != moves.length + 1) {
    throw ArgumentError.value(
      positions.length,
      'positions',
      'A game of ${moves.length} moves is written against ${moves.length + 1} positions',
    );
  }
  return [for (var i = 0; i < moves.length; i++) xiangqiMoveNotation(positions[i], moves[i])].lock;
}

/// Whether a piece of [type] leaves the file it started on when it moves.
///
/// Three kinds do — the horse, the elephant and the advisor — and for those the notation gives the
/// file the piece lands on, because the distance means nothing on a diagonal. The other four keep
/// to a file — the general, both chariots and the soldier — and for those it gives the number of
/// ranks instead.
bool _xiangqiMovesAcrossFiles(XiangqiPieceType type) => switch (type) {
  .knight || .bishop || .advisor => true,
  .king || .rook || .cannon || .pawn => false,
};

/// What a piece is called when more than one of its kind stands on the file it is leaving.
///
/// [index] counts from the piece nearest the opponent, 0, to the one nearest the mover, [count] - 1.
/// Two pieces are 前 and 后; a third between them is 中; and four or more are 前, 二, 三 … 后, which
/// is how a file of soldiers is written. Only soldiers can ever be that many — a side has two
/// chariots, two cannons and two horses but five soldiers, and they may all cross and come to the
/// same file — and a file is ten ranks long, so the middle numbering never has to reach past 八.
String _xiangqiFileOrderLabel(int index, int count) => switch (count) {
  2 => const ['前', '后'][index],
  3 => const ['前', '中', '后'][index],
  _ when index == 0 => '前',
  _ when index == count - 1 => '后',
  // The ones between the two ends: 二 for the first past 前, then 三, 四, … , the soldier's own way
  // of numbering a file of them.
  _ => kXiangqiDigitsRed[index],
};
