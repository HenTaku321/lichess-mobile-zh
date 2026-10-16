// Tests for reading a profile, a record and a leaderboard.
//
// The shapes are the ones the 2026-10-16 probe measured — see `xiangqi-com-re/docs/profile.md` —
// with every value replaced. Not one username, rating or game id here is the capture's.
//
// Two of the cases are about a shape being *thin* rather than wrong, because both were measured
// that way: the three game leaderboards answer with nobody on them, and a record for an account that
// has never played carries zeroes and empty lists rather than nulls.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// One seat of a game-history row, with the fields the endpoint was measured to carry.
Map<String, Object?> seat({
  Object id = 1,
  String username = 'player',
  int? rating = 1500,
  int result = -10,
}) => {
  'id': id,
  'username': username,
  'identity': username,
  'rating': rating,
  'result': result,
  'seconds': 600,
  'p_type': 10,
  'country': {'name': 'Viet Nam', 'code': 'VN'},
};

/// One row of a game history.
Map<String, Object?> game({
  String id = 'AbCdEf1234',
  int state = 3,
  Object? endReason = 100,
  int movesCount = 42,
  int gameTimer = 10,
  int increment = 5,
  Map<String, Object?>? red,
  Map<String, Object?>? black,
}) => {
  'id': id,
  'state': state,
  'end_reason': endReason,
  'moves_count': movesCount,
  'game_timer': gameTimer,
  'increment': increment,
  'last_move_time': '2026-10-16T08:24:45.411049',
  'accuracy': null,
  'game_page_accuracy': {'r_player': null, 'b_player': null},
  'rplayer': red ?? seat(id: 1, username: 'red-one', result: 30),
  'bplayer': black ?? seat(id: 2, username: 'black-two', result: 10),
};

void main() {
  group('the four ratings', () {
    test('are read from the account payload', () {
      final ratings = xiangqiRatingsFromJson(const {
        'bullet_rating': 900,
        'rapid_rating': 1200,
        'daily_rating': 1000,
        'puzzle_rating': 600,
      });
      expect(ratings.of(XiangqiRatingType.bullet), 900);
      expect(ratings.of(XiangqiRatingType.rapid), 1200);
      expect(ratings.of(XiangqiRatingType.daily), 1000);
      expect(ratings.of(XiangqiRatingType.puzzle), 600);
    });

    test('are null when the account has none', () {
      final ratings = xiangqiRatingsFromJson(const {});
      for (final type in XiangqiRatingType.values) {
        expect(ratings.of(type), isNull, reason: type.name);
      }
    });

    test('are filed under the wire names the stats endpoints take', () {
      // Not the obvious spelling: the three game speeds are `<speed>_rating`, and the natural
      // `multiplayer_rating` was measured answering 400 Invalid rating type.
      expect(XiangqiRatingType.rapid.wireName, 'rapid_rating');
      expect(XiangqiRatingType.bullet.wireName, 'bullet_rating');
      expect(XiangqiRatingType.daily.wireName, 'daily_rating');
      expect(XiangqiRatingType.puzzle.wireName, 'puzzle_rating');
      expect(XiangqiRatingType.puzzle.isGame, isFalse);
      expect(XiangqiRatingType.rapid.isGame, isTrue);
    });
  });

  group('a game record', () {
    test('is read field for field', () {
      final stats = xiangqiGameStatsFromJson(const {
        'wins': 12,
        'losses': 8,
        'draws': 3,
        'win_rate': 52.17,
        'total_games': 23,
        'current_rating': 1234,
        'highest_rating': 1300,
      });
      expect(stats.wins, 12);
      expect(stats.losses, 8);
      expect(stats.draws, 3);
      expect(stats.totalGames, 23);
      expect(stats.winRate, 52.17);
      expect(stats.currentRating, 1234);
      expect(stats.highestRating, 1300);
    });

    test('is zeroes rather than nulls for an account that has never played', () {
      // Measured that way: a fresh account answers with zeroes and an empty history, not with nulls.
      final stats = xiangqiGameStatsFromJson(const {
        'wins': 0,
        'losses': 0,
        'draws': 0,
        'win_rate': 0,
        'total_games': 0,
        'current_rating': 900,
        'highest_rating': 0,
        'best_win': null,
        'rating_history': <Object?>[],
      });
      expect(stats.totalGames, 0);
      expect(stats.winRate, 0);
    });
  });

  group('a puzzle record', () {
    test('is read field for field', () {
      final stats = xiangqiPuzzleStatsFromJson(const {
        'attempted': 40,
        'success_rate': 62.5,
        'current_rating': 1500,
        'highest_rating': 1600,
      });
      expect(stats.attempted, 40);
      expect(stats.successRate, 62.5);
      expect(stats.currentRating, 1500);
      expect(stats.highestRating, 1600);
    });
  });

  group('a leaderboard', () {
    test('is read with the ranks the body does not carry', () {
      // The server sends the rows in order and the page number, and no rank on the rows. A row's
      // rank is where it sits on the page, offset by the pages before it.
      final board = xiangqiLeaderboardFromJson({
        'meta': {'total_pages': 3, 'total_players': 40, 'current_page': 1},
        'data': [
          {
            'rating': 4660,
            'challenge_attempts': 1962,
            'win_rate': null,
            'user': seat(id: 321501, username: 'top-one', rating: null),
          },
          {
            'rating': 4600,
            'challenge_attempts': 1500,
            'win_rate': null,
            'user': seat(id: 321502, username: 'top-two', rating: null),
          },
        ],
      });

      expect(board.entries.length, 2);
      expect(board.entries[0].rank, 1);
      expect(board.entries[1].rank, 2);
      expect(board.entries[0].player.name, 'top-one');
      expect(board.entries[0].rating, 4660);
      expect(board.entries[0].challengeAttempts, 1962);
      expect(board.entries[0].winRate, isNull);
      expect(board.totalPlayers, 40);
      expect(board.hasNextPage, isTrue);
    });

    test('numbers a later page from where the earlier one left off', () {
      final board = xiangqiLeaderboardFromJson({
        'meta': {'total_pages': 3, 'total_players': 40, 'current_page': 2},
        'data': [
          {'rating': 4000, 'user': seat(id: 1, username: 'a')},
        ],
      });
      expect(board.entries.single.rank, kXiangqiLeaderboardPageSize + 1);
      expect(board.currentPage, 2);
    });

    test('is empty, and not a failure, when the board has nobody on it', () {
      // Measured on 2026-10-16: the rapid, bullet and daily boards all answer exactly this.
      final board = xiangqiLeaderboardFromJson(const {
        'meta': {
          'total_pages': 0,
          'total_players': 0,
          'current_page': 1,
          'user_context': {'is_ranked': false},
        },
        'data': <Object?>[],
      });
      expect(board.entries, isEmpty);
      expect(board.totalPlayers, 0);
      expect(board.hasNextPage, isFalse);
    });

    test('is empty for a body that is not a board at all', () {
      expect(xiangqiLeaderboardFromJson(null).entries, isEmpty);
      expect(xiangqiLeaderboardFromJson('nope').entries, isEmpty);
      expect(xiangqiLeaderboardFromJson(const <String, Object?>{}).currentPage, 1);
    });

    test('drops a row with nobody in it or no rating', () {
      final board = xiangqiLeaderboardFromJson({
        'meta': {'total_pages': 1, 'total_players': 3, 'current_page': 1},
        'data': [
          {'rating': 100, 'user': seat(id: 1, username: 'a')},
          {'rating': null, 'user': seat(id: 2, username: 'b')},
          {'rating': 300, 'user': null},
          {'rating': 400, 'user': seat(id: 4, username: 'd')},
        ],
      });
      expect(board.entries.map((e) => e.player.name), ['a', 'd']);
      // The rank is where the row sits among the ones that could be read, so a dropped row does not
      // leave a hole in the numbering.
      expect(board.entries.map((e) => e.rank), [1, 2]);
    });
  });

  group('a game history', () {
    test('is read field for field, with the winner from the two result codes', () {
      final history = xiangqiGameHistoryFromJson({
        'total_pages': 12,
        'next_page_num': 2,
        'prev_page_num': null,
        'has_next_page': true,
        'items': [game()],
      });

      expect(history.games.length, 1);
      final row = history.games.single;
      expect(row.id, 'AbCdEf1234');
      expect(row.state, 3);
      expect(row.endReason, 100);
      expect(row.isFinished, isTrue);
      expect(row.movesCount, 42);
      expect(row.gameTimeSeconds, 600);
      expect(row.incrementSeconds, 5);
      expect(row.red!.name, 'red-one');
      expect(row.black!.name, 'black-two');
      expect(row.winner, XiangqiSide.red);
      expect(history.totalPages, 12);
      expect(history.nextPage, 2);
      expect(history.hasNextPage, isTrue);
    });

    test('has no winner for a game that is not over', () {
      // Both seats carry the `-10` sentinel while the game is on, and `end_reason` is null.
      final history = xiangqiGameHistoryFromJson({
        'items': [
          game(
            state: 2,
            endReason: null,
            red: seat(id: 1, username: 'red-one'),
            black: seat(id: 2, username: 'black-two'),
          ),
        ],
      });
      final row = history.games.single;
      expect(row.isFinished, isFalse);
      expect(row.winner, isNull);
      expect(row.endReason, isNull);
    });

    test('has no winner for a drawn game', () {
      // A draw is 20 on both seats, which is neither the win code nor the loss code.
      final history = xiangqiGameHistoryFromJson({
        'items': [
          game(
            endReason: 400,
            red: seat(id: 1, username: 'red-one', result: 20),
            black: seat(id: 2, username: 'black-two', result: 20),
          ),
        ],
      });
      expect(history.games.single.winner, isNull);
    });

    test('is empty for an account with no games, and for a body that is not one', () {
      final empty = xiangqiGameHistoryFromJson(const {
        'items': <Object?>[],
        'total_pages': 0,
        'next_page_num': null,
      });
      expect(empty.games, isEmpty);
      expect(empty.hasNextPage, isFalse);
      expect(xiangqiGameHistoryFromJson(null).games, isEmpty);
    });
  });
}
