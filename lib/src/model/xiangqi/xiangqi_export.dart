import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';

/// The shareable text a xiangqi game is written down as.
///
/// Three spellings of the same thing, each for a reader of a different kind: a FEN, which sets a
/// board back up exactly; an ICCS move list, which is what Pikafish takes and answers with; and the
/// Chinese notation a player reads. Nothing here derives a position — every one of them is handed
/// the position or the moves and says them again — so all three are pure functions of their
/// arguments, and all three round-trip through the parsers the app already has.
///
/// The ICCS list and the notation both stop at the first move the position they are playing through
/// cannot play. An engine's principal variation is a guess at the future and its tail can be
/// nonsense in a way the engine itself never notices; a line that renders its readable head and
/// drops the rest is worth more on a screen than one that throws.

/// [position] as FEN, the one line of text that sets a board back up.
///
/// The exact inverse of [XiangqiPosition.fromFen], which is what makes it an export rather than a
/// description: `fromFen(toFen(p))` is `p` again, counters and all.
String xiangqiFenExport(XiangqiPosition position) => position.toFen();

/// [moves] as a space-separated ICCS move list, `h2e2 h9g7`.
///
/// The notation the engine speaks, and the one spelling of a move that survives a round trip
/// unchanged: [xiangqiIccsImport] reads exactly this back. An empty list is the empty string.
String xiangqiIccsExport(IList<XiangqiMove> moves) => moves.map((move) => move.iccs).join(' ');

/// The moves [xiangqiIccsExport] wrote, read back — the exact inverse of it.
///
/// Throws [FormatException] on anything that is not a space-separated list of ICCS moves rather
/// than skipping the token: a list that cannot be read back is not an export, and quietly dropping
/// what does not parse would turn a corrupt line into a shorter, wrong one.
IList<XiangqiMove> xiangqiIccsImport(String list) {
  final trimmed = list.trim();
  if (trimmed.isEmpty) return const IListConst([]);
  return [
    for (final token in trimmed.split(RegExp(r'\s+')))
      XiangqiMove.parseIccs(token) ?? (throw FormatException('Not an ICCS move: "$token"', list)),
  ].lock;
}

/// [moves] played from [from], written in Chinese notation on one line: `1. 炮二平五 马8进7 2. 马二进三`.
///
/// Numbered the way a scoresheet numbers them — one number to a whole move, black's written under
/// the same number as the red move that opened it, and `1...` for the case that cannot happen in a
/// game but can in an analysis: a line that starts with black to move. A line whose first move is
/// unplayable is the empty string.
String xiangqiMovesExport(XiangqiPosition from, IList<XiangqiMove> moves) =>
    _moveLines(from, moves).join(' ');

/// A line written to be read: its starting position as a FEN, then its moves, one whole move to a
/// line.
///
/// The FEN comes first and on its own line, so the whole rendering is self-describing — parsing the
/// first line back with [XiangqiPosition.fromFen] gives the position the rest of the line is to be
/// played from — and anything reading it knows whose move the line's first move is without being
/// told separately.
String xiangqiLineExport(XiangqiPosition from, IList<XiangqiMove> moves) =>
    <String>[xiangqiFenExport(from), ..._moveLines(from, moves)].join('\n');

/// [from] with [moves] played on it, each move carrying the number it is written under.
///
/// The number and the side both come from the position the move is played in rather than being
/// counted here: [XiangqiPosition.fullmoveNumber] is exactly what a scoresheet writes beside the
/// move, and [XiangqiPosition.turn] is exactly who is playing it, so a line that starts with black
/// to move numbers itself correctly with nothing extra to keep track of.
IList<({int number, XiangqiSide side, String notation})> _numberedLine(
  XiangqiPosition from,
  IList<XiangqiMove> moves,
) {
  var position = from;
  final entries = <({int number, XiangqiSide side, String notation})>[];
  for (final move in moves) {
    if (!isLegal(position, move)) break;
    entries.add((
      number: position.fullmoveNumber,
      side: position.turn,
      notation: xiangqiMoveNotation(position, move),
    ));
    position = play(position, move);
  }
  return entries.lock;
}

/// The numbered notation of [_numberedLine], grouped: one full move to a string, red's first.
List<String> _moveLines(XiangqiPosition from, IList<XiangqiMove> moves) {
  final lines = <String>[];
  var current = '';
  for (final entry in _numberedLine(from, moves)) {
    if (entry.side == XiangqiSide.red) {
      if (current.isNotEmpty) lines.add(current);
      current = '${entry.number}. ${entry.notation}';
    } else {
      current = current.isEmpty
          ? '${entry.number}... ${entry.notation}'
          : '$current ${entry.notation}';
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}
