// Tests for reading one entry of `GET /api/v2/games/active`.
//
// The reader is the one place the app decides what a live-list entry means, so it is tested against
// the shape the endpoint was measured sending on 2026-10-16 — the key names, the units, the two
// sentinel values — with every value replaced. Not one username, rating or id here is the
// capture's; the capture itself is in `xiangqi-com-re/captures/watch/`.
//
// Two things about the shape are worth knowing before reading the cases below, because each of them
// is a way the reader could have been wrong and each has a test of its own: `game_timer` and
// `move_timer` are **minutes** while `increment` and a seat's `seconds` are **seconds**, and
// `p_type` is what says whether a seat is a person at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// One seat of a list entry, with the fields `v2/games/active` was measured to carry.
Map<String, Object?> seat({
  Object id = 1,
  String username = 'player',
  int? rating = 1500,
  int? seconds = 600,
  int pType = 10,
  String? identity,
  Map<String, Object?>? country = const {'name': 'Viet Nam', 'code': 'VN'},
}) => {
  'id': id,
  'username': username,
  'identity': identity ?? username,
  'rating': rating,
  'seconds': seconds,
  'p_type': pType,
  'side': 1,
  'factor': 0,
  'result': -10,
  'hidden_username': false,
  'hidden_profile_icon': false,
  'profile_image': null,
  'profile_link_token': null,
  'country': country,
};

/// One entry of the list, with both seats taken unless a case says otherwise.
Map<String, dynamic> entry({
  Object? id = 'AbCdEf1234',
  bool isRated = true,
  bool isTimed = true,
  int gameTimer = 20,
  int increment = 5,
  int moveTimer = 5,
  int movesCount = 144,
  Map<String, Object?>? red,
  Map<String, Object?>? black,
  Object? timestamp = '2026-10-16T07:56:58.241092',
  Object? lastMoveTime = '2026-10-16T08:37:27.313354',
}) => {
  'id': id,
  'is_rated': isRated,
  'is_timed': isTimed,
  'game_timer': gameTimer,
  'increment': increment,
  'move_timer': moveTimer,
  'moves_count': movesCount,
  'timestamp': timestamp,
  'last_move_time': lastMoveTime,
  'rplayer': red ?? seat(id: 157013, username: 'red-one', rating: 2815, seconds: 423),
  'bplayer': black ?? seat(id: 464493, username: 'black-two', rating: 2869, seconds: 281),
};

void main() {
  group('a full entry', () {
    test('is read field for field', () {
      final game = xiangqiLiveGameFromJson(entry())!;

      expect(game.id, 'AbCdEf1234');
      expect(game.isRated, isTrue);
      expect(game.red.name, 'red-one');
      expect(game.red.rating, 2815);
      expect(game.red.secondsLeft, 423);
      expect(game.black.name, 'black-two');
      expect(game.black.rating, 2869);
      expect(game.black.secondsLeft, 281);
      expect(game.movesCount, 144);
    });

    test('reads the two timers as minutes and the increment as seconds', () {
      final game = xiangqiLiveGameFromJson(entry(gameTimer: 20, moveTimer: 5, increment: 5))!;

      // The same entry was measured with 423 s left on a clock of a 20-minute game, which is the
      // reading that makes `game_timer` minutes: twenty minutes is twelve hundred seconds.
      expect(game.gameTimeSeconds, 1200);
      expect(game.moveTimeSeconds, 300);
      expect(game.incrementSeconds, 5);
    });

    test('reads the timestamps, and drops one it cannot parse', () {
      final game = xiangqiLiveGameFromJson(entry())!;
      expect(game.startedAt, DateTime(2026, 10, 16, 7, 56, 58, 241, 92));
      expect(game.lastMoveAt, DateTime(2026, 10, 16, 8, 37, 27, 313, 354));

      final unreadable = xiangqiLiveGameFromJson(
        entry(timestamp: 'not a date', lastMoveTime: null),
      )!;
      expect(unreadable.startedAt, isNull);
      expect(unreadable.lastMoveAt, isNull);
    });
  });

  group('the side to move', () {
    test('is red after an even number of plies and black after an odd one', () {
      // Red opens every game, so the parity of the ply count is the side to move. This is the rule
      // the server's own `turn_now` follows, and the only one available here — the list carries no
      // `turn_now` at all.
      expect(xiangqiLiveGameFromJson(entry(movesCount: 0))!.turn, XiangqiSide.red);
      expect(xiangqiLiveGameFromJson(entry(movesCount: 1))!.turn, XiangqiSide.black);
      expect(xiangqiLiveGameFromJson(entry(movesCount: 144))!.turn, XiangqiSide.red);
      expect(xiangqiLiveGameFromJson(entry(movesCount: 145))!.turn, XiangqiSide.black);
    });
  });

  group('a seat', () {
    test('is a bot only for the two bot p_types', () {
      // `p_type` is `{AUTHENTICATED: 10, GUEST: 20, BOT: 30, GUEST_BOT: 40}` in the shipped bundle,
      // and the live list was measured carrying both 10 and 30.
      expect(xiangqiLiveGameFromJson(entry(red: seat(pType: 10)))!.red.isBot, isFalse);
      expect(xiangqiLiveGameFromJson(entry(red: seat(pType: 20)))!.red.isBot, isFalse);
      expect(xiangqiLiveGameFromJson(entry(red: seat(pType: 30)))!.red.isBot, isTrue);
      expect(xiangqiLiveGameFromJson(entry(red: seat(pType: 40)))!.red.isBot, isTrue);
    });

    test('is read as a person when the list carries no p_type at all', () {
      // A missing field is not evidence of a bot.
      final red = seat()..remove('p_type');
      expect(xiangqiLiveGameFromJson(entry(red: red))!.red.isBot, isFalse);
    });

    test('prefers identity over username, and falls back to username without one', () {
      // The two differ exactly when the account has hidden its name, and `identity` is the one the
      // server itself prints in that case.
      final hidden = seat(username: 'a-real-name', identity: 'Anonymous');
      expect(xiangqiLiveGameFromJson(entry(red: hidden))!.red.name, 'Anonymous');

      final noIdentity = seat(username: 'a-real-name')..remove('identity');
      expect(xiangqiLiveGameFromJson(entry(red: noIdentity))!.red.name, 'a-real-name');
    });

    test('carries the country, and none when the account has not set one', () {
      final game = xiangqiLiveGameFromJson(entry())!;
      expect(game.red.countryName, 'Viet Nam');
      expect(game.red.countryCode, 'VN');

      final stateless = xiangqiLiveGameFromJson(entry(red: seat(country: null)))!;
      expect(stateless.red.countryName, isNull);
      expect(stateless.red.countryCode, isNull);
    });

    test('reads a numeric id as the string the token would spell it with', () {
      // An account id is a JSON number on this payload and the token's `sub` is a string; both spell
      // the same account, so both are read as strings.
      expect(xiangqiLiveGameFromJson(entry(red: seat(id: 157013)))!.red.id, '157013');
      expect(xiangqiLiveGameFromJson(entry(red: seat(id: 'guest7zuq8')))!.red.id, 'guest7zuq8');
    });
  });

  group('an entry that cannot be placed', () {
    test('is dropped when it has no id', () {
      expect(xiangqiLiveGameFromJson(entry(id: null)), isNull);
      expect(xiangqiLiveGameFromJson(entry(id: '')), isNull);
    });

    test('is dropped when a seat is empty', () {
      // A game with a seat nobody is in is not a game being played. An empty seat is not a seat with
      // an empty name — it is the key with a null value, or a seat whose fields are all absent.
      expect(
        xiangqiLiveGameFromJson(
          entry(
            black: seat(id: '', username: ''),
          ),
        ),
        isNull,
      );
      expect(
        xiangqiLiveGameFromJson(
          entry(
            black: seat(id: '', username: '', identity: ''),
          ),
        ),
        isNull,
      );
    });

    test('is read with nulls rather than guesses when the numbers are missing', () {
      final sparse = entry()
        ..remove('game_timer')
        ..remove('move_timer')
        ..remove('increment')
        ..remove('moves_count');
      final game = xiangqiLiveGameFromJson(sparse)!;
      expect(game.gameTimeSeconds, 0);
      expect(game.moveTimeSeconds, 0);
      expect(game.incrementSeconds, 0);
      expect(game.movesCount, 0);
      expect(game.red.rating, isNotNull);
    });
  });

  group('the list', () {
    test('keeps the order the server sent, and drops the entries it cannot place', () {
      final games = xiangqiLiveGamesFromJson(<Object?>[
        entry(id: 'first'),
        entry(id: null),
        entry(id: 'third'),
        'not an object',
      ]);
      expect(games.map((g) => g.id), ['first', 'third']);
    });

    test('is empty for a body that is not a list at all', () {
      // A list this app cannot read is a list with nothing in it, not a failure of the screen.
      expect(xiangqiLiveGamesFromJson(null), isEmpty);
      expect(xiangqiLiveGamesFromJson(<String, Object?>{'games': <Object?>[]}), isEmpty);
      expect(xiangqiLiveGamesFromJson('[]'), isEmpty);
    });
  });
}
