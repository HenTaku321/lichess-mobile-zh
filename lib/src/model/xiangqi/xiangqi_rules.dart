import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// The rules of xiangqi, as pure functions over an immutable [XiangqiPosition].
///
/// Everything here is decided by generating moves and looking at the board: there is no search, no
/// evaluation and no state carried between calls. The one thing worth knowing before reading the
/// implementation is that the flying-general rule is not a rule of its own — see [_isKingAttacked].
///
/// The moves themselves are packed into single ints while they are being generated, which is
/// explained at [_pack]. A [XiangqiMove] only appears at the edge, in the values these functions
/// return.

/// Whether [move] can be played in [position].
///
/// The move list is what decides, so this and [legalMoves] can never disagree.
bool isLegal(XiangqiPosition position, XiangqiMove move) => legalMoves(position).contains(move);

/// Every move the side to move may play, in no particular order.
///
/// "May" in the full sense: a move that would leave one's own general in check — or would leave it
/// facing the enemy general down an open file — is not in this list, and neither is a move that
/// breaks a piece's own rule of movement.
IList<XiangqiMove> legalMoves(XiangqiPosition position) {
  final board = List<XiangqiPiece?>.of(position.board);
  final packed = <int>[];
  _generate(board, position.turn, packed);
  final moves = <XiangqiMove>[];
  for (final move in packed) {
    if (_isLegalAfter(board, move, position.turn)) moves.add(_unpack(move));
  }
  return moves.lock;
}

/// Every move the piece standing on [from] may play — what a board has to shade when a piece is
/// picked up.
IList<XiangqiMove> legalMovesFrom(XiangqiPosition position, XiangqiSquare from) =>
    legalMoves(position).where((move) => move.from == from).toIList();

/// Whether the side to move is in check — its general is under attack, and this move has to answer
/// that.
///
/// The side to move being in check is the normal state of a position, not an impossible one: what
/// the rules forbid is a move that leaves *your own* general attacked, which is the attack by the
/// other side, the one you are not making. So this is the question a board asks when a move arrives
/// and [isCheckmate] asks again after the move list comes back empty.
bool isCheck(XiangqiPosition position) =>
    _isKingAttacked(List<XiangqiPiece?>.of(position.board), position.turn);

/// Whether the side to move has been checkmated, and has therefore lost.
bool isCheckmate(XiangqiPosition position) => isCheck(position) && legalMoves(position).isEmpty;

/// Whether the side to move has no legal move while not being in check, and has therefore lost.
///
/// This is 困毙, and it is a loss, not the draw chess makes of the same situation. Xiangqi's rule
/// is that a player who cannot move loses; there is no stalemate.
bool isStalemate(XiangqiPosition position) => !isCheck(position) && legalMoves(position).isEmpty;

/// Whether the game is over in [position] — [isCheckmate] or [isStalemate], which for the side to
/// move amount to the same thing.
bool isGameOver(XiangqiPosition position) => legalMoves(position).isEmpty;

/// The position after [move].
///
/// Throws [XiangqiIllegalMoveException] if [move] cannot be played here, so a move that came from
/// somewhere other than [legalMoves] is reported rather than quietly applied. The move counters are
/// carried forward the usual way: the half-move clock resets on a capture, and the move number goes
/// up once both sides have moved.
XiangqiPosition play(XiangqiPosition position, XiangqiMove move) {
  if (!isLegal(position, move)) throw XiangqiIllegalMoveException(move);
  final board = List<XiangqiPiece?>.of(position.board);
  final captured = board[move.to.index];
  board[move.to.index] = board[move.from.index];
  board[move.from.index] = null;
  return XiangqiPosition(
    board: board.lock,
    turn: position.turn.opposite,
    halfmoveClock: captured == null ? position.halfmoveClock + 1 : 0,
    fullmoveNumber: position.turn == .black ? position.fullmoveNumber + 1 : position.fullmoveNumber,
  );
}

/// Every move the piece standing on [from] could make, whoever is to move.
///
/// **Not a rule of the game.** [legalMoves] is the side to move's, and a lesson needs more than
/// that: a chapter's script is not a game — measured on 2026-10-16, one chapter asks for two red
/// moves in a row — and the site's own lesson board lets the reader pick up either side's piece and
/// play any move that piece could make. This is that: the piece's own rule of movement, with no
/// question asked about whose turn it is and no question asked about check.
///
/// The one thing it does keep is that a piece cannot land on its own side: that is part of what a
/// piece's move is, not a consequence of whose turn it is.
IList<XiangqiMove> pieceMoves(XiangqiPosition position, XiangqiSquare from) {
  final piece = position.pieceAt(from);
  if (piece == null) return const IListConst([]);
  final board = List<XiangqiPiece?>.of(position.board);
  final packed = <int>[];
  _generate(board, piece.side, packed);
  return [
    for (final move in packed)
      if (_fromOf(move) == from.index) _unpack(move),
  ].lock;
}

/// The position after [move], whether or not it is legal here.
///
/// A lesson's script is not a game, and the site's own player does not ask the rules about the
/// moves it plays on the reader's behalf: it moves the piece, takes whatever was on the square it
/// landed on, and hands the turn to the other side of the piece that moved. That last part is not
/// the same as handing it to the other side of the *position* — a script with two red moves in a
/// row has the second one played while it is still black's turn by the rules — which is exactly why
/// this cannot be [play].
///
/// Everything else in this file refuses a move that is not legal. This is the one door the lesson's
/// script comes through, and it is deliberately not used by games.
XiangqiPosition playForced(XiangqiPosition position, XiangqiMove move) {
  final board = List<XiangqiPiece?>.of(position.board);
  final piece = board[move.from.index];
  final captured = board[move.to.index];
  board[move.to.index] = piece;
  board[move.from.index] = null;
  final side = piece?.side ?? position.turn;
  return XiangqiPosition(
    board: board.lock,
    turn: side.opposite,
    halfmoveClock: captured == null ? position.halfmoveClock + 1 : 0,
    fullmoveNumber: side == .black ? position.fullmoveNumber + 1 : position.fullmoveNumber,
  );
}

/// Thrown by [play] for a move that is not legal in the position.
final class const XiangqiIllegalMoveException(
  /// The move that was refused.
  final XiangqiMove move,
) implements Exception {
  @override
  String toString() => 'Illegal xiangqi move: $move';
}

/// The number of positions reachable from [position] in exactly [depth] moves.
///
/// Perft, the standard measure of whether a move generator implements the rules it claims to: the
/// counts are published for a set of positions and any disagreement is a bug in the generator. The
/// numbers this app's own copy is held to are in `test/model/xiangqi/xiangqi_perft_test.dart`, and
/// they were measured from Pikafish rather than remembered.
int perft(XiangqiPosition position, int depth) =>
    _perft(List<XiangqiPiece?>.of(position.board), position.turn, depth);

int _perft(List<XiangqiPiece?> board, XiangqiSide side, int depth) {
  if (depth == 0) return 1;
  final moves = <int>[];
  _generate(board, side, moves);
  var nodes = 0;
  for (final move in moves) {
    final from = _fromOf(move);
    final to = _toOf(move);
    final captured = board[to];
    board[to] = board[from];
    board[from] = null;
    if (!_isKingAttacked(board, side)) nodes += _perft(board, side.opposite, depth - 1);
    board[from] = board[to];
    board[to] = captured;
  }
  return nodes;
}

/// A move as two square indices in one int, `from * 90 + to`.
///
/// Generating a move as a [XiangqiMove] means allocating it, and a square object inside it, and
/// perft asks for tens of millions of them — starting from the initial position, depth 4 alone is
/// 3,290,240 nodes and something like a hundred million generated moves. So the rules work in
/// packed ints, which are allocated nowhere, and unpack once at the edge.
int _pack(int from, int to) => from * kXiangqiSquares + to;

int _fromOf(int move) => move ~/ kXiangqiSquares;

int _toOf(int move) => move % kXiangqiSquares;

XiangqiMove _unpack(int move) =>
    XiangqiMove(XiangqiSquare(_fromOf(move)), XiangqiSquare(_toOf(move)));

/// Whether [side]'s general is attacked, which is also how the flying-general rule is enforced.
///
/// The rule — the two generals may never see each other down an open file — is written here as the
/// enemy general attacking along its own file with nothing in the way. That makes it a rule about
/// attacks like any other, and it means the ordinary "a move may not leave your own general
/// attacked" filter forbids exactly the moves the rule forbids, with no second test to keep in
/// step. The trick is sound for the only thing this is ever asked about, a general's own square: a
/// general never leaves its palace, so the file it shares with the other one is always this one.
bool _isKingAttacked(List<XiangqiPiece?> board, XiangqiSide side) {
  final king = _kingSquare(board, side);
  if (king < 0) return false;
  return _isAttacked(board, king, side.opposite);
}

/// Whether anything of [by]'s attacks the square [target].
///
/// Only four kinds of piece can attack a square, and they are the four found here: a chariot or a
/// soldier along one of the four orthogonal lines, a cannon over exactly one screen on one of them,
/// and a horse jumping in with its leg clear. An advisor or an elephant cannot attack one at all —
/// an advisor never leaves its own palace and an elephant never crosses the river, so neither can
/// ever bear on a general, which is confined to the palace at the other end of the board.
bool _isAttacked(List<XiangqiPiece?> board, int target, XiangqiSide by) {
  final targetFile = target % 9;
  final targetRank = target ~/ 9;

  for (final (df, dr) in _orthogonal) {
    // The first piece along the line. A chariot attacks from it, a soldier may attack with it, and
    // on a file so does a general.
    var file = targetFile + df;
    var rank = targetRank + dr;
    XiangqiPiece? first;
    var firstFile = 0;
    var firstRank = 0;
    while (_onBoard(file, rank)) {
      final piece = board[rank * 9 + file];
      if (piece != null) {
        first = piece;
        firstFile = file;
        firstRank = rank;
        break;
      }
      file += df;
      rank += dr;
    }
    if (first != null && first.side == by) {
      switch (first.type) {
        case .rook:
          return true;
        case .king:
          // The flying general: along a file, and only along a file, with nothing between.
          if (df == 0) return true;
        case .pawn:
          if (_pawnAttacks(by, firstFile, firstRank, targetFile, targetRank)) return true;
        case .advisor || .bishop || .knight || .cannon:
          break;
      }
    }

    // The second piece along the line, which is what a cannon needs: the first piece is its screen,
    // and only the piece immediately past the screen can be captured — further ones are out of
    // range, so the walk stops at the first piece it meets.
    if (first == null) continue;
    file += df;
    rank += dr;
    while (_onBoard(file, rank)) {
      final piece = board[rank * 9 + file];
      if (piece != null) {
        if (piece.side == by && piece.type == .cannon) return true;
        break;
      }
      file += df;
      rank += dr;
    }
  }

  // Horses come from the other end: a horse does not slide, so the squares it could attack this one
  // from are enumerated and each is checked for a horse with a clear leg.
  for (final (df, dr) in _knightSteps) {
    final file = targetFile + df;
    final rank = targetRank + dr;
    if (!_onBoard(file, rank)) continue;
    final piece = board[rank * 9 + file];
    if (piece == null || piece.side != by || piece.type != .knight) continue;
    // The leg is the square beside the horse, on the axis it jumps two squares along. It always
    // lies between the horse and its target, so it is on the board whenever they both are.
    final legFile = df.abs() == 2 ? file - df ~/ 2 : file;
    final legRank = dr.abs() == 2 ? rank - dr ~/ 2 : rank;
    if (board[legRank * 9 + legFile] == null) return true;
  }

  return false;
}

/// Whether a soldier of [side] standing on ([file], [rank]) attacks ([targetFile], [targetRank]).
///
/// A soldier attacks the square it steps into, and — once it is across the river and only then —
/// the two beside it. Never backwards, and never sideways while it is still at home.
bool _pawnAttacks(XiangqiSide side, int file, int rank, int targetFile, int targetRank) {
  final forward = side == .red ? 1 : -1;
  if (file == targetFile && rank + forward == targetRank) return true;
  return rank == targetRank &&
      (file - targetFile).abs() == 1 &&
      !XiangqiSquare.at(file, rank).onOwnHalf(side);
}

/// The index of [side]'s general, or -1 if there is none.
///
/// Only the palace is looked at, because only the palace can hold a general — no move this file can
/// generate ever takes one out of it. A position with a general somewhere else is not a position
/// the rules describe, and reads here as a general that cannot be attacked.
int _kingSquare(List<XiangqiPiece?> board, XiangqiSide side) {
  final firstRank = side == .red ? 0 : 7;
  for (var rank = firstRank; rank < firstRank + 3; rank++) {
    for (var file = 3; file <= 5; file++) {
      final piece = board[rank * 9 + file];
      if (piece != null && piece.side == side && piece.type == .king) return rank * 9 + file;
    }
  }
  return -1;
}

/// Whether [move] leaves [side]'s general unattacked, and so may be played.
bool _isLegalAfter(List<XiangqiPiece?> board, int move, XiangqiSide side) {
  final from = _fromOf(move);
  final to = _toOf(move);
  final captured = board[to];
  board[to] = board[from];
  board[from] = null;
  final legal = !_isKingAttacked(board, side);
  board[from] = board[to];
  board[to] = captured;
  return legal;
}

/// Writes every move [side] could make into [out], ignoring whether it leaves their general in
/// check — [legalMoves] and [perft] both filter that out by playing the move.
void _generate(List<XiangqiPiece?> board, XiangqiSide side, List<int> out) {
  for (var index = 0; index < kXiangqiSquares; index++) {
    final piece = board[index];
    if (piece == null || piece.side != side) continue;
    final file = index % 9;
    final rank = index ~/ 9;

    switch (piece.type) {
      case .king:
        for (final (df, dr) in _orthogonal) {
          final f = file + df;
          final r = rank + dr;
          if (_onBoard(f, r) && XiangqiSquare.at(f, r).inPalaceOf(side)) {
            _addMove(board, index, f, r, side, out);
          }
        }

      case .advisor:
        for (final (df, dr) in _diagonalSteps) {
          final f = file + df;
          final r = rank + dr;
          if (_onBoard(f, r) && XiangqiSquare.at(f, r).inPalaceOf(side)) {
            _addMove(board, index, f, r, side, out);
          }
        }

      case .bishop:
        for (final (df, dr) in _diagonalSteps) {
          final f = file + 2 * df;
          final r = rank + 2 * dr;
          if (!_onBoard(f, r)) continue;
          // An elephant never crosses the river: it is a defender of its own half and nothing else.
          if (!XiangqiSquare.at(f, r).onOwnHalf(side)) continue;
          // And the eye it steps over has to be empty, which on the opening position leaves each
          // elephant exactly two squares.
          if (board[(rank + dr) * 9 + file + df] != null) continue;
          _addMove(board, index, f, r, side, out);
        }

      case .knight:
        for (final (df, dr) in _knightSteps) {
          final f = file + df;
          final r = rank + dr;
          if (!_onBoard(f, r)) continue;
          // The leg: the square beside the horse on the axis it jumps two squares along. A single
          // piece there stops the jump, however far away the target is.
          final legFile = df.abs() == 2 ? file + df ~/ 2 : file;
          final legRank = dr.abs() == 2 ? rank + dr ~/ 2 : rank;
          if (board[legRank * 9 + legFile] != null) continue;
          _addMove(board, index, f, r, side, out);
        }

      case .rook:
        for (final (df, dr) in _orthogonal) {
          var f = file + df;
          var r = rank + dr;
          while (_onBoard(f, r)) {
            final target = board[r * 9 + f];
            if (target != null) {
              if (target.side != side) out.add(_pack(index, r * 9 + f));
              break;
            }
            out.add(_pack(index, r * 9 + f));
            f += df;
            r += dr;
          }
        }

      case .cannon:
        for (final (df, dr) in _orthogonal) {
          var f = file + df;
          var r = rank + dr;
          // Up to the screen the cannon moves like a chariot, and takes nothing.
          while (_onBoard(f, r) && board[r * 9 + f] == null) {
            out.add(_pack(index, r * 9 + f));
            f += df;
            r += dr;
          }
          if (!_onBoard(f, r)) continue;
          // Then it jumps the screen and takes the first piece past it — which may be its own,
          // in which case there is no move — and never reaches any piece beyond that.
          f += df;
          r += dr;
          while (_onBoard(f, r)) {
            final target = board[r * 9 + f];
            if (target != null) {
              if (target.side != side) out.add(_pack(index, r * 9 + f));
              break;
            }
            f += df;
            r += dr;
          }
        }

      case .pawn:
        final forward = side == .red ? 1 : -1;
        if (_onBoard(file, rank + forward)) _addMove(board, index, file, rank + forward, side, out);
        // Sideways comes with the crossing and never goes away again, backwards never comes at all.
        if (!XiangqiSquare.at(file, rank).onOwnHalf(side)) {
          for (final df in const [-1, 1]) {
            if (_onBoard(file + df, rank)) _addMove(board, index, file + df, rank, side, out);
          }
        }
    }
  }
}

/// Adds the move to ([file], [rank]) unless one of [side]'s own pieces is standing there.
void _addMove(
  List<XiangqiPiece?> board,
  int from,
  int file,
  int rank,
  XiangqiSide side,
  List<int> out,
) {
  final target = board[rank * 9 + file];
  if (target != null && target.side == side) return;
  out.add(_pack(from, rank * 9 + file));
}

bool _onBoard(int file, int rank) => file >= 0 && file <= 8 && rank >= 0 && rank <= 9;

/// The four steps a general, chariot or cannon line runs along.
const _orthogonal = [(0, 1), (0, -1), (1, 0), (-1, 0)];

/// The four steps an advisor takes, and half of an elephant's move.
const _diagonalSteps = [(1, 1), (1, -1), (-1, 1), (-1, -1)];

/// The eight squares a horse can reach in one jump.
const _knightSteps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
