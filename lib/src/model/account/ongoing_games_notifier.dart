import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/account/ongoing_game.dart';
import 'package:lichess_mobile/src/model/account/ongoing_game_entry.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_open_game.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// The lichess side of the ongoing-games list.
class LichessOngoingGamesNotifier() extends AsyncNotifier<IList<OngoingGame>> {
  @override
  Future<IList<OngoingGame>> build() {
    final authUser = ref.watch(authControllerProvider);
    if (authUser == null) return Future.value(IList());

    return ref.withAggregatorCacheFor(
      (client, aggregator) => AccountRepository(client, aggregator).getOngoingGames(nb: 50),
      // cache is useful to reduce the number of requests to the server because this is used by
      // both the correspondence service to sync games and the home screen to display ongoing games
      const Duration(minutes: 1),
    );
  }

  /// Update the game with the given `id` with the new `game` data.
  ///
  /// If the game is not playable anymore, it will be removed from the list.
  void updateGame(GameFullId id, PlayableGame game) {
    if (!state.hasValue) return;
    final index = state.requireValue.indexWhere((e) => e.fullId == id);
    if (index == -1) return;
    if (!game.playable) {
      state = AsyncData(state.requireValue.removeAt(index));
      return;
    }

    final me = game.youAre ?? Side.white;
    final newGame = OngoingGame(
      id: game.id,
      fullId: id,
      orientation: me,
      fen: game.lastPosition.fen,
      perf: game.meta.perf,
      speed: game.meta.speed,
      variant: game.meta.variant,
      opponent: game.opponent?.user,
      isMyTurn: game.isMyTurn,
      opponentRating: game.opponent?.rating,
      opponentAiLevel: game.opponent?.aiLevel,
      lastMove: game.lastMove,
      secondsLeft:
          game.clock?.forSide(me).inSeconds ?? game.correspondenceClock?.forSide(me).inSeconds,
    );
    state = AsyncData(
      state.requireValue.replace(index, newGame).sort((a, b) {
        if (a.isMyTurn && !b.isMyTurn) return -1;
        if (!a.isMyTurn && b.isMyTurn) return 1;
        return a.secondsLeft?.compareTo(b.secondsLeft ?? 0) ?? 0;
      }),
    );
  }
}

/// The current user's ongoing games on lichess.
///
/// This is the lichess-only source. The merged [ongoingGamesProvider] watches
/// it, and every lichess-specific event (a challenge accepted, a registered
/// move played, a deep link) invalidates *this* provider: the merge then
/// recomputes from the refreshed list on its own.
final lichessOngoingGamesProvider =
    AsyncNotifierProvider<LichessOngoingGamesNotifier, IList<OngoingGame>>(
      LichessOngoingGamesNotifier.new,
      name: 'LichessOngoingGamesProvider',
    );

// ---------------------------------------------------------------------------
// SEAM — xiangqi source.
//
// This wave ships no xiangqi transport: the provider below resolves to an empty
// list and performs no network I/O at all. A later agent (owner of
// `network/xiangqi_http.dart` and the online game model) fills it in — either by
// replacing the body with a call to the xiangqi.com REST API, or by overriding
// the provider in tests. [OngoingGamesNotifier] reads the xiangqi backend only
// through this provider, so nothing else has to move when the transport lands.
//
// The `xiangqiUri` helper (`network/xiangqi_uri.dart`) is already in place for
// the call itself, and `IList<XiangqiOpenGame>` is the shape to return.
// ---------------------------------------------------------------------------

/// The xiangqi backend's contribution to the ongoing-games list.
///
/// **Stub — this wave returns an empty list and touches the network nowhere.**
/// See the seam note above.
final xiangqiOngoingGamesSourceProvider = FutureProvider<IList<XiangqiOpenGame>>(
  (ref) => const IListConst<XiangqiOpenGame>([]),
  name: 'XiangqiOngoingGamesSourceProvider',
);

/// The current user's ongoing games, from every backend, as one list.
///
/// **Merge the lists, never the scalars.** The two backends are joined at the
/// level of rows only: each `OngoingGameEntry` keeps its own backend's game
/// object intact. Their ratings are on different scales, so fusing a username,
/// a rating or an avatar across a lichess game and a xiangqi one would be
/// inventing data that neither backend said.
///
/// A failure of a *single* backend is invisible here: its rows simply drop out
/// and the merged list stays in a data state, so the UI cannot be used to work
/// out which backend is down. Only when *both* fail does this go into an error
/// state — that is a genuine, total outage.
class OngoingGamesNotifier() extends AsyncNotifier<IList<OngoingGameEntry>> {
  @override
  Future<IList<OngoingGameEntry>> build() async {
    final lichessEntries = ref.watch(lichessOngoingGamesProvider.future);
    final xiangqiEntries = ref.watch(xiangqiOngoingGamesSourceProvider.future);

    // A per-source failure is turned into an empty list, so it never surfaces as
    // an error here. The count of failures is all that is needed to tell a
    // one-backend outage (invisible) from a total one (an error).
    final failures = <Object>[];

    IList<OngoingGameEntry> onFailure(Object error) {
      failures.add(error);
      return const IListConst<OngoingGameEntry>([]);
    }

    // Future.wait preserves the order of its inputs regardless of which future
    // completes first, so the merged list is deterministic: lichess rows first,
    // then xiangqi rows, each in its own backend's order.
    final merged = await Future.wait<IList<OngoingGameEntry>>([
      lichessEntries.then(
        (games) => games.map<OngoingGameEntry>(ChessOngoingGame.new).toIList(),
        onError: onFailure,
      ),
      xiangqiEntries.then(
        (games) => games.map<OngoingGameEntry>(XiangqiOngoingGame.new).toIList(),
        onError: onFailure,
      ),
    ]);

    if (failures.length == 2) {
      throw failures.first;
    }

    return merged.expand((games) => games).toIList();
  }

  /// Update the chess game with the given `id` with the new `game` data.
  ///
  /// The lichess source stays authoritative — `CorrespondenceService` reads it —
  /// so this delegates to it; the merged list recomputes from the refreshed
  /// source, replacing the matching [ChessOngoingGame] (or dropping it once the
  /// game is no longer playable).
  void updateGame(GameFullId id, PlayableGame game) {
    ref.read(lichessOngoingGamesProvider.notifier).updateGame(id, game);
  }
}

/// A provider that fetches the current user's ongoing games from every backend.
final ongoingGamesProvider = AsyncNotifierProvider<OngoingGamesNotifier, IList<OngoingGameEntry>>(
  OngoingGamesNotifier.new,
  name: 'OngoingGamesProvider',
);
