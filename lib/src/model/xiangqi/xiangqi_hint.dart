import 'dart:async';

import 'package:dartchess/dartchess.dart' show Chess, Side;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart';
import 'package:logging/logging.dart';

part 'xiangqi_hint.freezed.dart';

final _logger = Logger('XiangqiHint');

const _kEngineFailedMessage =
    'The computer could not analyse the position. Start a new game to try again.';

/// How hard a hint and an evaluation search think.
///
/// A depth of nine, written out here rather than taken from the controller's ladder.
///
/// The ladder is a player's control — six numbered rungs, with no middle rung to point at — and this
/// is not one: what a hint and the evaluation bar are given has been this depth since before the
/// ladder was numbered. It stays bounded for the reasons it always was, a hint that thought longer
/// than the opponent's own move being one nobody waits for, and a search on an engine the opponent
/// is sharing being only safe as a short one.
const xiangqiAnalysisLimit = SearchLimit.depth(9);

/// A move the engine suggests, with the verdict the search that found it ended on.
@freezed
sealed class const XiangqiHint._() with _$XiangqiHint {
  const factory({
    /// The move the engine would play here.
    required XiangqiMove move,

    /// The engine's evaluation of the position the hint was asked for, or null when the search
    /// ended before it reached one.
    XiangqiEvaluation? evaluation,
  }) = _XiangqiHint;
}

/// The engine's verdict on a position, in **red's** point of view.
///
/// The sign is red's, not the engine's and not the side to move's — see
/// [xiangqiEvaluationFromEngine], which is the one place the flip happens. A positive [cp] or
/// [mate] means red is better or mating, whichever side happened to be to move.
@freezed
sealed class const XiangqiEvaluation._() with _$XiangqiEvaluation {
  const factory({
    /// Centipawns, red's point of view. Null for a mate score.
    int? cp,

    /// Moves to mate, red's point of view: positive means red is the one mating. Null for a
    /// centipawn score.
    int? mate,
  }) = _XiangqiEvaluation;

  /// How likely red is to win, on a bar's scale: 0 is black winning outright, 1 is red, and 0.5 is
  /// level.
  ///
  /// This reuses the app's one score-to-probability conversion, [Eval.winningChances] — white in
  /// its vocabulary stands for red here, and the score handed to it is already red-POV — rather
  /// than deriving a second one. That conversion answers in `[-1, 1]`; this shifts it onto the
  /// bar's `[0, 1]`, which is what makes 0.5 the middle and the clamp at the ends a formality.
  double get redWinProbability {
    final redChances = ExternalEval(cp: cp, mate: mate).winningChances(Side.white);
    return ((redChances + 1) / 2).clamp(0.0, 1.0);
  }
}

/// The evaluation of a position, from an engine score that is in the **side to move's** point of
/// view.
///
/// [UciInfo] reports a score the way the engine sees it: positive means the side to move is better,
/// whoever that is. Everything above this — the win probability, and the bar it drives — is red's
/// point of view, so a black-to-move position has its score flipped here, once, at the edge where
/// the engine's answer enters the model. Missing this is not a rounding error: a black advantage
/// would read as a red one and the bar would show the game the wrong way round.
XiangqiEvaluation xiangqiEvaluationFromEngine({
  required int? cp,
  required int? mate,
  required XiangqiSide sideToMove,
}) => XiangqiEvaluation(
  cp: cp == null ? null : (sideToMove == XiangqiSide.red ? cp : -cp),
  mate: mate == null ? null : (sideToMove == XiangqiSide.red ? mate : -mate),
);

/// What the xiangqi analysis has to say right now.
@freezed
sealed class const XiangqiEngineAnalysisState._() with _$XiangqiEngineAnalysisState {
  const factory({
    /// The last hint asked for, or null when none has been asked for or the last one failed.
    XiangqiHint? hint,

    /// The latest score, from whichever search — a hint's or an evaluation's — is the current one.
    XiangqiEvaluation? evaluation,

    /// Whether a search this provider started is still running.
    @Default(false) bool isBusy,
  }) = _XiangqiEngineAnalysisState;
}

/// The xiangqi engine analysis: a hint on demand, and an evaluation that streams while it runs.
///
/// Both are searches on the app's shared [Engine] — the same one [xiangqiEngineProvider] hands the
/// offline opponent — and that engine runs **one search at a time, whoever is asking**. So nothing
/// here searches in the background: every search is bounded by [xiangqiAnalysisLimit], and starting
/// one stops the one started before it. What this cannot do is tell whether the game controller is
/// mid-search; the two are connected only by the engine they share, and the caller owns the timing.
///
/// ## Contention
///
/// The caller owns the timing. Asking for a hint or an evaluation while the opponent is thinking
/// makes the engine drop the opponent's search to take this one — the opponent can lose its move,
/// and the game will sit there until the player moves again or starts over. Nothing here reaches
/// into the controller to check whose turn it is: the controller's search is its own. A view is
/// expected to offer analysis when it is the player's turn, or once the game is over.
///
/// ## Disposal
///
/// The provider is `autoDispose`, so leaving the screen tears it down, and the search is stopped in
/// [build]'s `onDispose`. Without that the shared engine would be left mid-search after the screen
/// was gone, running down a clock nobody is waiting on.
final xiangqiEngineAnalysisProvider =
    NotifierProvider.autoDispose<XiangqiEngineAnalysis, XiangqiEngineAnalysisState>(
      XiangqiEngineAnalysis.new,
      name: 'XiangqiEngineAnalysisProvider',
    );

class XiangqiEngineAnalysis() extends Notifier<XiangqiEngineAnalysisState> {
  /// The search this provider started, if one is still in flight, so that the next call can stop it
  /// and the disposal can let it go.
  Search? _search;

  /// Which search the answers arriving belong to. Bumped by everything that makes a pending answer
  /// meaningless — a new request, a manual stop, disposal — so that an answer to a question nobody
  /// is asking any more is dropped rather than written over the current state.
  int _generation = 0;

  @override
  XiangqiEngineAnalysisState build() {
    // Hold the engine open for as long as this analysis is watched, exactly as the game controller
    // does: a bare read of the engine's future is not a watcher, so it could be torn down between
    // two of these searches. A failure is only noted here; it is reported to the player by the
    // search that actually needs the engine.
    ref.listen(
      xiangqiEngineProvider,
      (_, _) {},
      onError: (error, stackTrace) {
        _logger.warning('The xiangqi engine is not available for analysis', error, stackTrace);
      },
    );

    ref.onDispose(() {
      _generation++;
      _search?.stop();
      _search = null;
    });

    return const XiangqiEngineAnalysisState();
  }

  /// Runs a bounded search of [position] and offers the engine's move as a hint.
  ///
  /// Completes when the hint is ready, or as soon as it is known there will not be one — the search
  /// was stopped or superseded, the engine failed, or it answered with a move this position cannot
  /// play. In every one of those cases the state is left clean (no hint, `isBusy: false`) and the
  /// player is told, rather than being shown a move the board would refuse.
  Future<void> requestHint(XiangqiPosition position) async {
    final generation = _restart();
    state = state.copyWith(hint: null, evaluation: null, isBusy: true);

    try {
      final search = await _startSearch(position, generation);
      // Superseded while the engine was being fetched: the request that replaced this one owns the
      // state now, so there is nothing here to undo.
      if (search == null) return;

      // The last score seen, held here as well as in the state: the hint is built from it, and the
      // `info` lines always precede the `bestmove` that ends the search, so this is the verdict the
      // search died on rather than one read back through a state copy that may not have landed yet.
      XiangqiEvaluation? latest;
      final subscription = search.infos.listen((info) {
        if (generation != _generation) return;
        latest = _evaluationOf(info, position);
        state = state.copyWith(evaluation: latest);
      });

      final best = await search.bestMove;
      await subscription.cancel();
      if (generation != _generation || !ref.mounted) return;
      _search = null;

      if (best == null) {
        // The search was stopped and its `bestmove` never came, or the engine died in the middle of
        // it. Either way there is no move to show.
        _reportFailure(null, null, generation);
        return;
      }

      final move = XiangqiMove.parseIccs(best);
      if (move == null || !isLegal(position, move)) {
        // An engine that answers with a move this position cannot play is broken rather than merely
        // odd, and there is no hint to be had from it: the position that would follow does not
        // exist, so neither does the move shown to the player.
        _logger.severe('Pikafish answered "$best", which is not a legal move in this position');
        _reportFailure(null, null, generation);
        return;
      }

      state = state.copyWith(
        hint: XiangqiHint(move: move, evaluation: latest),
        isBusy: false,
      );
    } on Object catch (error, stackTrace) {
      _reportFailure(error, stackTrace, generation);
    }
  }

  /// Starts a search of [position] and streams its score into
  /// [XiangqiEngineAnalysisState.evaluation] until it ends or [stopEvaluation] is called.
  ///
  /// Bounded like a hint, so it cannot hold the shared engine indefinitely; a caller that wants it
  /// to run on asks again when it ends.
  void startEvaluation(XiangqiPosition position) {
    final generation = _restart();
    state = state.copyWith(evaluation: null, isBusy: true);
    unawaited(_evaluate(position, generation));
  }

  /// Stops the evaluation — or a hint, since the two share the engine and the one search slot.
  void stopEvaluation() {
    _restart();
    state = state.copyWith(isBusy: false);
  }

  Future<void> _evaluate(XiangqiPosition position, int generation) async {
    try {
      final search = await _startSearch(position, generation);
      if (search == null) return;

      final subscription = search.infos.listen((info) {
        if (generation != _generation) return;
        state = state.copyWith(evaluation: _evaluationOf(info, position));
      });

      final best = await search.bestMove;
      await subscription.cancel();
      if (generation != _generation || !ref.mounted) return;
      _search = null;

      if (best == null) {
        _reportFailure(null, null, generation);
        return;
      }
      state = state.copyWith(isBusy: false);
    } on Object catch (error, stackTrace) {
      _reportFailure(error, stackTrace, generation);
    }
  }

  /// Starts a search of [position], or null if this call was superseded before the engine was
  /// ready.
  ///
  /// Throws whatever fetching the engine throws — a failed start, or the engine going away — for
  /// the caller to report.
  Future<Search?> _startSearch(XiangqiPosition position, int generation) async {
    final engine = await ref.read(xiangqiEngineProvider.future);
    if (generation != _generation || !ref.mounted) return null;

    final search = engine.search(
      SearchRequest(
        // Handed over as a FEN rather than a move list, exactly as the game controller does: this
        // is not a chess position and there is no `moves` list that says what a xiangqi move is,
        // while a standard xiangqi FEN is what `fenOverride` carries verbatim into the `position`
        // command.
        initialPosition: Chess.initial,
        moves: const IListConst([]),
        variant: Variant.standard,
        limit: xiangqiAnalysisLimit,
        fenOverride: position.toFen(),
        // The analysis is its own context for the engine's table, and `this` is stable for as long
        // as the provider lives: the engine is told `ucinewgame` once, on this screen's first
        // search, and not again on every hint. A different context here — the opponent's epoch —
        // would clear the table on every hand-off between the two, and vice versa.
        game: this,
      ),
    );
    _search = search;
    return search;
  }

  XiangqiEvaluation _evaluationOf(UciInfo info, XiangqiPosition position) =>
      xiangqiEvaluationFromEngine(cp: info.cp, mate: info.mate, sideToMove: position.turn);

  /// Stops whatever this provider is running and claims the next generation, so that answers still
  /// arriving from the old search are dropped.
  int _restart() {
    _search?.stop();
    _search = null;
    return ++_generation;
  }

  /// Leaves the state clean and tells the player, unless a newer request has already taken over.
  void _reportFailure(Object? error, StackTrace? stackTrace, int generation) {
    if (generation != _generation) return;
    if (error != null) _logger.warning('The xiangqi analysis failed', error, stackTrace);
    if (!ref.mounted) return;
    state = state.copyWith(isBusy: false);
    ref.read(uiEventBusProvider).emit(const ShowErrorEvent(_kEngineFailedMessage));
  }
}
