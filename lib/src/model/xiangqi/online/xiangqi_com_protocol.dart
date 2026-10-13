import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// The bridge between xiangqi.com's UCI and this repo's [XiangqiMove].
///
/// The two agree on the files — a letter `a` to `i`, left to right — and on the move being two of
/// them, `from` then `to`. They disagree on the ranks, and that is the whole of this file.
///
/// This repo counts ranks from 0: red's back rank is 0 and black's is 9, so the opening cannon move
/// is `h2e2` and a black horse from its back rank to the rank in front of it is `h9g7`
/// ([XiangqiSquare.rank] is `index ~/ 9`, and its doc says `0 to 9, red's back row being 0`).
///
/// xiangqi.com counts the same ranks from 1: red's back rank is 1 and black's is 10, so the very
/// same two moves are `h3e3` and `h10g8`. A rank of 10 is the one place a file letter is followed
/// by two digits, and it is what makes a naive `length == 4` parse wrong: five characters are as
/// ordinary as four.
///
/// Everything xiangqi.com carries about a move uses the rank-1 spelling — the `move` field of a
/// `g_v2.move` emit and each entry of `move_history`, whose first whitespace-separated token is the
/// UCI (`"c3d5 577/120 570/120 3"`). The callers of this file split that token off and hand it here;
/// these two functions take a move and nothing else.

/// The file letter a to i of [square]. [XiangqiSquare.name] spells file *and* rank together, and
/// here the rank has to be written xiangqi.com's way, so the two halves are taken separately.
String _fileLetter(XiangqiSquare square) => String.fromCharCode(0x61 + square.file);

/// The rank xiangqi.com writes for [square], `1` to `10`.
int _comRank(XiangqiSquare square) => square.rank + 1;

/// This repo's rank for xiangqi.com's `comRank`, `1` to `10`, or null if it is out of range.
int? _repoRank(int comRank) => comRank >= 1 && comRank <= 10 ? comRank - 1 : null;

/// The square a xiangqi.com UCI half names, starting at [start], and the index just past it.
///
/// A half is a file letter `a` to `i` followed by one or two digits: `h3`, and `h10`. Returns null
/// if there is no such half there, and a null `next` if the digits are not a rank.
(XiangqiSquare, int)? _parseComSquare(String uci, int start) {
  if (start >= uci.length) return null;
  final file = uci.codeUnitAt(start) - 0x61;
  if (file < 0 || file > 8) return null;

  var i = start + 1;
  final digitsStart = i;
  while (i < uci.length && uci.codeUnitAt(i) >= 0x30 && uci.codeUnitAt(i) <= 0x39) {
    i++;
  }
  final digitCount = i - digitsStart;
  // One or two digits, no more: a rank is `1` to `10`, never three characters and never none.
  if (digitCount == 0 || digitCount > 2) return null;

  final rank = _repoRank(int.parse(uci.substring(digitsStart, i)));
  if (rank == null) return null;
  return (XiangqiSquare.at(file, rank), i);
}

/// The move xiangqi.com's [uci] names, or null if it is not two squares.
///
/// `h3e3` becomes this repo's `h2e2`, and `h10g8` becomes `h9g7`. The whole string has to be a
/// move: a caller holding one element of `move_history` splits off the leading UCI token
/// (`"c3d5"` from `"c3d5 577/120 570/120 3"`) before calling this.
///
/// Returns null for anything that is not exactly two squares — a bad file, a rank outside `1` to
/// `10`, a trailing character — matching [XiangqiMove.parseIccs], which is equally strict about the
/// four-character ICCS form.
///
/// The length is only a pre-filter, `4` to `6`: a half is a file letter and one or two digits, so
/// four characters when neither square is on rank 10, five when one is, and six when **both** are —
/// `a10a10` is a legal move on black's back rank. [_parseComSquare] and the full-consumption check
/// below do the real validating.
XiangqiMove? xiangqiMoveFromComUci(String uci) {
  final trimmed = uci.trim();
  if (trimmed.length < 4 || trimmed.length > 6) return null;
  final from = _parseComSquare(trimmed, 0);
  if (from == null) return null;
  final to = _parseComSquare(trimmed, from.$2);
  if (to == null || to.$2 != trimmed.length) return null;
  return XiangqiMove(from.$1, to.$1);
}

/// [move] in xiangqi.com's UCI, rank-1.
///
/// This repo's `h2e2` becomes `h3e3`, and `h9g7` becomes `h10g8`. The inverse of
/// [xiangqiMoveFromComUci]: the two round-trip exactly, in both directions.
String xiangqiMoveToComUci(XiangqiMove move) =>
    '${_fileLetter(move.from)}${_comRank(move.from)}'
    '${_fileLetter(move.to)}${_comRank(move.to)}';
