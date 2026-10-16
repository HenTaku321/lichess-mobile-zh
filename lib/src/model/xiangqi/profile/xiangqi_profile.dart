import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

part 'xiangqi_profile.freezed.dart';

/// One of the four ratings xiangqi.com keeps, and the name it files it under.
///
/// The wire names are the server's own and are what `users/multiplayer_stats` and
/// `users/puzzle_stats` take as `rating_type`. They are **not** the obvious spelling: the three game
/// speeds are `<speed>_rating`, and the fourth is plain `puzzle_rating` — measured on 2026-10-16,
/// where the natural-looking `multiplayer_rating` was answered `400 Invalid rating type`.
enum XiangqiRatingType(final String wireName) {
  rapid('rapid_rating'),
  bullet('bullet_rating'),
  daily('daily_rating'),
  puzzle('puzzle_rating');

  /// Whether this is a rating for a game rather than for a puzzle.
  ///
  /// The two are read from two different endpoints with two different shapes, so which one a
  /// rating is decides which call is made for it.
  bool get isGame => this != XiangqiRatingType.puzzle;
}

/// The four ratings an account has, from `GET /api/users/account/<username>`.
@freezed
sealed class const XiangqiRatings._() with _$XiangqiRatings {
  const factory({int? bullet, int? rapid, int? daily, int? puzzle}) = _XiangqiRatings;

  /// The rating of [type], or null when the account has none for it.
  int? of(XiangqiRatingType type) => switch (type) {
    .bullet => bullet,
    .rapid => rapid,
    .daily => daily,
    .puzzle => puzzle,
  };
}

/// One speed's record, from `GET /api/users/multiplayer_stats/<username>`.
@freezed
sealed class const XiangqiGameStats._() with _$XiangqiGameStats {
  const factory({
    required int wins,
    required int losses,
    required int draws,
    required int totalGames,

    /// The share of games won, as the server computed it. A percentage, not a fraction.
    required double winRate,
    int? currentRating,
    int? highestRating,
  }) = _XiangqiGameStats;
}

/// An account's puzzle record, from `GET /api/users/puzzle_stats/<username>`.
@freezed
sealed class const XiangqiPuzzleStats._() with _$XiangqiPuzzleStats {
  const factory({
    required int attempted,

    /// The share of attempts that were solved, as the server computed it.
    required double successRate,
    int? currentRating,
    int? highestRating,
  }) = _XiangqiPuzzleStats;
}

/// One row of a leaderboard, from `GET /api/leaders/v2/list`.
///
/// The two boards carry different fields — a puzzle board counts `challenge_attempts` and has no
/// `win_rate`, a game board the other way round — so both are nullable and the screen prints
/// whichever the server sent. Measured on 2026-10-16: the three game boards answered with **no
/// rows at all**, so only the puzzle half of that pair has ever been seen with a value in it.
@freezed
sealed class const XiangqiLeaderboardEntry._() with _$XiangqiLeaderboardEntry {
  const factory({
    /// Where the row sits on the board, counted from one.
    required int rank,

    required XiangqiLivePlayer player,

    /// The rating the board is for.
    required int rating,

    /// How many puzzles this account has attempted, on a puzzle board.
    int? challengeAttempts,

    /// The share of games won, on a game board.
    double? winRate,
  }) = _XiangqiLeaderboardEntry;
}

/// One page of a leaderboard.
@freezed
sealed class const XiangqiLeaderboard._() with _$XiangqiLeaderboard {
  const factory({
    required IList<XiangqiLeaderboardEntry> entries,

    /// How many pages the board has, as the server counted them.
    required int totalPages,

    /// How many accounts are on it.
    required int totalPlayers,

    /// Which page this is, counted from one.
    required int currentPage,
  }) = _XiangqiLeaderboard;

  /// Whether there is a page after this one.
  bool get hasNextPage => currentPage < totalPages;
}

/// One row of an account's game history, from `GET /api/users/games/<username>`.
///
/// A summary and nothing more: the endpoint carries no moves and no position, the same way the live
/// list does not — see `xiangqi-com-re/docs/profile.md`. What it does carry is how the game ended
/// and, sometimes, how well each side played.
@freezed
sealed class const XiangqiGameSummary._() with _$XiangqiGameSummary {
  const factory({
    required String id,

    /// xiangqi.com's own state code: `2` while the game is on, `3` once it is over.
    required int state,

    /// xiangqi.com's own end-reason code, or null while the game is still being played.
    int? endReason,

    required int movesCount,
    required int gameTimeSeconds,
    required int incrementSeconds,

    /// The two seats, either of which may be empty on a game nobody has joined.
    XiangqiLivePlayer? red,
    XiangqiLivePlayer? black,

    /// When the last move was played, or null before the first one.
    DateTime? lastMoveAt,

    /// Which side won, or null for a game that is not over or ended in a draw.
    ///
    /// Read from the two seats' own `result` codes rather than from the end reason: the reason says
    /// *how* the game ended and the codes say *who* it ended for, which is the same split the
    /// socket's `game.server.end` frame makes. See [xiangqiGameWinner].
    XiangqiSide? winner,
  }) = _XiangqiGameSummary;

  /// Whether the game is over.
  bool get isFinished => state == 3;
}

/// A page of an account's game history.
@freezed
sealed class const XiangqiGameHistory._() with _$XiangqiGameHistory {
  const factory({
    required IList<XiangqiGameSummary> games,
    required int totalPages,
    int? nextPage,
  }) = _XiangqiGameHistory;

  /// Whether there is a page after this one.
  bool get hasNextPage => nextPage != null;
}

/// The ratings [json] carries, read for the four this app shows.
XiangqiRatings xiangqiRatingsFromJson(Map<String, dynamic> json) => XiangqiRatings(
  bullet: _int(json['bullet_rating']),
  rapid: _int(json['rapid_rating']),
  daily: _int(json['daily_rating']),
  puzzle: _int(json['puzzle_rating']),
);

/// The game record [json] describes, from `users/multiplayer_stats`.
XiangqiGameStats xiangqiGameStatsFromJson(Map<String, dynamic> json) => XiangqiGameStats(
  wins: _int(json['wins']) ?? 0,
  losses: _int(json['losses']) ?? 0,
  draws: _int(json['draws']) ?? 0,
  totalGames: _int(json['total_games']) ?? 0,
  winRate: _double(json['win_rate']) ?? 0,
  currentRating: _int(json['current_rating']),
  highestRating: _int(json['highest_rating']),
);

/// The puzzle record [json] describes, from `users/puzzle_stats`.
XiangqiPuzzleStats xiangqiPuzzleStatsFromJson(Map<String, dynamic> json) => XiangqiPuzzleStats(
  attempted: _int(json['attempted']) ?? 0,
  successRate: _double(json['success_rate']) ?? 0,
  currentRating: _int(json['current_rating']),
  highestRating: _int(json['highest_rating']),
);

/// A page of a leaderboard, read from a `leaders/v2/list` body.
///
/// **An empty board is a board, not a failure.** The three game boards answered `total_players: 0`
/// and `data: []` on 2026-10-16, and that is a page with nothing on it rather than an error — see
/// `xiangqi-com-re/docs/profile.md`. A body this reader cannot read at all is an empty board too,
/// for the same reason a list this app cannot read is a list with nothing in it.
XiangqiLeaderboard xiangqiLeaderboardFromJson(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const XiangqiLeaderboard(
      entries: IListConst([]),
      totalPages: 0,
      totalPlayers: 0,
      currentPage: 1,
    );
  }
  final meta = json['meta'];
  final metaMap = meta is Map<String, dynamic> ? meta : const <String, dynamic>{};
  final currentPage = _int(metaMap['current_page']) ?? 1;

  final entries = <XiangqiLeaderboardEntry>[];
  final data = json['data'];
  if (data is List) {
    for (final row in data) {
      if (row is! Map<String, dynamic>) continue;
      final player = xiangqiLivePlayerFromJson(row['user']);
      final rating = _int(row['rating']);
      // A row with nobody in it or no rating is not a row: the rank is what the list is for, and a
      // rank with nothing to rank would be a blank line.
      if (player == null || rating == null) continue;
      entries.add(
        XiangqiLeaderboardEntry(
          rank: (currentPage - 1) * kXiangqiLeaderboardPageSize + entries.length + 1,
          player: player,
          rating: rating,
          challengeAttempts: _int(row['challenge_attempts']),
          winRate: _double(row['win_rate']),
        ),
      );
    }
  }

  return XiangqiLeaderboard(
    entries: entries.lock,
    totalPages: _int(metaMap['total_pages']) ?? 0,
    totalPlayers: _int(metaMap['total_players']) ?? 0,
    currentPage: currentPage,
  );
}

/// How many rows a leaderboard page holds.
///
/// The server's own page size, and not a setting: measured on 2026-10-16, `page=1` and `page=2` of
/// the puzzle board answered with rows whose ranks ran one to a page and then the next page's ranks
/// ran on from there, which is how the size is known. It is written down here because the ranks are
/// **not** in the body — the server sends the order and the page number, and a row's rank is worked
/// out from where it sits.
const int kXiangqiLeaderboardPageSize = 15;

/// A page of an account's game history, read from a `users/games/<username>` body.
XiangqiGameHistory xiangqiGameHistoryFromJson(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const XiangqiGameHistory(games: IListConst([]), totalPages: 0);
  }
  final games = <XiangqiGameSummary>[];
  final items = json['items'];
  if (items is List) {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final id = _string(item['id']);
      if (id == null) continue;
      games.add(
        XiangqiGameSummary(
          id: id,
          state: _int(item['state']) ?? 0,
          endReason: _int(item['end_reason']),
          movesCount: _int(item['moves_count']) ?? 0,
          gameTimeSeconds: (_int(item['game_timer']) ?? 0) * 60,
          incrementSeconds: _int(item['increment']) ?? 0,
          red: xiangqiLivePlayerFromJson(item['rplayer']),
          black: xiangqiLivePlayerFromJson(item['bplayer']),
          lastMoveAt: _dateTime(item['last_move_time']),
          winner: xiangqiGameWinner(item['rplayer'], item['bplayer']),
        ),
      );
    }
  }
  return XiangqiGameHistory(
    games: games.lock,
    totalPages: _int(json['total_pages']) ?? 0,
    nextPage: _int(json['next_page_num']),
  );
}

/// The side that won the game an item describes, or null when nobody did.
///
/// Read the way the socket's own end frames are read: `result` is 30 for the winner and 10 for the
/// loser, and `-10` is the sentinel a game that is not over carries on both seats. A draw has 20 on
/// both, and a game still being played has the sentinel on both, so neither names a winner.
///
/// [red] and [black] are the raw seat objects, which is where the codes live — [XiangqiLivePlayer]
/// does not carry one, because the live list is a list of games being played and never has a
/// result to report.
XiangqiSide? xiangqiGameWinner(Object? red, Object? black) {
  final redResult = _int(red is Map<String, dynamic> ? red['result'] : null);
  final blackResult = _int(black is Map<String, dynamic> ? black['result'] : null);
  if (redResult == kXiangqiResultWin) return XiangqiSide.red;
  if (blackResult == kXiangqiResultWin) return XiangqiSide.black;
  return null;
}

/// The `result` code a seat carries when it won.
const int kXiangqiResultWin = 30;

/// The `result` code a seat carries when it lost.
const int kXiangqiResultLoss = 10;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;

DateTime? _dateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}
