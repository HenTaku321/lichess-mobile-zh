// Tests for reading the master-games database.
//
// The shapes are the ones the 2026-10-16 probe measured — see `xiangqi-com-re/docs/database.md` —
// with every value replaced. Not one player, slug or move here is the capture's.
//
// The case that matters most is the game: it is the one place on xiangqi.com where a game arrives in
// this app's own spelling, so what is pinned here is that the reader takes it at face value — a
// standard FEN and standard ICCS — and that it refuses a game whose moves do not replay rather than
// drawing half of one.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// A page envelope, which every list in this domain uses.
Map<String, Object?> page(List<Map<String, Object?>> items, {int? nextPage, int totalPages = 3}) =>
    {
      'items': items,
      'total_pages': totalPages,
      'next_page_num': nextPage,
      'prev_page_num': null,
      'has_next_page': nextPage != null,
    };

/// One player of the database.
Map<String, Object?> player({
  int id = 1,
  String name = 'A Player',
  String? title = 'Xiangqi Master',
  int gameCount = 478,
}) => {'id': id, 'name': name, 'title': title, 'game_count': gameCount};

/// One game in a player's list.
Map<String, Object?> row({String slug = 'a-vs-b', String result = 'won', int moveCount = 73}) => {
  'slug': slug,
  'red_player': 'A Player',
  'red_country': 'CN',
  'black_player': 'B Player',
  'black_country': 'VN',
  'tournament_name': 'A Tournament',
  'tournament_date': null,
  'move_count': moveCount,
  'result_for_player': result,
};

/// A whole game.
Map<String, Object?> game({
  String slug = 'a-vs-b',
  String result = 'red_win',
  String opening = '-',
  String fen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
  List<String> moves = const ['h2e2', 'h9g7'],
}) => {
  'slug': slug,
  'red_player': {'id': 1, 'name': 'A Player', 'title': 'Xiangqi Master'},
  'black_player': {'id': 2, 'name': 'B Player', 'title': null},
  'initial_fen': fen,
  'moves': moves,
  'move_count': moves.length,
  'result': result,
  'opening': opening,
  'tournament_name': 'A Tournament',
  'tournament_date': null,
};

void main() {
  group('the players', () {
    test('are read field for field', () {
      final players = xiangqiMasterPlayersFromJson(page([player()]));
      expect(players.items.length, 1);
      final first = players.items.single;
      expect(first.id, 1);
      expect(first.name, 'A Player');
      expect(first.title, 'Xiangqi Master');
      expect(first.gameCount, 478);
    });

    test('carry the page the server says comes next', () {
      expect(xiangqiMasterPlayersFromJson(page(const [], nextPage: 2)).hasNextPage, isTrue);
      expect(xiangqiMasterPlayersFromJson(page(const [])).hasNextPage, isFalse);
    });

    test('are empty for a body that is not a list of them', () {
      expect(xiangqiMasterPlayersFromJson(null).items, isEmpty);
      expect(xiangqiMasterPlayersFromJson(const {'items': 'nope'}).items, isEmpty);
    });

    test('drop a row with no id or no name', () {
      final players = xiangqiMasterPlayersFromJson(
        page([
          player(id: 1),
          {...player(id: 2)}..remove('name'),
          player(id: 3),
        ]),
      );
      expect(players.items.map((p) => p.id), [1, 3]);
    });
  });

  group("a player's record", () {
    test('is read field for field, with the country as a bare code', () {
      // The country is `"CN"` here and `{"code": "CN", "name": "China"}` everywhere else on the
      // site — measured that way on 2026-10-16.
      final stats = xiangqiMasterStatsFromJson(const {
        'name': 'A Player',
        'title': 'Xiangqi Master',
        'country': 'CN',
        'wins': 151,
        'losses': 158,
        'draws': 169,
        'total_games': 478,
      });
      expect(stats.name, 'A Player');
      expect(stats.country, 'CN');
      expect(stats.wins, 151);
      expect(stats.losses, 158);
      expect(stats.draws, 169);
      expect(stats.totalGames, 478);
    });
  });

  group("a player's games", () {
    test('are read with the result the server gives for that player', () {
      final games = xiangqiMasterGamesFromJson(page([row()]));
      final first = games.items.single;
      expect(first.slug, 'a-vs-b');
      expect(first.redPlayer, 'A Player');
      expect(first.blackPlayer, 'B Player');
      expect(first.redCountry, 'CN');
      expect(first.blackCountry, 'VN');
      expect(first.tournamentName, 'A Tournament');
      expect(first.moveCount, 73);
      // Relative to the player the list was asked for, which is what the server sends.
      expect(first.resultForPlayer, 'won');
    });

    test('are empty for a body that is not a list of them', () {
      expect(xiangqiMasterGamesFromJson(null).items, isEmpty);
    });
  });

  group('a whole game', () {
    test("is read at face value, in this app's own spelling", () {
      // A standard FEN and standard ICCS: nothing is translated, which is what makes this domain
      // the one that can be drawn.
      final read = xiangqiMasterGameFromJson(game())!;
      expect(read.slug, 'a-vs-b');
      expect(read.redPlayer, 'A Player');
      expect(read.blackPlayer, 'B Player');
      expect(read.redTitle, 'Xiangqi Master');
      expect(read.blackTitle, isNull);
      expect(read.initialPosition.toFen(), XiangqiPosition.initial().toFen());
      expect(read.moves, [XiangqiMove.parseIccs('h2e2'), XiangqiMove.parseIccs('h9g7')]);
      expect(read.isPlayable, isTrue);
      expect(read.positions.length, 3);
      expect(read.winner, XiangqiSide.red);
    });

    test('reads the three results the server names', () {
      expect(xiangqiMasterGameFromJson(game(result: 'red_win'))!.winner, XiangqiSide.red);
      expect(xiangqiMasterGameFromJson(game(result: 'black_win'))!.winner, XiangqiSide.black);
      expect(xiangqiMasterGameFromJson(game(result: 'draw'))!.winner, isNull);
    });

    test('reads a dash as no opening at all', () {
      // The one value measured for this field is `"-"`, which is the database saying it has no name
      // for the opening rather than an opening called `-`.
      expect(xiangqiMasterGameFromJson(game(opening: '-'))!.opening, isNull);
      expect(xiangqiMasterGameFromJson(game(opening: 'Central Cannon'))!.opening, 'Central Cannon');
    });

    test('has no positions at all when a move does not fit the one before it', () {
      // A game this app will not draw half of: a board showing a position that never happened is
      // worse than no board.
      final broken = xiangqiMasterGameFromJson(game(moves: const ['h2e2', 'h2e2']))!;
      expect(broken.isPlayable, isFalse);
      expect(broken.positions, isEmpty);
    });

    test('is null for a body that is not a game', () {
      expect(xiangqiMasterGameFromJson(null), isNull);
      expect(xiangqiMasterGameFromJson(const {'slug': 'a'}), isNull);
      expect(xiangqiMasterGameFromJson({...game(), 'initial_fen': 'not a position'}), isNull);
    });
  });
}
