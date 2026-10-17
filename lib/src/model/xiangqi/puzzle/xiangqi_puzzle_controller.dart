import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/quota/xiangqi_quota.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:logging/logging.dart';

part 'xiangqi_puzzle_controller.freezed.dart';

final _logger = Logger('XiangqiPuzzleController');

/// How long the app waits before playing the opponent's answer to the solver's move.
///
/// The opponent's moves are not the solver's to find — they are in the puzzle's answer, and the app
/// plays them — so this is not a delay in an answer, it is the pause that makes the answer
/// readable. Both moves landing in the same frame would show the solver's move and the reply as one
/// jump, and the reply is the half of the line that proves the tactic worked.
const xiangqiPuzzleReplyDelay = Duration(milliseconds: 400);

/// The pause [XiangqiPuzzleController] takes before playing the opponent's answer.
///
/// A provider rather than the constant itself so that a test can set it to [Duration.zero] and drive
/// a whole line without waiting out four hundred milliseconds per reply. Nothing else overrides it:
/// the length is a reading pace and not a setting, which is why it is not in the board preferences
/// beside the piece animation.
final xiangqiPuzzleReplyDelayProvider = Provider<Duration>(
  (Ref ref) => xiangqiPuzzleReplyDelay,
  name: 'XiangqiPuzzleReplyDelayProvider',
);

/// How long a wrong move stays on the board before it is taken back.
///
/// The move is shown, not silently refused: a solver who taps a legal move deserves to see what that
/// move would have done and which piece it moved. It is then spliced back out so the next attempt
/// starts from the puzzle's own position. The five hundred milliseconds match the chess puzzle
/// controller's wrong-move feedback.
const xiangqiPuzzleWrongMoveDelay = Duration(milliseconds: 500);

/// The pause [XiangqiPuzzleController] takes before taking a wrong move back.
///
/// A provider so tests can shorten the feedback without changing what users see.
final xiangqiPuzzleWrongMoveDelayProvider = Provider<Duration>(
  (Ref ref) => xiangqiPuzzleWrongMoveDelay,
  name: 'XiangqiPuzzleWrongMoveDelayProvider',
);

/// Where an attempt at a puzzle has got to.
enum XiangqiPuzzlePhase() {
  /// The solver is looking for the next move.
  solving,

  /// The whole line is on the board and the attempt is on its way to the server.
  submitting,

  /// The server has recorded the attempt.
  recorded,

  /// The whole line is on the board, and the server never got it.
  ///
  /// The line is still the answer: the solver found it, and nothing about the board changes because
  /// a submission did not arrive. What is missing is the server's verdict and whatever it does with
  /// it, which is why this is a state of its own rather than an error — see
  /// [XiangqiPuzzleController.retrySubmit].
  unrecorded,
}

/// The state of one attempt at one puzzle.
@freezed
sealed class const XiangqiPuzzleAttemptState._() with _$XiangqiPuzzleAttemptState {
  const factory({
    /// The puzzle being solved.
    required XiangqiPuzzle puzzle,

    /// Every position of the attempt, the one the puzzle starts from first.
    ///
    /// One longer than [moves], and `positions[i]` is the position `moves[i]` was played in — which
    /// is what the notation list reads, since a move is written from the board it was made on. The
    /// second entry is the position with the blunder already played: the app plays that move itself,
    /// because it is the move the *opponent* blundered and not a move the solver has to find. See
    /// [XiangqiPuzzle.blunderMove].
    required IList<XiangqiPosition> positions,

    /// Every move played, by either side, in the order they were played — the blunder first.
    required IList<XiangqiMove> moves,

    /// How many moves the solver got wrong.
    ///
    /// A wrong move is played for [xiangqiPuzzleWrongMoveDelay] and then spliced back out, so the
    /// solver sees which move was wrong but tries again from the same position. That is what the
    /// shipped client's `makeRevertWrongMove` does, and it is what the server's own `attempt_status`
    /// implies, since an attempt can be recorded as solved *by mistake*.
    required int mistakes,

    /// How many hints the solver has asked for and been given.
    required int hintsUsed,

    /// Where the attempt has got to.
    required XiangqiPuzzlePhase phase,

    /// The move the last hint pointed at, or null when none is showing.
    ///
    /// Cleared as soon as any move is played: a hint is about one position, and it stops saying
    /// anything the moment the board leaves it.
    XiangqiMove? hint,

    /// The move the solver just got wrong, or null when the last move was not one.
    ///
    /// Kept so that the screen can say so, and cleared by the next move of any kind.
    XiangqiMove? wrongMove,

    /// How the server recorded the attempt, once it has answered.
    XiangqiPuzzleAttemptStatus? recordedStatus,
  }) = _XiangqiPuzzleAttemptState;

  /// The position on the board.
  XiangqiPosition get position => positions.last;

  /// The move that was played last, or null before anything has been played.
  XiangqiMove? get lastMove => moves.isEmpty ? null : moves.last;

  /// Whether it is the solver's move.
  ///
  /// The blunder is played by the opponent and is the first entry of [moves], so the solver moves on
  /// every odd count: one move played is the blunder and the solver's turn, two is the solver's move
  /// and the opponent's turn, and so on.
  bool get isSolverTurn => moves.length.isOdd;

  /// The move the solver has to find next, or null when there is none left to find.
  ///
  /// The whole line is `[blunder, ...solution]` — the blunder and then the two sides alternating —
  /// so the move that comes after `moves.length` moves is `solution[moves.length - 1]`. Null when
  /// that is past the end, which is the line being complete, and null as well when the puzzle's
  /// answer was withheld: a puzzle with no solution has no next move to find, and nothing in this
  /// class tells it apart from a finished one except [puzzle].
  XiangqiMove? get nextSolutionMove {
    final solution = puzzle.solution;
    if (solution == null) return null;
    final index = moves.length - 1;
    return index >= 0 && index < solution.length ? solution[index] : null;
  }

  /// Whether the whole line is on the board.
  bool get isLineComplete => phase != XiangqiPuzzlePhase.solving;

  /// Whether the board takes the solver's moves at all.
  ///
  /// False once the line is complete, and false for a puzzle whose answer the server withheld: there
  /// is nothing to check a move against, and a board that took one would be inviting the solver to
  /// play a game that is not there.
  bool get isPlayable => phase == XiangqiPuzzlePhase.solving && puzzle.solution != null;

  /// Whether a hint can be asked for from here.
  bool get canHint => isPlayable && isSolverTurn;
}

/// What one attempt at a puzzle is held under: the puzzle, and which attempt at it this is.
///
/// The puzzle is the key rather than its id because the attempt cannot start until the puzzle is in
/// hand and the value is what says so: the screen watches a puzzle fetch and only then builds this,
/// so there is no state here that has to mean "still loading".
///
/// The counter is not decoration. A search can answer with the puzzle that was just solved — the
/// server's own record of what has been played can lag by a moment — and an attempt keyed by the
/// puzzle alone would then still be holding the finished line: a board with the whole answer on it
/// and a "next puzzle" button that appears to do nothing. Bumping the counter is what makes "next"
/// mean a new attempt whether or not the puzzle changes.
typedef XiangqiPuzzleAttemptKey = ({XiangqiPuzzle puzzle, int attempt});

/// A provider for [XiangqiPuzzleController], one attempt per [XiangqiPuzzleAttemptKey].
final xiangqiPuzzleControllerProvider = NotifierProvider.autoDispose
    .family<XiangqiPuzzleController, XiangqiPuzzleAttemptState, XiangqiPuzzleAttemptKey>(
      XiangqiPuzzleController.new,
      name: 'XiangqiPuzzleControllerProvider',
    );

/// One attempt at one puzzle: the moves the solver makes, and what the server says about them.
class XiangqiPuzzleController(final XiangqiPuzzleAttemptKey key)
    extends Notifier<XiangqiPuzzleAttemptState> {
  /// The puzzle being solved.
  XiangqiPuzzle get puzzle => key.puzzle;

  @override
  XiangqiPuzzleAttemptState build() {
    // The blunder is played here, before the solver ever sees the board, because it is the
    // opponent's move and not one of the moves being asked for. It is legal by construction: the
    // puzzle reader refuses a puzzle whose blunder cannot be played in its own position, so this
    // cannot throw. See `xiangqiPuzzleFromJson`.
    final afterBlunder = rules.play(puzzle.position, puzzle.blunderMove);
    return XiangqiPuzzleAttemptState(
      puzzle: puzzle,
      // The position the puzzle starts from and the one the blunder leads to, so that every move
      // has the position it was played in in front of it — which is what the notation list reads.
      positions: IList([puzzle.position, afterBlunder]),
      moves: IList([puzzle.blunderMove]),
      mistakes: 0,
      hintsUsed: 0,
      phase: XiangqiPuzzlePhase.solving,
    );
  }

  /// Plays [move] for the solver.
  ///
  /// A move that is not the puzzle's next one is played for a moment, counted and reported through
  /// [XiangqiPuzzleAttemptState.wrongMove], and then taken back so the solver tries again from the
  /// same position. A move that is the next one is played, and so is the opponent's answer to it,
  /// which is the half of the line the app plays for them.
  ///
  /// Does nothing when it is not the solver's turn, when the line is already complete, or when the
  /// puzzle has no answer to check against.
  void onUserMove(XiangqiMove move) {
    if (!state.isPlayable || !state.isSolverTurn) return;
    final expected = state.nextSolutionMove;
    if (expected == null) return;

    if (move != expected) {
      final positionsBefore = state.positions;
      final movesBefore = state.moves;
      state = state.copyWith(
        positions: positionsBefore.add(rules.play(state.position, move)),
        moves: movesBefore.add(move),
        mistakes: state.mistakes + 1,
        wrongMove: move,
        hint: null,
      );
      unawaited(_revertWrongMove(move, positionsBefore, movesBefore));
      return;
    }

    _play(move);
    unawaited(_playOpponentAnswer());
  }

  /// Asks the server whether a hint may be shown, and shows one if it may.
  ///
  /// **The allowance is the server's to spend, and this is where it is spent.** The request goes to
  /// `POST /api/quota/usage` before anything is revealed, and `allowed: false` is the answer — there
  /// is no local count to consult and none is kept. See `xiangqi-com-re/docs/quota.md`.
  ///
  /// Returns what the server said, or null when nothing was asked: a hint is only asked for on the
  /// solver's turn of a puzzle that has an answer, and a caller that asks at any other moment is
  /// told nothing rather than charged for it.
  Future<XiangqiQuotaUsage?> hint() async {
    if (!state.canHint) return null;
    final usage = await ref.read(xiangqiQuotaRepositoryProvider).consume(kXiangqiQuotaPuzzleHints);
    if (!ref.mounted || !usage.allowed) return usage;

    // Re-read after the await: the solver may have moved while the request was in flight, in which
    // case the hint it was asked for is about a position that is no longer on the board.
    final move = state.canHint ? state.nextSolutionMove : null;
    if (move == null) return usage;
    state = state.copyWith(hint: move, hintsUsed: state.hintsUsed + 1);
    return usage;
  }

  /// Sends the attempt again, after [XiangqiPuzzlePhase.unrecorded].
  ///
  /// The same counts are sent as the first time — the mistakes and the hints are facts about the
  /// attempt and do not change because a request was lost — so the server records the attempt it
  /// would have recorded, not a second one.
  Future<void> retrySubmit() => _submit();

  /// Plays the opponent's answer to the solver's last move, then submits if the line is complete.
  ///
  /// The pause is [xiangqiPuzzleReplyDelay] and it is for the reader, not for the server. Nothing
  /// can happen during it: it is not the solver's turn, so [onUserMove] ignores anything that
  /// arrives, and the only other way into this class is [hint], which is refused for the same
  /// reason.
  Future<void> _playOpponentAnswer() async {
    final answer = state.nextSolutionMove;
    if (answer != null) {
      final delay = ref.read(xiangqiPuzzleReplyDelayProvider);
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
        if (!ref.mounted) return;
      }
      _play(answer);
    }
    if (state.nextSolutionMove == null) await _submit();
  }

  /// Takes [move] back if it is still the wrong move on the board.
  ///
  /// The captured lists are the attempt before the wrong move. Nothing can be played while the move
  /// is showing — appending it flips [XiangqiPuzzleAttemptState.isSolverTurn] to false — so the only
  /// race that matters is this provider being disposed, which [Ref.mounted] covers.
  Future<void> _revertWrongMove(
    XiangqiMove move,
    IList<XiangqiPosition> positionsBefore,
    IList<XiangqiMove> movesBefore,
  ) async {
    final delay = ref.read(xiangqiPuzzleWrongMoveDelayProvider);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
      if (!ref.mounted) return;
    }
    if (state.wrongMove != move || state.moves.length != movesBefore.length + 1) return;
    state = state.copyWith(positions: positionsBefore, moves: movesBefore);
  }

  /// Plays [move] on the board and appends it to the attempt.
  void _play(XiangqiMove move) {
    state = state.copyWith(
      positions: state.positions.add(rules.play(state.position, move)),
      moves: state.moves.add(move),
      // A hint is about the position it was asked for, and the wrong-move mark is about the last
      // move; both stop meaning anything once the board moves on.
      hint: null,
      wrongMove: null,
    );
  }

  /// Submits the attempt and records what the server says about it.
  ///
  /// A failure is [XiangqiPuzzlePhase.unrecorded] rather than an error the screen has to catch: the
  /// solver's line is on the board either way, and what is lost is the server's side of the record.
  /// The screen offers [retrySubmit] for it.
  Future<void> _submit() async {
    state = state.copyWith(phase: XiangqiPuzzlePhase.submitting);
    try {
      final result = await ref
          .read(xiangqiPuzzleRepositoryProvider)
          .complete(
            puzzle.id,
            mistakes: state.mistakes,
            hintsUsed: state.hintsUsed,
            // Practice, always. The challenge queue's own submit path answers 500 on the server —
            // measured on 2026-10-16 — and this screen does not draw from that queue. See
            // `xiangqi-com-re/docs/puzzle.md`.
            mode: XiangqiPuzzleAttemptMode.practice,
          );
      if (!ref.mounted) return;
      state = state.copyWith(phase: XiangqiPuzzlePhase.recorded, recordedStatus: result.status);
    } catch (error, stackTrace) {
      _logger.warning('Could not submit the attempt at puzzle ${puzzle.id}.', error, stackTrace);
      if (!ref.mounted) return;
      state = state.copyWith(phase: XiangqiPuzzlePhase.unrecorded);
    }
  }
}
