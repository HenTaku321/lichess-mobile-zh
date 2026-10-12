import 'dart:async';

import 'package:dartchess/dartchess.dart' show Chess;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_providers.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
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

/// How hard the computer plays.
///
/// Three levels, and each one is a search limit rather than a strength setting, because Pikafish has
/// no strength setting: it declares no `Skill Level` and no `UCI_LimitStrength` — unlike
/// Fairy-Stockfish, whose negative skill levels are how the app's weakest chess opponents are made —
/// so the only dial the engine offers is how long it may think.
///
/// The three limits are measured, from the opening position, on the Pikafish this app ships:
/// `depth 3` answers after 160 nodes and a millisecond, `depth 9` after 9450 nodes and 90 ms, and
/// `movetime 2000` reaches depth 17 over 202116 nodes. The first two are therefore a move back in an
/// instant and a move in a blink, and only the third costs the computer the two seconds it is given
/// — which is why it is the only one a player can feel.
enum XiangqiDifficulty(final String label, final SearchLimit limit) {
  easy('Easy', SearchLimit.depth(3)),
  medium('Medium', SearchLimit.depth(9)),
  hard('Hard', SearchLimit.movetime(Duration(seconds: 2))),
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

/// The game in progress.
@freezed
sealed class const XiangqiGameState._() with _$XiangqiGameState {
  const factory({
    /// The side the player has, and so the side the board is drawn from.
    required XiangqiSide playerSide,
    required XiangqiDifficulty difficulty,

    /// Every position the game has been in, the initial one first — so this is one longer than
    /// [moves], and the one at the end is the game as it stands.
    required IList<XiangqiPosition> positions,
    required IList<XiangqiMove> moves,

    @Default(false) bool isEngineThinking,

    /// The piece the player has picked up, if any.
    XiangqiSquare? selected,

    /// The side that gave up, if the game ended that way.
    XiangqiSide? resignedBy,
  }) = _XiangqiGameState;

  /// The game as it stands.
  XiangqiPosition get position => positions.last;

  /// Whose move it is.
  XiangqiSide get turn => position.turn;

  bool get isPlayerTurn => turn == playerSide;

  XiangqiMove? get lastMove => moves.isEmpty ? null : moves.last;

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
    if (resignedBy != null) return .resign;
    if (isCheckmate(position)) return .checkmate;
    // 困毙: not in check, and no move to make. A loss, not a draw — see [XiangqiGameEnd].
    if (isStalemate(position)) return .stalemate;
    if (positions.where((p) => p == position).length >= kXiangqiRepetitionDraw) {
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
  int? get undoIndex {
    for (var i = positions.length - 2; i >= 0; i--) {
      if (positions[i].turn == playerSide) return i;
    }
    return null;
  }

  bool get canUndo => !isFinished && undoIndex != null;

  /// Where the selected piece may go, for the board to shade.
  IList<XiangqiMove> get selectedMoves {
    final square = selected;
    if (square == null || !isPlayerTurn || isFinished) return const IListConst([]);
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

  /// The search the engine is running for this game, so that it can be stopped once its answer stops
  /// mattering.
  Search? _search;

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
      _search?.stop();
    });

    return XiangqiGameState(
      playerSide: XiangqiSide.red,
      difficulty: XiangqiDifficulty.medium,
      positions: IList([XiangqiPosition.initial()]),
      moves: const IListConst([]),
    );
  }

  /// Starts over, with the player on [side] against a computer of [difficulty].
  void startNewGame({required XiangqiSide side, required XiangqiDifficulty difficulty}) {
    _epoch++;
    _search?.stop();
    _search = null;
    state = XiangqiGameState(
      playerSide: side,
      difficulty: difficulty,
      positions: IList([XiangqiPosition.initial()]),
      moves: const IListConst([]),
    );
    if (!state.isPlayerTurn) unawaited(_playEngineMove());
  }

  /// Acts on a touch on [square]: picks a piece up, puts one down, or ignores it.
  void tapSquare(XiangqiSquare square) {
    if (state.isFinished || state.isEngineThinking || !state.isPlayerTurn) return;

    final selected = state.selected;
    if (selected != null && state.selectedMoves.any((move) => move.to == square)) {
      _play(XiangqiMove(selected, square));
      return;
    }
    // Either nothing was picked up, or what was picked up cannot go there — in which case a piece of
    // the player's own under the finger is picked up instead, and anything else clears the selection.
    state = state.copyWith(selected: _isPlayerPiece(square) ? square : null);
  }

  /// Takes the player's last move back.
  void undo() {
    final index = state.undoIndex;
    if (!state.canUndo || index == null) return;

    _epoch++;
    _search?.stop();
    _search = null;
    // The engine has nothing to say about a position that was already played and answered, so the
    // search it may have been running is left behind rather than carried over.
    state = state.copyWith(
      positions: state.positions.sublist(0, index + 1),
      moves: state.moves.sublist(0, index),
      isEngineThinking: false,
      selected: null,
    );
  }

  /// The player gives up.
  void resign() {
    if (state.isFinished) return;
    _epoch++;
    _search?.stop();
    _search = null;
    state = state.copyWith(resignedBy: state.playerSide, isEngineThinking: false, selected: null);
  }

  bool _isPlayerPiece(XiangqiSquare square) {
    final piece = state.position.pieceAt(square);
    return piece != null && piece.side == state.playerSide;
  }

  /// Makes [move] and, if the game is still running, hands the turn to the engine.
  void _play(XiangqiMove move) {
    state = state.copyWith(
      positions: state.positions.add(play(state.position, move)),
      moves: state.moves.add(move),
      selected: null,
    );
    if (!state.isFinished && !state.isPlayerTurn) unawaited(_playEngineMove());
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
          fenOverride: state.position.toFen(),
          // A new value here is what tells the engine a new game has started, and with it to clear
          // the table it filled for the last one.
          game: epoch,
        ),
      );
      _search = search;

      final best = await search.bestMove;
      _search = null;
      // Null means the search was superseded or the engine died; either way this answer is not one.
      if (best == null || epoch != _epoch || !ref.mounted) return;

      final move = XiangqiMove.parseIccs(best);
      if (move == null || !isLegal(state.position, move)) {
        // An engine that answers with a move this game cannot play is broken rather than merely slow,
        // and there is no way to carry on: the position that would follow it does not exist.
        _logger.severe('Pikafish answered "$best", which is not a legal move in this position');
        _reportFailure();
        return;
      }
      _play(move);
    } catch (error, stackTrace) {
      _logger.warning('Failed to play the engine move', error, stackTrace);
      _reportFailure();
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
