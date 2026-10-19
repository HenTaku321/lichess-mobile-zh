// Tests for starting a game on xiangqi.com.
//
// The shapes are the ones the 2026-10-19 probe measured — see `xiangqi-com-re/docs/game.md` — with
// every value replaced. Not one id, name or rating here is the capture's.
//
// Three of these cases are about what the wire actually takes, and each of them is a way to get it
// wrong quietly: the quick match's body is one field and not a game, the custom game's rating window
// is a string, and the two time-control spellings are not interchangeable.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_new_game.dart';

/// A client answering whatever [answer] says, and writing down what it was asked.
MockClient client(
  List<http.Request> requests,
  ({int status, Object? body}) Function(http.Request request) answer,
) {
  return MockClient((request) async {
    requests.add(request);
    final result = answer(request);
    return http.Response(
      result.body == null ? '' : jsonEncode(result.body),
      result.status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

void main() {
  group('the quick match', () {
    test('asks with one field, and the time control is the whole of it', () async {
      final requests = <http.Request>[];
      final repository = XiangqiNewGameRepository(
        client(requests, (_) => (status: 200, body: {'message': 'Successfully scheduled request'})),
      );

      await repository.quickChallenge(XiangqiTimeControl.fifteen);

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/v2/games/quick-challenge');
      expect(jsonDecode(requests.single.body), {'config_str': '15+2/5'});
    });

    test('the four controls are the four strings the lobby builds', () {
      // Two spellings and four values, and the increment is the only thing in seconds. A control
      // that spelled its increment in minutes would ask for a game nobody can play.
      expect(XiangqiTimeControl.values.map((c) => c.configStr), [
        '5/1',
        '10/2',
        '15+2/5',
        '20+5/5',
      ]);
      expect(XiangqiTimeControl.defaultControl, XiangqiTimeControl.ten);
    });

    test('the status is searching until it names a game, and matched once it does', () async {
      final searching = XiangqiNewGameRepository(
        client(<http.Request>[], (_) => (status: 200, body: {'message': 'Search in progress...'})),
      );
      expect(await searching.challengeStatus(), isA<XiangqiChallengeSearching>());

      final matched = XiangqiNewGameRepository(
        client(<http.Request>[], (_) => (status: 200, body: {'game_id': 'AbCdEfGhIj'})),
      );
      final status = await matched.challengeStatus();
      expect(status, isA<XiangqiChallengeMatched>());
      expect((status as XiangqiChallengeMatched).gameId, 'AbCdEfGhIj');
    });

    test('cancelling is a GET with nothing in it', () async {
      final requests = <http.Request>[];
      final repository = XiangqiNewGameRepository(
        client(requests, (_) => (status: 200, body: <String, Object?>{})),
      );

      await repository.cancelQuickChallenge();

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/games/cancel-quick-challenge');
    });
  });

  group('the custom game', () {
    test('sends the whole game in one body, in the units the wire takes', () async {
      final requests = <http.Request>[];
      final repository = XiangqiNewGameRepository(
        client(requests, (_) => (status: 200, body: {'game_id': 'AbCdEfGhIj'})),
      );

      final id = await repository.createCustom(
        const XiangqiCustomGameRequest(
          timeControl: XiangqiTimeControl.twenty,
          side: XiangqiSideChoice.black,
          rated: true,
          private: false,
        ),
      );

      expect(id, 'AbCdEfGhIj');
      expect(requests.single.url.path, '/api/v2/games/create-custom');
      expect(jsonDecode(requests.single.body), {
        'is_rated': true,
        'is_private': false,
        'is_daily': false,
        'is_timed': true,
        'side': 2,
        // A string and not a number: the endpoint's own picker writes `"50"`, `"100"`, `"200"` and
        // `"Any"`, and a number there is a different field's type.
        'rating_diff': 'Any',
        // Minutes for the two timers, seconds for the increment.
        'move_time': 5,
        'game_time': 20,
        'increment': 5,
        'opponent': null,
        'opponent_email': null,
      });
    });

    test('the side is the number the wire takes, and either is zero', () {
      expect(XiangqiSideChoice.red.wireValue, 1);
      expect(XiangqiSideChoice.either.wireValue, 0);
      expect(XiangqiSideChoice.black.wireValue, 2);
    });

    test('a game the server will not name is a failure, not a game', () {
      final repository = XiangqiNewGameRepository(
        client(<http.Request>[], (_) => (status: 200, body: {'message': 'hmm'})),
      );

      expect(
        () => repository.createCustom(
          const XiangqiCustomGameRequest(timeControl: XiangqiTimeControl.five),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('an error status is thrown rather than read', () {
      final repository = XiangqiNewGameRepository(
        client(<http.Request>[], (_) => (status: 400, body: {'message': '未找到对手'})),
      );

      expect(
        () => repository.invite(gameId: 'AbCdEfGhIj', username: 'nobody'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('inviting', () {
    test('names the game and the opponent, and nothing else', () async {
      final requests = <http.Request>[];
      final repository = XiangqiNewGameRepository(
        client(requests, (_) => (status: 200, body: <String, Object?>{})),
      );

      await repository.invite(gameId: 'AbCdEfGhIj', username: 'A Player');

      expect(requests.single.url.path, '/api/v2/games/custom_game_invite');
      expect(jsonDecode(requests.single.body), {'game_id': 'AbCdEfGhIj', 'opponent': 'A Player'});
    });
  });

  group('the players who could be invited', () {
    test('are read out of the page envelope, with the country they carry', () async {
      final repository = XiangqiNewGameRepository(
        client(
          <http.Request>[],
          (_) => (
            status: 200,
            body: {
              'items': [
                {
                  'id': 42,
                  'username': 'A Player',
                  'rating': 1500,
                  'country': {'code': 'ZZ', 'name': 'International'},
                  'profile_image': null,
                },
                {'id': 43, 'username': 'Another'},
                // A row with no id is not a player; a row that is not an object is not a row.
                {'username': 'Nameless'},
                'not a row',
              ],
              'has_next_page': true,
              'total_pages': 3,
            },
          ),
        ),
      );

      final players = await repository.onlineUsers(gameId: 'AbCdEfGhIj');

      expect(players, hasLength(2));
      expect(players.first.id, 42);
      expect(players.first.username, 'A Player');
      expect(players.first.rating, 1500);
      expect(players.first.countryCode, 'ZZ');
      expect(players.first.countryName, 'International');
      expect(players.last.rating, isNull);
    });

    test('are empty, and not a failure, for a body that is not a page', () async {
      final repository = XiangqiNewGameRepository(
        client(<http.Request>[], (_) => (status: 200, body: {'message': 'no'})),
      );

      expect(await repository.onlineUsers(gameId: 'AbCdEfGhIj'), isEmpty);
    });
  });
}
