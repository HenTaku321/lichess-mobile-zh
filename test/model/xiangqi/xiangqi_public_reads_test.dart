// Tests for the xiangqi.com reads that need no account.
//
// **The regression this wave fixed.** Every repository here used to refuse to ask unless a
// xiangqi.com session was held, and a desktop that has never signed in holds none — so the courses,
// the master-games database, the tournaments and the leaderboards all showed an error instead of
// what they had asked for. The server was never the problem: measured on 2026-10-16, every endpoint
// below answered `200` to a request carrying no `Authorization` header at all.
//
// So what is pinned here is the shape of the gate rather than the shape of the payloads — the
// readers have their own tests for those. Each case asks a provider with **no session at all** and
// asserts it came back with data, which is exactly the state a fresh desktop is in.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/database/xiangqi_master_game_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_user_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/tournament/xiangqi_tournament_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart'
    show XiangqiAuthStorage, xiangqiAuthStorageProvider;

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';

/// The bodies the endpoints answer with, by path.
///
/// Thin on purpose: each reader has its own tests for what a payload means, and what this file is
/// about is whether the request is made at all. Every body here carries just enough for the reader
/// to come back with something rather than nothing.
const _bodies = <String, String>{
  '/api/lessons/levels':
      '{"topics":[{"encrypted_id":"AbCdEf","topic_title":"A topic",' +
      '"level_id":1,"level_title":"NewBie","total_lessons":7,"complete_lessons":0}]}',
  '/api/master-games/players':
      '{"items":[{"id":1,"name":"A Player","title":"Xiangqi Master","game_count":478}],' +
      '"total_pages":3,"next_page_num":2}',
  '/api/tournament/list': '{"active":[{"id":"AbCdEf","name":"A Cup","state":10}],"previous":[]}',
  '/api/leaders/v2/list':
      '{"meta":{"total_pages":1,"total_players":2,"current_page":1},'
      '"data":[{"rating":1500,"user":{"id":1,"username":"a-player"}}]}',
  '/api/users/account/a-player': '{"id":1,"username":"a-player","rapid_rating":1200}',
  '/api/users/multiplayer_stats/a-player':
      '{"wins":12,"losses":8,"draws":3,"win_rate":52.17,"total_games":23,'
      '"current_rating":1234,"highest_rating":1300}',
  '/api/v2/games/active':
      '[{"id":"AbCdEf1234","is_rated":true,"is_timed":true,"game_timer":20,"increment":5,'
      '"move_timer":5,"moves_count":4,'
      '"rplayer":{"id":1,"username":"red-one","seconds":600},'
      '"bplayer":{"id":2,"username":"black-two","seconds":600}}]',
};

/// A container with **no xiangqi.com session**, and a client that answers [_bodies].
Future<ProviderContainer> _containerWithNoSession() async {
  final asked = <String>[];
  final container = await makeContainer(
    overrides: {
      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
        const _NoSessionStorage(),
      ),
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
        (ref) => FakeHttpClientFactory(
          () => MockClient((request) async {
            final body = _bodies[request.url.path];
            asked.add(request.url.path);
            if (body == null) return http.Response('', 404);
            return http.Response.bytes(
              body.codeUnits,
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ),
      ),
    },
  );
  addTearDown(container.dispose);
  return container;
}

/// Reads [provider]'s first value, keeping it alive for the rest of the test.
///
/// A bare `container.read(provider.future)` does not hold an `autoDispose` provider open: the
/// temporary subscription is closed as soon as the read returns, and a provider disposed while its
/// request is still in flight completes with a disposal error instead of the answer.
Future<T> _read<T>(ProviderContainer container, FutureProvider<T> provider) {
  final subscription = container.listen(provider, (_, _) {});
  addTearDown(subscription.close);
  return container.read(provider.future);
}

void main() {
  group('a device with no xiangqi.com session', () {
    test('can read the courses', () async {
      final container = await _containerWithNoSession();
      final topics = await _read(container, xiangqiTopicsProvider('zh_Hans'));
      expect(topics.single.title, 'A topic');
    });

    test('can read the master-games database', () async {
      final container = await _containerWithNoSession();
      final players = await _read(
        container,
        xiangqiMasterPlayersProvider((search: null, page: 1, locale: 'zh_Hans')),
      );
      expect(players.items.single.name, 'A Player');
    });

    test('can read the tournaments', () async {
      final container = await _containerWithNoSession();
      final tournaments = await _read(container, xiangqiTournamentsProvider);
      expect(tournaments.active.single.name, 'A Cup');
    });

    test('can read a leaderboard', () async {
      final container = await _containerWithNoSession();
      final board = await _read(
        container,
        xiangqiLeaderboardProvider((XiangqiRatingType.rapid, null, 1)),
      );
      expect(board.entries.single.player.name, 'a-player');
    });

    test('can read an account', () async {
      final container = await _containerWithNoSession();
      final account = await _read(container, xiangqiUserProvider('a-player'));
      expect(account.rapidRating, 1200);
    });

    test('can read a record', () async {
      final container = await _containerWithNoSession();
      final stats = await _read(
        container,
        xiangqiGameStatsProvider(('a-player', XiangqiRatingType.rapid)),
      );
      expect(stats.wins, 12);
    });

    test('can read the games being played', () async {
      final container = await _containerWithNoSession();
      final games = await _read(container, xiangqiLiveGamesProvider);
      expect(games.single.red.name, 'red-one');
    });
  });
}

/// A storage that never has a session, and never gains one.
///
/// `const` and immutable: the point of this file is the state a fresh desktop is in, and a fake that
/// could be written to would be a fake that could stop being that state.
class const _NoSessionStorage() implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => null;

  @override
  Future<void> write(XiangqiSession value) async {}

  @override
  Future<void> delete() async {}
}
