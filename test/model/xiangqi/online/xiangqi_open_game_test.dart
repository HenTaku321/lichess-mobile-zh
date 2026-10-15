// Tests for reading one entry of `GET /api/v2/games/my-games`.
//
// The endpoint itself has only ever been seen answering the empty list — a guest session is refused
// an account of its own, so there is no way to make it hand out a game — which is exactly why the
// reader is tested this hard: it is the one place the app decides what a list entry means, and the
// fields it reads are the ones the shipped xiangqi.com client reads, not a capture of this endpoint.
//
// The shapes here are therefore the measured ones: the sibling `GET /api/v2/games/active`
// projection for the fields a list carries (`id`, `rplayer`/`bplayer` with `id`, `username`,
// `rating` and `seconds`, `game_timer` in minutes, `increment` in seconds, `is_rated`, `is_timed`,
// `moves_count`, `move_timer`, `timestamp`, `last_move_time`), and the `g_v2.get` snapshot for the
// two the list may or may not carry (`fen`, `turn_now`). Every case below says which of the two it
// is built from.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_open_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// The id of the account the token belongs to, as the token spells it: a string, whatever the
/// payload's own spelling of the same account is.
const _me = '100001';

/// One seat of a list entry, with the fields `v2/games/active` was measured to carry.
Map<String, Object?> seat({
  required Object id,
  required String username,
  int? rating,
  int? seconds,
}) => {
  'id': id,
  'username': username,
  'identity': username,
  'rating': rating,
  'seconds': seconds,
  'hidden_username': false,
  'hidden_profile_icon': false,
  'profile_image': null,
  'profile_link_token': null,
  'country': {'name': 'International', 'code': 'ZZ'},
};

/// One entry of the list, with both seats taken unless a case says otherwise.
Map<String, dynamic> entry({
  String id = 'By-TxD0QKV',
  bool isRated = true,
  bool isTimed = true,
  Object? redId = _me,
  String redName = 'Tester',
  int? redRating,
  int? redSeconds = 577,
  Object? blackId = 157007,
  String? blackName = 'jackson65',
  int? blackRating = 2831,
  int? blackSeconds = 660,
  int gameTimer = 15,
  int increment = 5,
  int moveTimer = 2,
  int movesCount = 54,
  String? turnNow,
  String? fen,
  Map<String, Object?>? invitee,
  Object? endReason,
}) => {
  'id': id,
  'is_rated': isRated,
  'is_timed': isTimed,
  'game_timer': gameTimer,
  'increment': increment,
  'move_timer': moveTimer,
  'moves_count': movesCount,
  'timestamp': '2026-10-15T13:04:43.604016',
  'last_move_time': '2026-10-15T13:18:44.179384',
  'rplayer': seat(id: redId ?? '', username: redName, rating: redRating, seconds: redSeconds),
  'bplayer': blackName == null
      ? seat(id: blackId ?? '', username: '', rating: blackRating, seconds: blackSeconds)
      : seat(id: blackId!, username: blackName, rating: blackRating, seconds: blackSeconds),
  'turn_now': ?turnNow,
  'fen': ?fen,
  'invitee': ?invitee,
  'end_reason': ?endReason,
};

/// The entry `GET /api/v2/games/my-games` really answered with, on 2026-10-15.
///
/// Captured with a signed-in account (id `536174`) and one private game of its own waiting for an
/// opponent. It is quoted here as it came off the wire, with only the fields this reader does not
/// read dropped — no value is changed and no key is renamed. This is the one test in this file that
/// is not built from a shape someone reasoned about: it is the shape the server sent.
///
/// The four things it pins, each of which the reader could have got wrong: `bplayer` is `null`
/// rather than an empty object, there is no `fen` and no `turn_now`, `game_timer: 10` agrees with
/// `rplayer.seconds: 600` (so the timer is minutes), and a game still being played carries no
/// `end_reason` key at all.
const Map<String, dynamic> capturedEntry = {
  'id': 'YKeIzcBbtY',
  'rplayer': {
    'id': 536174,
    'username': 'astralisxq',
    'identity': 'astralisxq',
    'rating': 900,
    'seconds': 600,
    'side': 1,
    'p_type': 10,
    'factor': 0,
    'result': -10,
    'hidden_username': false,
    'hidden_profile_icon': false,
    'profile_image': null,
    'profile_link_token': null,
    'country': {'name': 'Hong Kong, China', 'code': 'HK'},
  },
  'bplayer': null,
  'game_timer': 10,
  'increment': 0,
  'move_timer': 2,
  'moves_count': 0,
  'is_timed': true,
  'is_rated': false,
  'timestamp': '2026-10-15T14:06:20.089295',
  'last_move_time': null,
};

void main() {
  group('a full entry', () {
    test('is read field for field', () {
      final game = xiangqiOpenGameFromJson(
        entry(turnNow: 'black', fen: kXiangqiInitialFen),
        myUserId: _me,
      );

      expect(game, isNotNull);
      expect(game!.id, 'By-TxD0QKV');
      expect(game.isRated, isTrue);
      expect(game.mySide, XiangqiSide.red);
      expect(game.gameTimeSeconds, 900);
      expect(game.incrementSeconds, 5);
      expect(game.opponent, const LightUser(id: UserId('157007'), name: 'jackson65'));
      expect(game.opponentRating, 2831);
      expect(game.isMyTurn, isFalse);
      expect(game.movesCount, 54);
      expect(game.fen, kXiangqiInitialFen);
      expect(game.redSecondsLeft, 577);
      expect(game.blackSecondsLeft, 660);
    });

    test('reads the side from the other seat when that is the one this device holds', () {
      final game = xiangqiOpenGameFromJson(
        entry(
          redId: 157007,
          redName: 'jackson65',
          redRating: 2831,
          redSeconds: 660,
          blackId: _me,
          blackName: 'Tester',
          blackRating: null,
          blackSeconds: 577,
        ),
        myUserId: _me,
      );

      expect(game!.mySide, XiangqiSide.black);
      expect(game.opponent, const LightUser(id: UserId('157007'), name: 'jackson65'));
      expect(game.opponentRating, 2831);
      expect(game.redSecondsLeft, 660);
      expect(game.blackSecondsLeft, 577);
    });

    test('matches a guest seat, whose id is a string on both sides', () {
      final game = xiangqiOpenGameFromJson(
        entry(redId: 'guest7zuq8', redName: 'guest7zuq8', redRating: null),
        myUserId: 'guest7zuq8',
      );

      expect(game!.mySide, XiangqiSide.red);
      expect(game.opponentRating, 2831);
    });

    test('takes game_timer as minutes and increment as seconds', () {
      // The reading that pins the units: `v2/games/active` listed a `game_timer: 15, increment: 5`
      // game with 577 s and 660 s left on its clocks 841 s in, which is 15 minutes plus the
      // increments and not 15 seconds plus them.
      final game = xiangqiOpenGameFromJson(entry(gameTimer: 15, increment: 5), myUserId: _me);

      expect(game!.gameTimeSeconds, 900);
      expect(game.incrementSeconds, 5);
    });
  });

  group('the side', () {
    test('a row this device is in neither seat of is dropped, not guessed at', () {
      final game = xiangqiOpenGameFromJson(entry(redId: 1, blackId: 2), myUserId: _me);

      expect(game, isNull);
    });

    test('a row read without a session is dropped', () {
      expect(xiangqiOpenGameFromJson(entry(), myUserId: null), isNull);
      expect(xiangqiOpenGameFromJson(entry(), myUserId: ''), isNull);
    });
  });

  group('whose move it is', () {
    test('turn_now wins when the entry carries one', () {
      // A list entry that carries `turn_now` is read from it and not from the move count, so a
      // count that disagrees with it does not get a vote.
      final game = xiangqiOpenGameFromJson(entry(turnNow: 'red', movesCount: 53), myUserId: _me);

      expect(game!.isMyTurn, isTrue);
    });

    test('falls back to the move count when it carries none', () {
      // Red opens every game and the two sides alternate, which is the rule the server's own
      // `turn_now` follows: an even number of plies played means red is to move.
      expect(xiangqiOpenGameFromJson(entry(movesCount: 54), myUserId: _me)!.isMyTurn, isTrue);
      expect(xiangqiOpenGameFromJson(entry(movesCount: 55), myUserId: _me)!.isMyTurn, isFalse);
      // The same two counts, read from the other seat: it is this device's move exactly when the
      // side to move is the side it holds.
      expect(
        xiangqiOpenGameFromJson(
          entry(redId: 157007, blackId: _me, movesCount: 54),
          myUserId: _me,
        )!.isMyTurn,
        isFalse,
      );
      expect(
        xiangqiOpenGameFromJson(
          entry(redId: 157007, blackId: _me, movesCount: 55),
          myUserId: _me,
        )!.isMyTurn,
        isTrue,
      );
    });

    test("an entry with no move count is not this device's move", () {
      final json = entry()..remove('moves_count');

      expect(xiangqiOpenGameFromJson(json, myUserId: _me)!.isMyTurn, isFalse);
    });

    test("a game nobody has joined is nobody's move", () {
      // The other seat is empty, so there is no move to be had: a row that said "your turn" for it
      // would be asking for a move that cannot be played.
      final game = xiangqiOpenGameFromJson(
        entry(blackId: '', blackName: null, movesCount: 0, turnNow: 'red'),
        myUserId: _me,
      );

      expect(game!.isMyTurn, isFalse);
      expect(game.opponent, isNull);
      expect(game.opponentRating, isNull);
    });
  });

  group('the opponent', () {
    test('is the invitee while the other seat is empty', () {
      // A challenge this user sent: one seat is theirs, the other is still nobody, and the person
      // the challenge is about is the invitee.
      final game = xiangqiOpenGameFromJson(
        entry(
          blackId: '',
          blackName: null,
          blackRating: null,
          blackSeconds: null,
          invitee: seat(id: 430842, username: 'dustlark', rating: 772),
        ),
        myUserId: _me,
      );

      expect(game!.opponent, const LightUser(id: UserId('430842'), name: 'dustlark'));
      expect(game.opponentRating, 772);
    });

    test('is not the invitee when the invitee is this user', () {
      // The same field, the other direction: a challenge *to* this user names them as the invitee,
      // and the opponent is then the seat the challenger holds.
      final game = xiangqiOpenGameFromJson(
        entry(
          blackId: '',
          blackName: null,
          invitee: seat(id: _me, username: 'Tester'),
        ),
        myUserId: _me,
      );

      expect(game!.opponent, isNull);
    });
  });

  group('the position', () {
    test('is the one the entry carries', () {
      const fen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1';

      expect(xiangqiOpenGameFromJson(entry(fen: fen), myUserId: _me)!.fen, fen);
    });

    test('falls back to the starting position when the entry carries none', () {
      // `v2/games/active` was measured without a `fen`, so a list projection that drops it is a
      // shape this reader has to survive. It says so in the log rather than silently drawing a
      // board that is not the game's.
      expect(xiangqiOpenGameFromJson(entry(), myUserId: _me)!.fen, kXiangqiInitialFen);
    });
  });

  group('what the list leaves out', () {
    test('a game that has ended is not an ongoing game', () {
      expect(xiangqiOpenGameFromJson(entry(endReason: 300), myUserId: _me), isNull);
    });

    test('an entry with no id is dropped', () {
      final json = entry()..remove('id');

      expect(xiangqiOpenGameFromJson(json, myUserId: _me), isNull);
    });

    test('a missing is_rated reads as unrated, and a missing clock as no clock', () {
      final json = entry()
        ..remove('is_rated')
        ..remove('increment');
      final game = xiangqiOpenGameFromJson(json, myUserId: _me);

      expect(game!.isRated, isFalse);
      expect(game.incrementSeconds, 0);
    });

    test('an untimed entry reads as 0+0 rather than as a game that is not there', () {
      final json = entry(isTimed: false)..remove('game_timer');
      final game = xiangqiOpenGameFromJson(json, myUserId: _me);

      expect(game, isNotNull);
      expect(game!.gameTimeSeconds, 0);
    });
  });

  group('the entry the server really sent', () {
    test('is read whole', () {
      final game = xiangqiOpenGameFromJson(capturedEntry, myUserId: '536174');

      expect(game, isNotNull);
      expect(game!.id, 'YKeIzcBbtY');
      expect(game.mySide, XiangqiSide.red);
      expect(game.isRated, isFalse);
      expect(game.gameTimeSeconds, 600);
      expect(game.incrementSeconds, 0);
      expect(game.movesCount, 0);
      expect(game.redSecondsLeft, 600);
      expect(game.blackSecondsLeft, isNull);
    });

    test('a null bplayer is a seat nobody has taken, not a crash and not an opponent', () {
      final game = xiangqiOpenGameFromJson(capturedEntry, myUserId: '536174');

      expect(game!.opponent, isNull);
      expect(game.opponentRating, isNull);
    });

    test("a game waiting for an opponent is nobody's move", () {
      // The entry carries no `turn_now` and `moves_count: 0`, which on its own would read as red to
      // move — and red is the side this device holds. There is no opponent to move against, so the
      // row must not claim it is this user's turn.
      expect(xiangqiOpenGameFromJson(capturedEntry, myUserId: '536174')!.isMyTurn, isFalse);
    });

    test('carries no position, so the row falls back to the starting one', () {
      expect(xiangqiOpenGameFromJson(capturedEntry, myUserId: '536174')!.fen, kXiangqiInitialFen);
    });

    test('is dropped for a device that is not in either seat', () {
      expect(xiangqiOpenGameFromJson(capturedEntry, myUserId: '999999'), isNull);
    });
  });

  group('the whole body', () {
    test('is read in the order it lists the games', () {
      final games = xiangqiOpenGamesFromJson([
        entry(id: 'first'),
        entry(id: 'second'),
      ], myUserId: _me);

      expect(games.map((g) => g.id), ['first', 'second']);
    });

    test('drops the entries it cannot place and keeps the ones it can', () {
      final games = xiangqiOpenGamesFromJson([
        entry(id: 'mine'),
        entry(id: 'theirs', redId: 1, blackId: 2),
        entry(id: 'over', endReason: 100),
      ], myUserId: _me);

      expect(games.map((g) => g.id), ['mine']);
    });

    test('a body that is not a list of entries is an empty list', () {
      // A list this app cannot read is a list with nothing in it, not a failure of the screen it
      // is drawn on.
      expect(xiangqiOpenGamesFromJson(null, myUserId: _me), isEmpty);
      expect(xiangqiOpenGamesFromJson('[]', myUserId: _me), isEmpty);
      expect(
        xiangqiOpenGamesFromJson(<String, Object?>{'games': <Object?>[]}, myUserId: _me),
        isEmpty,
      );
      expect(xiangqiOpenGamesFromJson(<Object?>[1, 'two', null], myUserId: _me), isEmpty);
    });
  });
}
