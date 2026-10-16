import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

part 'xiangqi_puzzle.freezed.dart';

/// The two themes xiangqi.com files a puzzle under.
///
/// `GET /api/puzzle/get_themes_tags` spells them out in four languages — `{"1": "CHECKMATE",
/// "2": "TACTIC"}` in English, `{"1": "杀法", "2": "战术"}` in Simplified Chinese — and a puzzle
/// carries the number. A member therefore holds the number `value` the wire spells it with and the
/// English `wireName` the themes endpoint gives it: the number is what goes back out on
/// `POST /api/puzzle/create`, and the words a reader sees are the app's own, like every other label
/// on these screens.
enum XiangqiPuzzleTheme(final int value, final String wireName) {
  /// 杀法: a forced mate.
  checkmate(1, 'CHECKMATE'),

  /// 战术: a tactic that wins material.
  tactic(2, 'TACTIC');

  /// The theme [value] names, or null for a value this enum does not know.
  ///
  /// Null rather than a default, because a theme is a fact about the puzzle and not a preference:
  /// a puzzle filed under a theme this app has never heard of is a puzzle this app cannot describe,
  /// and the one place that matters is the label, which is dropped rather than guessed at.
  static XiangqiPuzzleTheme? fromValue(Object? value) {
    final number = value is num ? value.toInt() : null;
    for (final theme in values) {
      if (theme.value == number) return theme;
    }
    return null;
  }
}

/// How far a puzzle has got through xiangqi.com's publishing pipeline.
///
/// A member's `value` is the number the wire spells it with. The three named values are the
/// bundle's own (`main.*.js`, module `432422`). **`-100` is not among them**: it is what a puzzle
/// created through `POST /api/puzzle/create` comes back as, measured on 2026-10-16, and it is why
/// [fromValue] answers null rather than a wrong member.
enum XiangqiPuzzleState(final int value) {
  /// Saved but not submitted.
  draft(0),

  /// Submitted, and waiting to be looked at.
  created(100),

  /// Being looked at.
  underReview(200),

  /// In the public pool.
  published(300);

  /// The state [value] names, or null for a value this enum does not know.
  static XiangqiPuzzleState? fromValue(Object? value) {
    final number = value is num ? value.toInt() : null;
    for (final state in values) {
      if (state.value == number) return state;
    }
    return null;
  }
}

/// How an attempt at a puzzle ended, as the server records it.
///
/// A member's `value` is the number the wire spells it with. The four values are the bundle's
/// (`attempt_status`, module `432422`), and the server recomputes
/// the status from the `mistakes` and `hints_used` an attempt is submitted with: a solve with
/// neither is [solved], a solve that used a hint is [solvedByHint], and a solve that got a move
/// wrong on the way is [solvedByMistake]. [started] is what an attempt in progress reads as.
enum XiangqiPuzzleAttemptStatus(final int value) {
  started(1),
  solvedByMistake(2),
  solvedByHint(3),
  solved(4);

  /// The status [value] names, or null for a value this enum does not know.
  static XiangqiPuzzleAttemptStatus? fromValue(Object? value) {
    final number = value is num ? value.toInt() : null;
    for (final status in values) {
      if (status.value == number) return status;
    }
    return null;
  }

  /// Whether this status is one of the three that mean the puzzle was solved.
  bool get isSolved => this != started;
}

/// Which queue a puzzle was taken from, as `POST /api/puzzle/<id>/complete` spells it.
///
/// A member's `wireName` is the single letter the wire spells it with.
enum XiangqiPuzzleAttemptMode(final String wireName) {
  /// Practice: the solver picks the themes and the rating range, and nothing is scored.
  practice('P'),

  /// Challenge: the server picks the next puzzle, and the rating moves.
  challenge('C'),
}

/// What the server already knows about this account's attempt at a puzzle.
///
/// The payload carries a good deal more — the puzzle's own rating, this account's rating, and the
/// two factors a win or a loss would move it by — and none of it is carried here: nothing on the
/// puzzle screen prints a rating change it has not been told the result of, and the result comes
/// back from `complete` rather than from the puzzle. See [XiangqiPuzzleCompleteResult].
@freezed
sealed class const XiangqiPuzzleAttempt._() with _$XiangqiPuzzleAttempt {
  const factory({
    /// How the last attempt ended, or null for a status this app does not know.
    XiangqiPuzzleAttemptStatus? status,

    /// This account's puzzle rating as the puzzle payload reports it.
    int? userRating,
  }) = _XiangqiPuzzleAttempt;
}

/// One puzzle, as `GET /api/puzzle/P/<id>` hands it over.
///
/// ## The two sides, which are not the same side
///
/// A xiangqi.com puzzle is a position with a blunder already played in it, and the solver is the
/// player who did **not** blunder. Two fields say so and they are easy to confuse:
///
/// * [position] is `initial_fen` parsed, and its `turn` is the **blunderer's** — the side that is
///   about to be punished, which is the side that moves first in the puzzle.
/// * [playerSide] is `player_turn`, and it is the **solver's** side. It is the opposite of
///   [position]'s turn in every sample measured (five on 2026-10-15/16, see
///   `xiangqi-com-re/docs/puzzle.md`), which is what [xiangqiPuzzleFromJson] falls back to when the
///   payload does not carry it.
///
/// So the board opens with the solver's opponent to move, and [blunderMove] is that move: the app
/// plays it before the solver is given the board.
@freezed
sealed class const XiangqiPuzzle._() with _$XiangqiPuzzle {
  const factory({
    /// `puzzle_id`, the six-character handle every other puzzle endpoint is addressed by.
    required String id,

    /// The author's title for it, which is null on every puzzle in the public pool.
    String? title,

    /// The puzzle's own rating.
    required int rating,

    /// Which of the two themes it is filed under.
    required XiangqiPuzzleTheme theme,

    /// How many moves the solver has to find — `full_moves`, which is half of `model_answer`
    /// rounded down, the blunder not counted.
    required int fullMoves,

    /// `initial_fen` parsed: the position **before** the blunder, with the blunderer to move.
    required XiangqiPosition position,

    /// The side the solver plays.
    required XiangqiSide playerSide,

    /// `blunder_move`: the move the app plays for the solver's opponent before handing over.
    required XiangqiMove blunderMove,

    /// The moves the solver has to find, in order — `model_answer` without the blunder that opens
    /// it, so `solution[0]` is the move the solver plays first.
    ///
    /// Null when the server withheld the answer, which is what it does once the day's puzzle quota
    /// is spent: the position comes back with the solution struck out. A puzzle with no solution is
    /// a puzzle that can be looked at and not solved, which is a state the screen has to draw rather
    /// than an error — see `xiangqiPuzzleProvider`.
    IList<XiangqiMove>? solution,

    /// The tag ids the puzzle is filed under, empty on every puzzle in the public pool.
    ///
    /// Ids rather than names: `get_themes_tags` is what names them, in the reader's language, and a
    /// puzzle that carried a copy of the name would be a second, staler answer to the same question.
    required IList<int> tags,

    /// The raw `state` number. See [XiangqiPuzzleState] for the three values that have names.
    required int state,

    /// How many attempts got it right, as a percentage, or null when the payload carries none.
    double? passRate,

    /// What the server already knows about this account's attempt.
    XiangqiPuzzleAttempt? attempt,
  }) = _XiangqiPuzzle;

  /// The moves of the whole solution, the blunder first — the shape the wire sends them in.
  ///
  /// Empty when [solution] is null: a puzzle whose answer was withheld has no moves to play, and an
  /// empty list is a truer answer to "what are the moves" than a null would be.
  IList<XiangqiMove> get modelAnswer =>
      solution == null ? const IListConst([]) : IList([blunderMove, ...solution!]);
}

/// What `POST /api/puzzle/<id>/complete` answers with.
///
/// Two fields and no more: the puzzle's own rating as the server now has it, and the status it
/// recorded the attempt under. The status is the server's verdict and not the client's claim — it
/// is recomputed from the `mistakes` and `hints_used` the attempt was submitted with, and a status
/// sent *to* it is a `400` (measured on 2026-10-16). The rating is the puzzle's, not this account's:
/// where the account's own rating moves is a question the payload does not answer, and nothing here
/// guesses at it.
@freezed
sealed class const XiangqiPuzzleCompleteResult._() with _$XiangqiPuzzleCompleteResult {
  const factory({
    /// The puzzle's rating, or null when the answer carries none.
    int? puzzleRating,

    /// How the attempt was recorded, or null for a status this app does not know.
    XiangqiPuzzleAttemptStatus? status,
  }) = _XiangqiPuzzleCompleteResult;
}

/// The puzzle [json] describes, or null when it is not one this app can solve.
///
/// ## What makes a payload unreadable
///
/// Three things, and each of them is a puzzle that cannot be handed to a board:
///
/// * an `initial_fen` that will not parse, or a `blunder_move` that is not a move or is not legal in
///   that position — there would be no position to draw, since the app plays the blunder itself;
/// * a `model_answer` that is there but shorter than two moves, which cannot describe a blunder and
///   an answer to it;
/// * a `state` that is not published. A draft is the author's own work in progress: it has no
///   rating, no blunder and no answer yet (measured on 2026-10-16 — a puzzle straight out of
///   `POST /api/puzzle/create` comes back with `state: -100`, `blunder_move: null`,
///   `player_turn: null` and `rating: 0`), so there is nothing on it to solve.
///
/// Everything else is read defensively: a missing title is no title, a missing pass rate is no pass
/// rate, and a `model_answer` that is absent is a withheld answer rather than a broken payload —
/// that last one is the quota case, and the one shape here that is a *successful* read.
XiangqiPuzzle? xiangqiPuzzleFromJson(Map<String, dynamic> json) {
  final id = _string(json['puzzle_id']);
  if (id == null) return null;

  if (XiangqiPuzzleState.fromValue(json['state']) != XiangqiPuzzleState.published) return null;

  final fen = _string(json['initial_fen']);
  if (fen == null) return null;
  final XiangqiPosition position;
  try {
    position = XiangqiPosition.fromFen(fen);
  } on FormatException {
    return null;
  }

  final blunder = _move(json['blunder_move']);
  if (blunder == null) return null;
  // The blunder is played from [position] before the solver is given the board, so a blunder that
  // cannot be played there is a puzzle that cannot be set up. Checked rather than assumed: the
  // board would throw on it, and a throw from a provider is an error screen where a dropped puzzle
  // is a puzzle the search can replace.
  if (!rules.isLegal(position, blunder)) return null;

  // `model_answer` opens with the blunder and then alternates, solver first. Absent is the quota
  // case; present but too short is a payload that cannot be played, and is dropped.
  final answer = json['model_answer'];
  IList<XiangqiMove>? solution;
  if (answer != null) {
    if (answer is! List || answer.length < 2) return null;
    final moves = <XiangqiMove>[];
    for (final entry in answer) {
      final move = _move(entry);
      if (move == null) return null;
      moves.add(move);
    }
    solution = moves.skip(1).toIList();
  }

  return XiangqiPuzzle(
    id: id,
    title: _string(json['title']),
    rating: _int(json['rating']) ?? 0,
    theme: XiangqiPuzzleTheme.fromValue(json['theme']) ?? XiangqiPuzzleTheme.tactic,
    fullMoves: _int(json['full_moves']) ?? (solution?.length ?? 0) ~/ 2,
    position: position,
    playerSide: _playerSide(json['player_turn'], position),
    blunderMove: blunder,
    solution: solution,
    tags: _tags(json['tags']),
    state: _int(json['state']) ?? 0,
    passRate: _double(json['pass_rate']),
    attempt: _attempt(json['attempt']),
  );
}

/// The side `player_turn` names, or the side that is not to move in [position].
///
/// `player_turn` is `1` for red and `2` for black, and it is the solver's side. It wins whenever it
/// is there. A payload without it is a draft — measured on 2026-10-16, `POST /api/puzzle/create`
/// answers `player_turn: null` — and the fallback is the rule every measured puzzle follows: the
/// solver is the side that is **not** to move, because the side to move is the one that just
/// blundered.
XiangqiSide _playerSide(Object? playerTurn, XiangqiPosition position) {
  final number = _int(playerTurn);
  if (number == 1) return XiangqiSide.red;
  if (number == 2) return XiangqiSide.black;
  return position.turn.opposite;
}

/// The move [value] names in xiangqi.com's rank-1 UCI, or null if it names none.
///
/// The wire spells a move the way its own board does — `h3e3`, and `h10g8` on the back rank — while
/// this repo's moves are rank-0. [xiangqiMoveFromComUci] is the one place that is translated, and
/// this is the puzzle reader's use of it.
XiangqiMove? _move(Object? value) {
  final text = _string(value);
  return text == null ? null : xiangqiMoveFromComUci(text);
}

/// The tag ids [value] holds, empty when it holds none.
///
/// **Inferred, not measured**: every puzzle captured so far carries `"tags": []`, so the shape of a
/// non-empty one is not known. Both shapes the wire could plausibly use are accepted — a bare number
/// (`[46]`) and an object with an `id` (`[{"id": 46, "theme": 2}]`) — and anything else is dropped
/// rather than guessed at. The one thing that is certain is that a tag is identified by the number
/// `get_themes_tags` lists it under, because that is the number `search` takes.
IList<int> _tags(Object? value) {
  if (value is! List) return const IListConst([]);
  final tags = <int>[];
  for (final entry in value) {
    final id = entry is Map<String, dynamic> ? _int(entry['id']) : _int(entry);
    if (id != null) tags.add(id);
  }
  return tags.lock;
}

/// The attempt [value] describes, or null when it describes none.
XiangqiPuzzleAttempt? _attempt(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  return XiangqiPuzzleAttempt(
    status: XiangqiPuzzleAttemptStatus.fromValue(value['status']),
    userRating: _int(value['u_rating']),
  );
}

/// [value] as a non-empty string, or null.
String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;

/// [value] as an integer, or null. A JSON number may arrive as a double, so both are accepted.
int? _int(Object? value) => value is num ? value.toInt() : null;

/// [value] as a double, or null.
double? _double(Object? value) => value is num ? value.toDouble() : null;
