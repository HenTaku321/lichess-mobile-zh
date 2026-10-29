import 'dart:async';

import 'package:dartchess/dartchess.dart' show Chess;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_providers.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart' show MoveVerdict;
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart'
    show XiangqiEvaluation, xiangqiEvaluationFromEngine;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';
import 'package:lichess_mobile/src/service/pikafish_nnue_service.dart';
import 'package:logging/logging.dart';

part 'xiangqi_game_controller.freezed.dart';

final _logger = Logger('XiangqiGameController');

/// How many times one position has to come back before the game is called a draw.
///
/// Three, as it is in chess, and for the same reason: two sides with nothing to play for can shuffle
/// forever, and the game has to end somewhere. What this is *not* is the real xiangqi rule — 长将
/// and 长捉 are forbidden and judged as the side doing it losing, which needs the attack to be
/// classified rather than counted. Counting is the approximation here; the honest version is a
/// separate piece of work.
const kXiangqiRepetitionDraw = 3;

const _kEngineFailedMessage =
    'The computer could not answer with a move. Start a new game to try again.';

/// How hard the computer plays: six levels, each of them a search budget rather than a strength
/// setting.
///
/// Six and not the chess game's twelve, because the dial is not the same dial. Chess's levels rest
/// on Stockfish's `Skill Level`, which walks down to a genuinely weaker opponent — Fairy-Stockfish's
/// negative levels are how the app's weakest chess opponents are made. Pikafish has no such setting:
/// its complete UCI option list is Debug Log File, NumaPolicy, Threads, Hash, Clear Hash, Ponder,
/// MultiPV, Move Overhead, nodestime, UCI_ShowWDL and EvalFile, and there is no `Skill Level`, no
/// `UCI_LimitStrength` and no `UCI_Elo` among them. The only thing a level can change here is how the
/// search is budgeted, and on that axis `depth 1` is already a search that will take anything —
/// nothing weaker exists. The upper half of a twelve-step ladder would be a knob that turns without
/// changing anything, so the ladder is as long as its one real axis holds: six.
///
/// The curve is xiangqi.com's own, re-sampled. Their ten levels are a `(depth, move_time, skill,
/// multi_pv)` table, and their first three share a depth and a move time and differ only in MultiPV —
/// a column this app does not use — so on a search-budget-only axis the table has eight points, and
/// these six rungs are every other one of them with both ends kept: their level 1 is level 1 here,
/// their level 10 is level 6, and the four between are their fourth, sixth, eighth and ninth. Both
/// columns rise strictly from end to end, which is the whole point: the rungs are ordered, and no
/// level is ever weaker than the one under it. The spacing between neighbouring rungs is a starting
/// point and may be re-tuned by feel; the ordering and the two ends are not.
///
/// A rung is both a deadline and a depth cap at once — see [SearchLimit.movetimeAndDepth] — because
/// on its own neither says what a level is. The other limits are untouched: a depth-only or a
/// movetime-only search is still exactly what an analysis screen or a hint asks for elsewhere.
///
/// What a level is called is the view's business, not the model's: a model cannot read a
/// `BuildContext`, so it owns the number and the view puts it on screen.
enum XiangqiDifficulty(final int depth, final Duration moveTime) {
  level1(1, Duration(milliseconds: 1)),
  level2(2, Duration(milliseconds: 10)),
  level3(4, Duration(milliseconds: 30)),
  level4(6, Duration(milliseconds: 50)),
  level5(8, Duration(milliseconds: 100)),
  level6(15, Duration(milliseconds: 500));

  /// The level as a number, 1 to 6 — how the view writes it, and what the slider moves along.
  int get level => index + 1;

  /// The search this level is.
  SearchLimit get limit => SearchLimit.movetimeAndDepth(duration: moveTime, depth: depth);

  /// The level a new game starts at.
  static const defaultLevel = XiangqiDifficulty.level4;
}

/// Who is sitting on the other side of the board.
///
/// Two seats, and the difference is not difficulty but who may move. [engine] is the game the app
/// has always played: one human side against Pikafish, which answers. [human] is two people at one
/// board, where whoever is to move may move and no search is ever started — the over-the-board
/// screen is the only thing that sets it.
///
/// Defaulted everywhere to [engine] so that every call site written before this existed goes on
/// meaning exactly what it meant.
enum XiangqiOpponent() {
  engine,
  human,
}

/// How the game ended, if it has.
///
/// Checkmate and stalemate are two names for the same result here: in xiangqi a side with no legal
/// move loses whether or not it is in check — 困毙 is a loss, where the same position in chess is a
/// draw — so the only thing that tells them apart is whether the general was under attack.
enum XiangqiGameEnd() {
  checkmate,
  stalemate,
  threefoldRepetition,
  resign,

  /// A clock ran out. Which side is the side that lost, and it is remembered rather than derived —
  /// see [XiangqiGameState.flaggedSide].
  timeout,
}

/// The xiangqi engine, started on demand and kept up for as long as the game wants it.
///
/// Pikafish takes its network as a path rather than from bytes — see [PikafishNnueService] — so this
/// resolves that path first and hands it to the spec, which is why the engine is behind a `Future`
/// rather than available outright.
///
/// The engine itself is the app's shared one and is held exactly the way every other caller holds
/// it: a listener for the life of this provider, so that the engine cannot be disposed between two
/// of this game's searches. See [EngineHolder].
final xiangqiEngineProvider = FutureProvider.autoDispose<Engine>((Ref ref) async {
  final nnuePath = await ref.read(pikafishNnueServiceProvider).ensureNnue();
  final spec = PikafishSpec(nnuePath: nnuePath);

  // Writing the network out is a file write of 48 MB, which is long enough for the screen to be
  // left while it happens.
  if (!ref.mounted) throw EngineNoLongerWatched(spec);

  ref.listen(engineProvider(spec), (_, _) {});
  return await ref.read(engineProvider(spec).future);
}, name: 'XiangqiEngineProvider');

/// One evaluation of a move the player made in practice mode.
@immutable
final class const XiangqiPracticeComment({
  required final MoveVerdict verdict,
  required final XiangqiMove? bestMove,
  required final XiangqiEvaluation? evaluation,

  /// The suggested move in Chinese notation, captured against the position it was played in.
  required final String? suggestionNotation,

  /// The evaluation after the move, in red's point of view.
  required final String? evalAfter,
});

/// The game in progress.
@freezed
sealed class const XiangqiGameState._() with _$XiangqiGameState {
  const factory({
    /// The side the player has, and so the side the board is drawn from.
    required XiangqiSide playerSide,
    required XiangqiDifficulty difficulty,

    /// Who is on the other side: Pikafish, or a second person at the same board.
    @Default(XiangqiOpponent.engine) XiangqiOpponent opponent,

    /// Every position the game has been in, the initial one first — so this is one longer than
    /// [moves], and the one at the end is the game as it stands.
    required IList<XiangqiPosition> positions,
    required IList<XiangqiMove> moves,

    @Default(false) bool isEngineThinking,

    /// The time control the game is played with. Infinite when the setup sheet did not ask for a
    /// clock, which is what every xiangqi computer game was before the clock was wired in.
    @Default(TimeIncrement.infinite()) TimeIncrement timeIncrement,

    /// Whether the player's moves are evaluated and commented on after they are played.
    @Default(false) bool practiceMode,

    /// Whether the current player move is still being evaluated in practice mode.
    @Default(false) bool isEvaluatingMove,

    /// Player-move verdicts keyed by the index of the position after that move.
    @Default(IMapConst({})) IMap<int, XiangqiPracticeComment> practiceComments,

    /// The practice suggestion currently drawn on the board, if any.
    XiangqiMove? showingSuggestedMove,

    /// Which position of [positions] is on the board. `-1` follows the live end of the game.
    @Default(-1) int cursor,

    /// The piece the player has picked up, if any.
    XiangqiSquare? selected,

    /// The side that gave up, if the game ended that way.
    XiangqiSide? resignedBy,

    /// The side whose clock ran out, if the game ended that way.
    ///
    /// Remembered rather than worked out from which clock reads zero, because a move and a flag can
    /// land in the same frame: the clock knows whose time it was when it stopped being, but by the
    /// time anyone asks, the turn may have moved on to the other side.
    XiangqiSide? flaggedSide,
  }) = _XiangqiGameState;

  /// The position drawn on the board.
  XiangqiPosition get position => positions[viewCursor];

  /// The live end of the game, which is where moves are played and results are decided.
  XiangqiPosition get gamePosition => positions.last;

  /// Which position the board is showing.
  int get viewCursor => cursor < 0 ? positions.length - 1 : cursor.clamp(0, positions.length - 1);

  /// Whether the board is at the live end of the game.
  bool get isAtLivePosition => viewCursor == positions.length - 1;

  /// Whose move it is in the game as it stands, not in a position being reviewed.
  XiangqiSide get turn => gamePosition.turn;

  /// Whether the side to move is one a person at this board may move.
  ///
  /// Against the engine it is the player's own side. Over the board both sides are a person's, so
  /// whoever is to move may move. This is the one question the rest of the game asks before a touch
  /// does anything, and before the engine is given a turn at all.
  bool get isPlayerTurn => opponent == .human || turn == playerSide;

  /// Input and drag affordances use the same policy; history and finished boards are read-only.
  bool get canMovePieces =>
      !isFinished && !isEngineThinking && !isEvaluatingMove && isAtLivePosition && isPlayerTurn;

  bool canMovePiece(XiangqiPiece piece) => canMovePieces && piece.side == turn;

  /// The live player's verdict, including after the computer has answered it.
  XiangqiPracticeComment? get practiceComment =>
      practiceComments[positions.length - 1] ?? practiceComments[positions.length - 2];

  /// The last surviving verdict, only used faded while the next move is evaluated.
  XiangqiPracticeComment? get previousPracticeComment {
    for (var ply = positions.length - 1; ply > 0; ply--) {
      final comment = practiceComments[ply];
      if (comment != null) return comment;
    }
    return null;
  }

  XiangqiMove? get lastMove => viewCursor == 0 ? null : moves[viewCursor - 1];

  /// How the game ended, or null while it is still running.
  ///
  /// Derived rather than stored, because every one of these is a question about the positions and
  /// the answer kept in a field beside them would be a copy that can go stale — which is exactly
  /// what taking a move back does to it.
  ///
  /// Every question is asked of the position at the end and nothing else, so where the game stands
  /// is the whole of the answer: a game is mate because the side to move is mated, and not because
  /// of how it got there.
  XiangqiGameEnd? get end {
    // A resignation and a flag are events rather than questions about the board — the position left
    // after either one is still a position that can be played — so they are asked first. Both are
    // remembered as which side it was, which is the only thing about them the position cannot say.
    if (resignedBy != null) return .resign;
    if (flaggedSide != null) return .timeout;
    if (isCheckmate(gamePosition)) return .checkmate;
    // 困毙: not in check, and no move to make. A loss, not a draw — see [XiangqiGameEnd].
    if (isStalemate(gamePosition)) return .stalemate;
    if (positions.where((p) => p == gamePosition).length >= kXiangqiRepetitionDraw) {
      return .threefoldRepetition;
    }
    return null;
  }

  bool get isFinished => end != null;

  /// Who won, or null for a draw.
  XiangqiSide? get winner => switch (end) {
    .checkmate || .stalemate =>
      // The side that cannot move is the side that lost, and that is the side to move.
      turn.opposite,
    .threefoldRepetition => null,
    .resign => resignedBy!.opposite,
    // Running out of time is losing, exactly as resigning is, and the side that flagged is the side
    // that lost. See [flaggedSide] for why it is the recorded side and not the side to move.
    .timeout => flaggedSide!.opposite,
    null => null,
  };

  /// Whether the side to move is in check, which the board warns about.
  bool get isInCheck => isCheck(position);

  /// The index into [positions] that taking a move back goes to, or null when there is nothing of
  /// the player's to take back.
  ///
  /// Their own last move, whether or not the engine has answered it: one ply back while the computer
  /// is still thinking, two once it has replied. A player who took black has nothing to take back
  /// until the engine has opened, which is what finding no such position means.
  ///
  /// Over the board there is no engine to leave out of it: both sides were played at this board, so
  /// the position to come back to is simply the one before the last move — always one ply.
  int? get undoIndex {
    if (opponent == .human) return positions.length >= 2 ? positions.length - 2 : null;
    for (var i = positions.length - 2; i >= 0; i--) {
      if (positions[i].turn == playerSide) return i;
    }
    return null;
  }

  bool get canUndo => !isFinished && undoIndex != null;

  /// Where the selected piece may go, for the board to shade.
  IList<XiangqiMove> get selectedMoves {
    final square = selected;
    if (square == null || !isAtLivePosition || !isPlayerTurn || isFinished) {
      return const IListConst([]);
    }
    return legalMovesFrom(position, square);
  }
}

final xiangqiGameControllerProvider =
    NotifierProvider.autoDispose<XiangqiGameController, XiangqiGameState>(
      XiangqiGameController.new,
      name: 'XiangqiGameControllerProvider',
    );

class XiangqiGameController() extends Notifier<XiangqiGameState> {
  /// Which game the engine's answers belong to.
  ///
  /// Bumped by everything that makes a pending answer meaningless — a new game, a move taken back, a
  /// resignation. A search cannot be un-asked, so the answer to a question the game has moved on
  /// from still arrives, and this is what tells it apart from the answer to the current one.
  int _epoch = 0;
  int get generation => _epoch;

  /// The search the engine is running for this game, so that it can be stopped once its answer stops
  /// mattering.
  Search? _search;
  Search? _practiceMoveSearch;

  void _stopSearches() {
    _search?.stop();
    _practiceMoveSearch?.stop();
    _search = null;
    _practiceMoveSearch = null;
  }

  @override
  XiangqiGameState build() {
    // Started here rather than on the first move, so that the network is written out and the engine
    // is up while the player is still choosing a side: the first move of a game against the computer
    // should not be the moment 48 MB is read off the disk.
    ref.listen(
      xiangqiEngineProvider,
      (_, _) {},
      onError: (error, stackTrace) {
        _logger.warning('The xiangqi engine could not be started', error, stackTrace);
      },
    );

    ref.onDispose(() {
      _epoch++;
      _stopSearches();
    });

    return XiangqiGameState(
      playerSide: XiangqiSide.red,
      difficulty: XiangqiDifficulty.defaultLevel,
      positions: IList([XiangqiPosition.initial()]),
      moves: const IListConst([]),
    );
  }

  /// Starts over, with the player on [side] against a computer of [difficulty].
  ///
  /// [opponent] is who is on the other side, and left out it is the engine — what every caller
  /// written before the over-the-board screen meant. [XiangqiOpponent.human] is two people at one
  /// board, and then [difficulty] is inert: nobody is searched for, and the side that moves first
  /// is simply the side whose player moves first.
  ///
  /// [initialPosition] is where the game starts, and left out it is the standard opening
  /// ([XiangqiPosition.initial]). The position carries whose move it is, so one that is not [side]'s
  /// to move hands the opening to the other side, exactly as taking black does.
  void startNewGame({
    required XiangqiSide side,
    required XiangqiDifficulty difficulty,
    XiangqiOpponent opponent = XiangqiOpponent.engine,
    XiangqiPosition? initialPosition,
    TimeIncrement? timeIncrement,
    bool practiceMode = false,
  }) {
    _epoch++;
    _stopSearches();
    final effectiveTimeIncrement = timeIncrement ?? ref.read(xiangqiClockProvider).timeIncrement;
    state = XiangqiGameState(
      playerSide: side,
      difficulty: difficulty,
      opponent: opponent,
      positions: IList([initialPosition ?? XiangqiPosition.initial()]),
      moves: const IListConst([]),
      timeIncrement: effectiveTimeIncrement,
      practiceMode: practiceMode,
      cursor: 0,
    );
    // Retaining the control is not retaining the old remaining times or timeout flag.
    ref.read(xiangqiClockProvider.notifier).setupClock(effectiveTimeIncrement);
    // Over the board it is never the computer's turn, so this never starts a search — see
    // [XiangqiGameState.isPlayerTurn].
    if (!state.isPlayerTurn) unawaited(_playEngineMove());
  }

  /// Restores a game that was saved to disk.
  void restoreGame({
    required XiangqiGameState game,
    required TimeIncrement timeIncrement,
    Duration? redTimeLeft,
    Duration? blackTimeLeft,
  }) {
    _epoch++;
    _stopSearches();
    state = game.copyWith(
      isEngineThinking: false,
      isEvaluatingMove: false,
      showingSuggestedMove: null,
      selected: null,
      cursor: game.positions.length - 1,
    );
    ref
        .read(xiangqiClockProvider.notifier)
        .setupClock(timeIncrement, redTimeLeft: redTimeLeft, blackTimeLeft: blackTimeLeft);
    if (!state.isFinished && !timeIncrement.isInfinite) {
      ref.read(xiangqiClockProvider.notifier).resume(state.turn);
    }
    if (!state.isFinished && !state.isPlayerTurn) unawaited(_playEngineMove());
  }

  /// Acts on a touch on [square]: picks a piece up, puts one down, or ignores it.
  void clearSelection() => state = state.copyWith(selected: null);

  /// Plays a drag as one move, independently of any earlier two-tap selection.
  bool _lastMoveViaDrag = false;
  bool get lastMoveViaDrag => _lastMoveViaDrag;

  void movePiece(XiangqiSquare from, XiangqiSquare to) {
    if (!state.canMovePieces) return;
    final move = XiangqiMove(from, to);
    if (!isLegal(state.gamePosition, move)) return;
    _play(move, viaDragAndDrop: true);
  }

  void tapSquare(XiangqiSquare square) {
    if (!state.canMovePieces) return;

    final selected = state.selected;
    if (selected != null && state.selectedMoves.any((move) => move.to == square)) {
      _play(XiangqiMove(selected, square));
      return;
    }
    // Either nothing was picked up, or what was picked up cannot go there — in which case a piece of
    // the player's own under the finger is picked up instead, and anything else clears the selection.
    state = state.copyWith(selected: selected != square && _isPlayerPiece(square) ? square : null);
  }

  /// Takes the player's last move back.
  void undo() {
    final index = state.undoIndex;
    if (!state.canUndo || index == null) return;

    _epoch++;
    _stopSearches();
    // The engine has nothing to say about a position that was already played and answered, so the
    // search it may have been running is left behind rather than carried over.
    state = state.copyWith(
      positions: state.positions.sublist(0, index + 1),
      moves: state.moves.sublist(0, index),
      isEngineThinking: false,
      isEvaluatingMove: false,
      showingSuggestedMove: null,
      practiceComments: IMap({
        for (final entry in state.practiceComments.entries)
          if (entry.key <= index) entry.key: entry.value,
      }),
      selected: null,
      cursor: index,
    );
  }

  /// Shows or hides the practice-mode suggestion on the board.
  void toggleSuggestedMove(XiangqiMove? move) {
    state = state.copyWith(showingSuggestedMove: state.showingSuggestedMove == move ? null : move);
  }

  /// Puts the board back on the position at [index] in the move history.
  void goTo(int index) {
    if (state.positions.isEmpty) return;
    final clamped = index.clamp(0, state.positions.length - 1);
    state = state.copyWith(cursor: clamped, selected: null, showingSuggestedMove: null);
  }

  void goBackward() {
    if (state.viewCursor > 0) goTo(state.viewCursor - 1);
  }

  void goForward() {
    if (state.viewCursor < state.positions.length - 1) goTo(state.viewCursor + 1);
  }

  /// The player gives up.
  void resign() {
    if (state.isFinished) return;
    _epoch++;
    _stopSearches();
    state = state.copyWith(
      resignedBy: state.playerSide,
      isEngineThinking: false,
      isEvaluatingMove: false,
      showingSuggestedMove: null,
      selected: null,
    );
  }

  /// The clock has run out for [side], and the game is over.
  ///
  /// [side] is taken as an argument rather than read off the clock here, because a move and a flag
  /// can land in the same frame: by the time this runs the turn may already have moved on, and the
  /// side that lost is the side whose clock it was, not the side now to move. It ends the game the
  /// way a resignation does — the side that flagged has lost.
  void onFlag(XiangqiSide side) {
    if (state.isFinished) return;
    _epoch++;
    _stopSearches();
    state = state.copyWith(
      flaggedSide: side,
      isEngineThinking: false,
      isEvaluatingMove: false,
      showingSuggestedMove: null,
      selected: null,
    );
  }

  bool _isPlayerPiece(XiangqiSquare square) {
    final piece = state.gamePosition.pieceAt(square);
    // The piece the side to move owns. Against the engine the side to move is only ever the
    // player's, so this is the player's piece; over the board it is whichever side's turn it is,
    // which is the side whose player is at the board.
    return piece != null && piece.side == state.turn;
  }

  /// Makes [move] and, if the game is still running, hands the turn to the engine.
  void _play(XiangqiMove move, {bool viaDragAndDrop = false}) {
    _lastMoveViaDrag = viaDragAndDrop;
    final positionBefore = state.gamePosition;
    final wasPlayerMove = state.isPlayerTurn;
    final wasAtLive = state.isAtLivePosition;
    final nextPosition = play(state.gamePosition, move);

    state = state.copyWith(
      positions: state.positions.add(nextPosition),
      moves: state.moves.add(move),
      selected: null,
      showingSuggestedMove: null,
      cursor: wasAtLive ? state.positions.length : state.viewCursor,
    );

    if (state.practiceMode && wasPlayerMove && !state.isFinished) {
      unawaited(_evaluatePracticeMove(positionBefore, move));
    } else if (!state.isFinished && !state.isPlayerTurn) {
      unawaited(_playEngineMove());
    }
  }

  Future<void> _evaluatePracticeMove(XiangqiPosition before, XiangqiMove move) async {
    final epoch = _epoch;
    final positionAfter = state.gamePosition;
    final ply = state.moves.length;
    state = state.copyWith(isEvaluatingMove: true);
    try {
      final pre = await _practiceSearch(before, epoch);
      if (epoch != _epoch || !ref.mounted) return;
      final after = await _practiceSearch(positionAfter, epoch);
      if (epoch != _epoch || !ref.mounted) return;

      final preEval = pre.evaluation;
      final afterEval = after.evaluation;
      if (preEval == null || afterEval == null) return;

      double playerChances(XiangqiEvaluation evaluation) => state.playerSide == XiangqiSide.red
          ? evaluation.redWinProbability
          : 1 - evaluation.redWinProbability;

      final beforeChances = playerChances(preEval);
      final afterChances = playerChances(afterEval);
      final shift = (beforeChances - afterChances).clamp(0.0, 1.0);
      final verdict = MoveVerdict.fromShift(
        shift,
        hasBetterMove: pre.bestMove != null && pre.bestMove != move,
        winningChancesBefore: beforeChances,
        winningChancesAfter: afterChances,
      );
      state = state.copyWith(
        isEvaluatingMove: false,
        practiceComments: state.practiceComments.add(
          ply,
          XiangqiPracticeComment(
            verdict: verdict,
            bestMove: pre.bestMove,
            evaluation: afterEval,
            suggestionNotation: pre.bestMove == null
                ? null
                : xiangqiMoveNotation(before, pre.bestMove!),
            evalAfter: ExternalEval(cp: afterEval.cp, mate: afterEval.mate).evalString,
          ),
        ),
        showingSuggestedMove: null,
      );
    } catch (error, stackTrace) {
      if (epoch == _epoch && ref.mounted) {
        _logger.warning('Xiangqi practice move evaluation failed', error, stackTrace);
      }
    } finally {
      if (epoch == _epoch && ref.mounted) {
        state = state.copyWith(isEvaluatingMove: false);
        if (!state.isFinished && !state.isPlayerTurn) unawaited(_playEngineMove());
      }
    }
  }

  Future<({XiangqiMove? bestMove, XiangqiEvaluation? evaluation})> _practiceSearch(
    XiangqiPosition position,
    int epoch,
  ) async {
    final engine = await ref.read(xiangqiEngineProvider.future);
    if (epoch != _epoch || !ref.mounted) return (bestMove: null, evaluation: null);
    final search = engine.search(
      SearchRequest(
        initialPosition: Chess.initial,
        moves: const IListConst([]),
        variant: Variant.standard,
        limit: const SearchLimit.depth(9),
        fenOverride: position.toFen(),
        game: this,
      ),
    );
    _practiceMoveSearch = search;
    XiangqiEvaluation? evaluation;
    final subscription = search.infos.listen((info) {
      if (epoch != _epoch || !ref.mounted || !identical(_practiceMoveSearch, search)) return;
      if (info.cp == null && info.mate == null) return;
      evaluation = xiangqiEvaluationFromEngine(
        cp: info.cp,
        mate: info.mate,
        sideToMove: position.turn,
      );
    });
    try {
      final best = await search.bestMove;
      if (epoch != _epoch || !ref.mounted) return (bestMove: null, evaluation: null);
      final move = best == null ? null : XiangqiMove.parseIccs(best);
      if (move == null || !isLegal(position, move)) return (bestMove: null, evaluation: null);
      return (bestMove: move, evaluation: evaluation);
    } finally {
      await subscription.cancel();
      if (identical(_practiceMoveSearch, search)) _practiceMoveSearch = null;
    }
  }

  Future<void> _playEngineMove() async {
    final epoch = _epoch;
    state = state.copyWith(isEngineThinking: true);
    try {
      final engine = await ref.read(xiangqiEngineProvider.future);
      if (epoch != _epoch || !ref.mounted) return;

      final search = engine.search(
        SearchRequest(
          // The position is handed over as a FEN rather than as a move list, because this is not a
          // chess position and `moves` is a list of chess moves. A standard xiangqi FEN is what
          // `fenOverride` carries verbatim into the `position` command, which is the whole of what
          // it takes to search one on an engine layer that knows only dartchess.
          initialPosition: Chess.initial,
          moves: const IListConst([]),
          variant: Variant.standard,
          limit: state.difficulty.limit,
          fenOverride: state.gamePosition.toFen(),
          // A new value here is what tells the engine a new game has started, and with it to clear
          // the table it filled for the last one.
          game: epoch,
        ),
      );
      _search = search;

      final best = await search.bestMove;
      if (identical(_search, search)) _search = null;
      // Null means the search was superseded or the engine died; either way this answer is not one.
      if (best == null || epoch != _epoch || !ref.mounted) return;

      final move = XiangqiMove.parseIccs(best);
      if (move == null || !isLegal(state.gamePosition, move)) {
        // An engine that answers with a move this game cannot play is broken rather than merely slow,
        // and there is no way to carry on: the position that would follow it does not exist.
        _logger.severe('Pikafish answered "$best", which is not a legal move in this position');
        _reportFailure();
        return;
      }
      _play(move);
    } catch (error, stackTrace) {
      if (epoch == _epoch && ref.mounted) {
        _logger.warning('Failed to play the engine move', error, stackTrace);
        _reportFailure();
      }
    } finally {
      // Only the current game may touch the state: a search left over from a game that has been
      // replaced or taken back has no business clearing the flag of the one that replaced it.
      if (epoch == _epoch && ref.mounted) {
        state = state.copyWith(isEngineThinking: false);
      }
    }
  }

  /// Tells the player the computer is not going to move.
  ///
  /// The game is left where it stands rather than being declared over: an engine that failed is not a
  /// resignation, and inventing a result would be a worse lie than a board that stops moving. What
  /// the player has is the restart button and the reason it is needed.
  void _reportFailure() {
    if (state.isFinished) return;
    ref.read(uiEventBusProvider).emit(const ShowErrorEvent(_kEngineFailedMessage));
  }
}
