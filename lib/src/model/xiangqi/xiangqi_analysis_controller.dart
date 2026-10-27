import 'dart:async';

import 'package:dartchess/dartchess.dart' show Chess;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart'
    show xiangqiEngineProvider;
// `$XiangqiEvaluationCopyWith` is freezed's own generated type and is named here for the same reason
// `XiangqiEvaluation` is: [XiangqiEngineLine] holds an evaluation, and the `copyWith` freezed writes
// for that field is written in terms of this type. A `show` clause hides it along with everything
// else it does not name, and the generated code then does not compile.
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart'
    show $XiangqiEvaluationCopyWith, XiangqiEvaluation, xiangqiEvaluationFromEngine;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:logging/logging.dart';

part 'xiangqi_analysis_controller.freezed.dart';

final _logger = Logger('XiangqiAnalysis');

/// What the player is told when the engine cannot be started or dies mid-search.
///
/// Written out in English rather than translated, exactly as the game screen's own engine failure
/// is: this is a failure message on a screen that is about the engine, and the app has no key for
/// it that says anything better than the literal thing that happened.
const _kEngineFailedMessage = 'The computer could not analyse the position.';

/// How many principal variations the analysis asks the engine for.
///
/// Three, the most the app's own engine setting allows — see `EngineEvaluationPrefState`. The
/// screen shows as many of them as that setting asks for and no more; the search runs with the
/// wider set so that turning the setting up does not mean starting the search over.
const int kXiangqiAnalysisLines = 3;

/// One line of the engine's reading: a score, and the sequence it expects to follow it with.
@freezed
sealed class const XiangqiEngineLine._() with _$XiangqiEngineLine {
  const factory({
    /// The verdict on the position the line starts from, in red's point of view — see
    /// [XiangqiEvaluation], which is where the flip from the engine's side happens.
    required XiangqiEvaluation evaluation,

    /// What the engine expects to be played, from the analysed position on. Empty when the engine
    /// has a score but no line to go with it yet.
    required IList<XiangqiMove> moves,

    /// The depth the line was found at.
    @Default(0) int depth,
  }) = _XiangqiEngineLine;
}

/// A standalone xiangqi analysis: a line of play, where in it the player is looking, and what the
/// engine makes of the position there.
@freezed
sealed class const XiangqiAnalysisState._() with _$XiangqiAnalysisState {
  const factory({
    /// Every position of the line: `positions[i]` is the position after [moves] has been played `i`
    /// times, so this is always exactly one longer than [moves].
    required IList<XiangqiPosition> positions,

    /// The moves played, in ICCS — `moves[i]` is what turned `positions[i]` into `positions[i + 1]`.
    required IList<XiangqiMove> moves,

    /// Which position of the line is on the board: an index into [positions], so 0 is the position
    /// the line started from and `moves.length` is the end of it.
    @Default(0) int cursor,

    /// The square the player has picked up, or null when they have not.
    XiangqiSquare? selected,

    /// Whether the engine is being kept running on the position on the board.
    @Default(false) bool isEngineRunning,

    /// What the engine says about the position on the board, best line first.
    ///
    /// Replaced as the search deepens, and emptied whenever the board moves on so that it never says
    /// something about a position that is no longer there.
    @Default(IListConst<XiangqiEngineLine>([])) IList<XiangqiEngineLine> lines,
  }) = _XiangqiAnalysisState;

  /// The position on the board.
  XiangqiPosition get position => positions[cursor];

  /// The move that led to [position], or null at the start of the line.
  XiangqiMove? get lastMove => cursor == 0 ? null : moves[cursor - 1];

  /// Where the piece the player has picked up may go.
  IList<XiangqiMove> get selectedMoves =>
      selected == null ? const IListConst([]) : rules.legalMovesFrom(position, selected!);

  /// The engine's best line, or null before it has said anything about this position.
  XiangqiEngineLine? get bestLine => lines.isEmpty ? null : lines.first;

  /// The score of [bestLine], or null before the engine has answered.
  XiangqiEvaluation? get evaluation => bestLine?.evaluation;

  /// How deep the engine has got, or 0 before it has answered.
  int get depth => bestLine?.depth ?? 0;

  /// Whether there is nothing left to play at [position] — no legal move for the side to move.
  bool get isFinished => rules.isGameOver(position);

  /// Whether a move earlier in the line can be stepped back to.
  bool get canGoBack => cursor > 0;

  /// Whether a move later in the line can be stepped forward to.
  bool get canGoForward => cursor < moves.length;
}

/// The analysis session kept in memory while the screen is away.
///
/// A module-level variable rather than a field of anything, because it has to outlive the provider
/// it is saved from: the provider is `autoDispose`, so popping the screen tears it down, and what
/// the player comes back to is the line they were looking at rather than a fresh board. Nothing
/// reaches the disk — this is a session, not a saved analysis — so it is gone when the process is.
///
/// The cursor and the selection are not part of it: what is worth coming back to is the line of
/// play, and a player coming back to a board is looking at the end of it, which is where the cursor
/// is put.
({IList<XiangqiPosition> positions, IList<XiangqiMove> moves})? _savedSession;

/// Forgets the analysis session, so that the next visit to the screen opens on an empty board.
///
/// The chess analysis has the same escape hatch (`clearSavedStandaloneAnalysis`), and it is here for
/// the same reason: something that outlives the screen it was made on has to be droppable by
/// whoever owns that screen.
void clearSavedXiangqiAnalysis() {
  _savedSession = null;
}

/// The analysis board's own state, one session at a time.
///
/// ## The engine
///
/// The analysis drives [xiangqiEngineProvider] directly rather than borrowing the game screen's
/// [XiangqiEngineAnalysis], because what it wants from the engine is not what that offers: a search
/// that runs until it is stopped, with its own depth and its principal variations, rather than a
/// bounded hint at a fixed depth with no line attached. It is the same shared [Engine] either way —
/// one engine, one search at a time — so a screen that is open in analysis must be the only thing
/// using it, and this provider stops its search on disposal for exactly that reason.
///
/// The search is `infinite` and `multipv` three; the position is handed over as a FEN, as the game
/// controller and the hint both do, because a xiangqi position is not a chess one and there is no
/// move list that says what a xiangqi move is.
///
/// ## Lifetime
///
/// `autoDispose`: the provider lives exactly as long as the screen watches it. The line of play is
/// caught in [build]'s `onCancel` — which is the screen being popped — and the search is stopped in
/// `onDispose`, so a stopped screen is not a board the engine is still thinking about.
final xiangqiAnalysisControllerProvider =
    NotifierProvider.autoDispose<XiangqiAnalysisController, XiangqiAnalysisState>(
      XiangqiAnalysisController.new,
      name: 'XiangqiAnalysisControllerProvider',
    );

class XiangqiAnalysisController() extends Notifier<XiangqiAnalysisState> {
  /// The search running on the engine, while one is.
  Search? _search;

  /// The subscription to its `info` lines, so a restart and a disposal can stop reading them.
  StreamSubscription<UciInfo>? _infos;

  /// Which search the answers arriving belong to. Bumped by everything that makes an answer
  /// meaningless — a new position, a stop, a disposal — so that an answer to a question nobody is
  /// asking any more is dropped rather than written over the current state. [XiangqiEngineAnalysis]
  /// keeps the same count for the same reason.
  int _generation = 0;

  /// The lines of the search in flight, by the engine's own `multipv` index.
  ///
  /// A map rather than a list because the engine reports its lines one at a time and not in order:
  /// the first `info` of a new depth is not necessarily multipv 1's, and a line has to replace the
  /// one it is a better version of rather than be appended beside it.
  final Map<int, XiangqiEngineLine> _pendingLines = {};

  /// The state as it was last written, kept beside the provider's own copy of it.
  ///
  /// Every write to [state] carries this along with it — `state = _latest = …` — because the one
  /// place that has to read the line back, `onCancel` below, is a lifecycle callback, and Riverpod
  /// refuses to read a provider from inside one. The line is saved when the screen is popped, and
  /// this is where the callback finds it.
  late XiangqiAnalysisState _latest;

  @override
  XiangqiAnalysisState build() {
    // Hold the engine open for as long as this analysis is watched, exactly as the game controller
    // and the hint do: a bare read of the engine's future is not a watcher, so it could be torn down
    // between two searches. A failure is only noted here; it is reported to the player by the search
    // that actually needs the engine.
    ref.listen(
      xiangqiEngineProvider,
      (_, _) {},
      onError: (error, stackTrace) {
        _logger.warning('The xiangqi engine is not available for analysis', error, stackTrace);
      },
    );

    // Saved on cancel rather than on dispose: `autoDispose` cancels the moment the last listener
    // goes away, which is the screen being popped, and it is the line as the player left it that is
    // wanted rather than whatever a later teardown might make of it. An empty line clears the saved
    // session rather than leaving the previous one behind — coming back to a board the player had
    // already cleared should not resurrect the analysis they cleared it from.
    ref.onCancel(() {
      final saved = _latest;
      _savedSession = saved.moves.isEmpty ? null : (positions: saved.positions, moves: saved.moves);
    });

    ref.onDispose(() {
      _generation++;
      _infos?.cancel();
      _infos = null;
      _search?.stop();
      _search = null;
    });

    final saved = _savedSession;
    return _latest = saved != null
        ? XiangqiAnalysisState(
            positions: saved.positions,
            moves: saved.moves,
            cursor: saved.moves.length,
          )
        : XiangqiAnalysisState(
            positions: IList([XiangqiPosition.initial()]),
            moves: const IListConst([]),
          );
  }

  /// Starts analysing the position on the board, and keeps the engine on it until the board moves
  /// on, [stopEngine] is called, or the screen goes away.
  ///
  /// Doing nothing when the engine is already running is deliberate: a screen that asks again on
  /// every rebuild would restart the search on every rebuild, and an analysis that never gets past
  /// the first few depths is worse than no analysis. A position that changes is restarted by
  /// whichever method changed it.
  void startEngine() {
    if (state.isEngineRunning) return;
    state = _latest = state.copyWith(isEngineRunning: true);
    _restart();
  }

  /// Stops the engine. The lines it has already found stay on screen — they are still about the
  /// position on the board — and the next [startEngine] replaces them.
  void stopEngine() {
    _cancel();
    state = _latest = state.copyWith(isEngineRunning: false);
  }

  /// Plays [move] on the position on the board.
  ///
  /// The move is played from wherever in the line the player is looking, so playing after stepping
  /// back is the new continuation of the line and whatever followed the old one is dropped — the
  /// same thing playing a move means on any analysis board.
  ///
  /// Throws [rules.XiangqiIllegalMoveException] if the move cannot be played in this position.
  void play(XiangqiMove move) {
    final before = state.position;
    if (!rules.isLegal(before, move)) throw rules.XiangqiIllegalMoveException(move);
    final positions = state.positions.sublist(0, state.cursor + 1).add(rules.play(before, move));
    final moves = state.moves.sublist(0, state.cursor).add(move);
    state = _latest = state.copyWith(
      positions: positions,
      moves: moves,
      cursor: positions.length - 1,
      selected: null,
    );
    _restart();
  }

  /// Takes the move that led to the position on the board back off the line.
  ///
  /// Nothing happens at the start of the line, which is also where a game that has not begun yet is.
  void retract() {
    if (state.cursor == 0) return;
    final cursor = state.cursor - 1;
    state = _latest = state.copyWith(
      positions: state.positions.sublist(0, cursor + 1),
      moves: state.moves.sublist(0, cursor),
      cursor: cursor,
      selected: null,
    );
    _restart();
  }

  /// Puts the board on the position [cursor] moves into the line, clamped to the line's ends.
  void goTo(int cursor) {
    final target = cursor.clamp(0, state.moves.length);
    if (target == state.cursor) return;
    state = _latest = state.copyWith(cursor: target, selected: null);
    _restart();
  }

  /// Steps one move forward along the line, if there is one.
  void goForward() => goTo(state.cursor + 1);

  /// Steps one move back along the line, if there is one.
  void goBack() => goTo(state.cursor - 1);

  /// Picks up the piece on [square], or plays the piece already picked up onto it.
  ///
  /// The two-tap gesture the game screens use, and for the same reason: a tap on a square of one's
  /// own that has somewhere to go picks the piece up, a tap on a square it may reach plays the move,
  /// and a tap anywhere else puts the piece back down. See [XiangqiGameController.tapSquare].
  void tapSquare(XiangqiSquare square) {
    final selected = state.selected;
    if (selected != null && state.selectedMoves.any((move) => move.to == square)) {
      play(XiangqiMove(selected, square));
      return;
    }
    final piece = state.position.pieceAt(square);
    final selectable =
        selected != square &&
        piece != null &&
        piece.side == state.position.turn &&
        rules.legalMovesFrom(state.position, square).isNotEmpty;
    state = _latest = state.copyWith(selected: selectable ? square : null);
  }

  void clearSelection() => state = _latest = state.copyWith(selected: null);

  void movePiece(XiangqiSquare from, XiangqiSquare to) {
    final move = XiangqiMove(from, to);
    if (rules.isLegal(state.position, move)) play(move);
  }

  /// Sets the board up from [fen], which becomes the start of a new line.
  ///
  /// Throws a [FormatException] if [fen] is not a position.
  void setFen(String fen) => _setStart(XiangqiPosition.fromFen(fen));

  /// Puts the board back to the position a game starts from, as a line with no moves in it.
  void reset() => _setStart(XiangqiPosition.initial());

  void _setStart(XiangqiPosition position) {
    state = _latest = state.copyWith(
      positions: IList([position]),
      moves: const IListConst([]),
      cursor: 0,
      selected: null,
    );
    _restart();
  }

  /// Starts the engine on the position on the board again, clearing the lines that were about the
  /// one before it.
  void _restart() {
    _cancel();
    state = _latest = state.copyWith(lines: const IListConst([]));
    if (!state.isEngineRunning) return;
    unawaited(_analyse(state.position, _generation));
  }

  /// Stops the running search and claims the next generation, so that the answers still arriving
  /// from it are dropped rather than written over the state.
  void _cancel() {
    _generation++;
    _infos?.cancel();
    _infos = null;
    _pendingLines.clear();
    _search?.stop();
    _search = null;
  }

  Future<void> _analyse(XiangqiPosition position, int generation) async {
    try {
      final engine = await ref.read(xiangqiEngineProvider.future);
      // Superseded while the engine was being fetched: whatever replaced this call owns the state
      // now, so there is nothing here to start.
      if (generation != _generation || !ref.mounted) return;

      final search = engine.search(
        SearchRequest(
          // Handed over as a FEN rather than as a move list, exactly as the game controller and the
          // hint do: this is not a chess position, and a standard xiangqi FEN is what `fenOverride`
          // carries verbatim into the `position` command.
          initialPosition: Chess.initial,
          moves: const IListConst([]),
          variant: Variant.standard,
          // Infinite: the analysis runs until the board moves on or the screen is left. Nothing
          // bounds it, because on this screen the engine has no opponent to share with.
          limit: const SearchLimit.infinite(),
          fenOverride: position.toFen(),
          multiPv: kXiangqiAnalysisLines,
          // The analysis is its own context for the engine's table, and `this` is stable for as
          // long as the provider lives: the engine is told `ucinewgame` on this screen's first
          // search rather than on every position, which is what the identity is for.
          game: this,
        ),
      );
      _search = search;
      _infos = search.infos.listen((info) {
        if (generation != _generation) return;
        _onInfo(info, position);
      });
    } on Object catch (error, stackTrace) {
      if (generation != _generation || !ref.mounted) return;
      _logger.warning('The xiangqi analysis could not be started', error, stackTrace);
      _generation++;
      _search = null;
      state = _latest = state.copyWith(isEngineRunning: false, lines: const IListConst([]));
      ref.read(uiEventBusProvider).emit(const ShowErrorEvent(_kEngineFailedMessage));
    }
  }

  /// Files one `info` line into the state, under the multipv index it belongs to.
  void _onInfo(UciInfo info, XiangqiPosition position) {
    // A bound is not a score. Multipv 1's `lowerbound`/`upperbound` line is the search reporting
    // that it has established the line is at least or at most this good, which is a fact about the
    // search rather than a verdict on the position; the app's own position evaluator ignores it for
    // the same reason (see `position_evaluator.dart`). The other lines the engine reports are real
    // scores for the lines they belong to, bounds or not.
    if (info.multiPv == 1 && (info.isLowerBound || info.isUpperBound)) return;

    final moves = <XiangqiMove>[];
    for (final uci in info.pv) {
      final move = XiangqiMove.parseIccs(uci);
      if (move != null) moves.add(move);
    }

    _pendingLines[info.multiPv] = XiangqiEngineLine(
      evaluation: xiangqiEvaluationFromEngine(
        cp: info.cp,
        mate: info.mate,
        sideToMove: position.turn,
      ),
      moves: moves.lock,
      depth: info.depth,
    );

    final ordered = _pendingLines.keys.toList()..sort();
    state = _latest = state.copyWith(
      lines: [for (final index in ordered) _pendingLines[index]!].lock,
    );
  }
}
