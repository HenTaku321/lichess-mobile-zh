// Tests for the merged ongoing-games list.
//
// This list is one of the places where the two backends meet, and the merge is where its rules
// live: both backends' games in one list, lichess first and each backend's own order kept, a row
// key namespaced so that two backends handing out the same id cannot collide, and a failure rule
// that keeps a backend's identity off the screen. None of that is a widget concern — the screen
// only renders the list it is handed — so it is tested here, against the provider itself.
//
// The lichess side comes off the HTTP mock like every other server-backed test. The xiangqi side is
// overridden directly in the merge cases — see AGENTS.md on when a direct override is the right
// thing — because what is under test there is the merge and not the transport; the transport has
// its own group at the bottom of this file, where the xiangqi source is exercised for real against
// the HTTP mock.

import 'dart:async';
import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_open_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';
import '../auth/fake_auth_storage.dart';

/// The two lichess games the merge is given, in the order the endpoint lists them.
const lichessFirstFullId = 'aaaaaaaa0001';
const lichessSecondFullId = 'aaaaaaaa0002';

/// The two xiangqi games the merge is given, in the order the source lists them.
const xiangqiFirstId = 'xq-first';
const xiangqiSecondId = 'xq-second';

/// A `/api/account/playing` body carrying one game per entry of [fullIds], in that order.
///
/// The shape is the one `mockAccountOngoingGamesResponse` has — the shape this endpoint really
/// answers with — with the ids varying so that a test can tell the rows apart and so pin the order
/// the merge leaves them in.
String lichessPlayingResponse(List<String> fullIds) =>
    '''
{
  "nowPlaying": [
${fullIds.map(lichessPlayingGameJson).join(',\n')}
  ]
}
''';

/// One `nowPlaying` entry, with [fullId] as its own id.
String lichessPlayingGameJson(String fullId) =>
    '''
    {
      "gameId": "${fullId.substring(0, 8)}",
      "fullId": "$fullId",
      "color": "black",
      "fen": "r1bqkbnr/pppp2pp/2n1pp2/8/8/3PP3/PPPB1PPP/RN1QKBNR w KQkq - 2 4",
      "hasMoved": true,
      "isMyTurn": false,
      "lastMove": "b8c6",
      "opponent": {"id": "philippe", "rating": 1790, "username": "Philippe"},
      "perf": "correspondence",
      "rated": false,
      "secondsLeft": 1209600,
      "source": "friend",
      "speed": "correspondence",
      "variant": {"key": "standard", "name": "Standard"}
    }''';

/// One xiangqi game, with [id] as its own id.
///
/// The shape is the one the screen test builds its xiangqi row from; only the id varies, so that
/// two rows can be told apart and the order the merge leaves them in can be pinned.
XiangqiOpenGame xiangqiGame(String id) => XiangqiOpenGame(
  id: id,
  isRated: true,
  mySide: XiangqiSide.red,
  gameTimeSeconds: 300,
  incrementSeconds: 3,
  opponent: LightUser(id: UserId('zq-$id'), name: 'XiangqiOpponent'),
  opponentRating: 1500,
  isMyTurn: true,
  movesCount: 0,
  fen: kXiangqiInitialFen,
  redSecondsLeft: 300,
  blackSecondsLeft: 300,
);

/// A container whose lichess side is [playing] and whose xiangqi side is [xiangqi].
///
/// The lichess side is driven through the HTTP mock rather than overridden, because the notifier
/// under it is the thing that turns a response into rows; the xiangqi side has no transport at all
/// in this wave, so there is nothing under it to exercise.
Future<ProviderContainer> makeMergeContainer({
  required MockClient playing,
  required FutureOr<IList<XiangqiOpenGame>> Function(Ref ref) xiangqi,
}) {
  return makeContainer(
    authUser: fakeAuthUser,
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
        (ref) => FakeHttpClientFactory(() => playing),
      ),
      xiangqiOngoingGamesSourceProvider: xiangqiOngoingGamesSourceProvider.overrideWith(
        (ref) => xiangqi(ref),
      ),
    },
  );
}

/// A [XiangqiAuthStorage] that keeps the session in memory.
///
/// [xiangqiAuthStorageProvider] is a plain provider — no network, no platform channel — so
/// overriding it with this is what AGENTS.md allows, and it keeps secure storage out of the test.
class FakeXiangqiAuthStorage([var XiangqiSession? session]) implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession value) async => session = value;

  @override
  Future<void> delete() async => session = null;
}

/// The session the transport cases run with.
const xiangqiSession = XiangqiSession(
  userId: '100001',
  name: 'Tester',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  isGuest: false,
);

/// The requests [requests] holds that were addressed to xiangqi.com.
///
/// A container's startup makes requests of its own — the connectivity check and the lichess favicon
/// are both HEADs off the same mock — so the assertions below look at the host and not at the whole
/// recording.
List<http.Request> xiangqiRequests(List<http.Request> requests) =>
    requests.where((r) => r.url.host == 'api.xiangqi.com').toList();

/// One `GET /api/v2/games/my-games` entry, in the shape the endpoint was measured to answer with.
///
/// The body is a bare array and the entry is the sibling `v2/games/active` projection, which is the
/// only list projection of a game that has been measured live: `id`, the two seats with `id`,
/// `username`, `rating` and `seconds`, `game_timer` in minutes, `increment` in seconds, `is_rated`,
/// `is_timed`, `moves_count`, `move_timer`, `timestamp` and `last_move_time`.
Map<String, Object?> xiangqiListEntry({
  String id = 'By-TxD0QKV',
  Object redId = '100001',
  Object blackId = 157007,
}) => {
  'id': id,
  'is_rated': true,
  'is_timed': true,
  'game_timer': 15,
  'increment': 5,
  'move_timer': 2,
  'moves_count': 54,
  'timestamp': '2026-10-15T13:04:43.604016',
  'last_move_time': '2026-10-15T13:18:44.179384',
  'rplayer': {'id': redId, 'username': 'Tester', 'rating': null, 'seconds': 577},
  'bplayer': {'id': blackId, 'username': 'jackson65', 'rating': 2831, 'seconds': 660},
};

/// A container with the xiangqi source exercised for real: the HTTP mock under it, and the session
/// store in memory.
///
/// The auth controller answers `null` at once and adopts the stored session in a microtask, so the
/// restore has to have landed before the source is read — read too early and the source sees "no
/// session" and answers the empty list without asking anything.
Future<ProviderContainer> makeXiangqiSourceContainer({
  required MockClient client,
  required XiangqiSession? session,
  bool online = true,
}) async {
  final container = await makeContainer(
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
        (ref) => FakeHttpClientFactory(() => client),
      ),
      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
        (ref) => FakeXiangqiAuthStorage(session),
      ),
      if (!online) isDeviceOnlineProvider: isDeviceOnlineProvider.overrideWithValue(false),
    },
  );
  // Something has to hold the auth controller open while it reads storage: it answers `null` at
  // once and adopts the stored session in a microtask, and a plain `read` lets it be disposed before
  // it ever gets there — which the source would then see as "no session" and answer without asking.
  container.listen(xiangqiAuthControllerProvider, (_, _) {});
  await container.pump();
  return container;
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('ongoingGamesProvider merge', () {
    test('rows come from both backends, lichess first, each in its own backend order', () async {
      final container = await makeMergeContainer(
        playing: MockClient(
          (request) =>
              mockResponse(lichessPlayingResponse([lichessFirstFullId, lichessSecondFullId]), 200),
        ),
        xiangqi: (ref) => IListConst([xiangqiGame(xiangqiFirstId), xiangqiGame(xiangqiSecondId)]),
      );

      final entries = await container.read(ongoingGamesProvider.future);

      // One list, both backends, and the order is the merge's own: the lichess rows first, then the
      // xiangqi ones, each backend's own order kept rather than re-sorted into one another.
      expect(entries.map((e) => e.rowKey), [
        'lichess:$lichessFirstFullId',
        'lichess:$lichessSecondFullId',
        'xiangqi:$xiangqiFirstId',
        'xiangqi:$xiangqiSecondId',
      ]);
    });

    test('a row key is namespaced, so two backends handing out the same id cannot collide', () async {
      // The two backends hand out the same id here. They are separate id namespaces, so this is not
      // a contrived input: it is the case the prefix exists for.
      const sharedId = 'cccccccc0001';

      final container = await makeMergeContainer(
        playing: MockClient((request) => mockResponse(lichessPlayingResponse([sharedId]), 200)),
        xiangqi: (ref) => IListConst([xiangqiGame(sharedId)]),
      );

      final entries = await container.read(ongoingGamesProvider.future);

      expect(entries.map((e) => e.rowKey), ['lichess:$sharedId', 'xiangqi:$sharedId']);
      expect(entries.map((e) => e.rowKey).toSet(), hasLength(2));
    });

    test('the lichess source failing loses its own rows and not the list', () async {
      // lichess is down; the xiangqi source answers.
      final container = await makeMergeContainer(
        playing: MockClient((request) => mockResponse('', 500)),
        xiangqi: (ref) => IListConst([xiangqiGame(xiangqiFirstId), xiangqiGame(xiangqiSecondId)]),
      );

      final entries = await container.read(ongoingGamesProvider.future);

      // Still a data state, with the other backend's rows intact: an error here would tell the user
      // which backend is down, which is exactly what must not surface.
      expect(entries.map((e) => e.rowKey), ['xiangqi:$xiangqiFirstId', 'xiangqi:$xiangqiSecondId']);
    });

    test('the xiangqi source failing loses only its own rows', () async {
      // The xiangqi source is down; lichess answers.
      final container = await makeMergeContainer(
        playing: MockClient(
          (request) =>
              mockResponse(lichessPlayingResponse([lichessFirstFullId, lichessSecondFullId]), 200),
        ),
        xiangqi: (ref) => Future.error(StateError('xiangqi is down')),
      );

      final entries = await container.read(ongoingGamesProvider.future);

      expect(entries.map((e) => e.rowKey), [
        'lichess:$lichessFirstFullId',
        'lichess:$lichessSecondFullId',
      ]);
    });

    test('only both sources failing is a failure of the list', () async {
      final container = await makeMergeContainer(
        playing: MockClient((request) => mockResponse('', 500)),
        xiangqi: (ref) => Future.error(StateError('xiangqi is down')),
      );

      // Which of the two errors surfaces is whichever future settled first: `build` throws
      // `failures.first`, and `failures` is appended in completion order rather than in source
      // order. So what can be asserted is that the list is an error and that it is one of the two,
      // not which one. (The contacts list throws the lichess failure deterministically instead; the
      // two merges differ here.)
      await expectLater(
        container.read(ongoingGamesProvider.future),
        throwsA(anyOf(isA<ServerException>(), isA<StateError>())),
      );
    });
  });

  group('the xiangqi source', () {
    test('asks nothing at all when there is no xiangqi.com session', () async {
      final requests = <http.Request>[];
      final container = await makeXiangqiSourceContainer(
        session: null,
        client: MockClient((request) {
          requests.add(request);
          return mockResponse('[]', 200);
        }),
      );

      expect(await container.read(xiangqiOngoingGamesSourceProvider.future), isEmpty);
      // Not "answered with nothing" — never asked. A device with no session has no games on
      // xiangqi.com, and there is nothing to find out.
      expect(xiangqiRequests(requests), isEmpty);
    });

    test('fetches the lobby list and reads the array it answers with', () async {
      final requests = <http.Request>[];
      final container = await makeXiangqiSourceContainer(
        session: xiangqiSession,
        client: MockClient((request) {
          requests.add(request);
          return mockResponse(jsonEncode([xiangqiListEntry()]), 200);
        }),
      );

      final games = await container.read(xiangqiOngoingGamesSourceProvider.future);

      final asked = xiangqiRequests(requests);
      expect(asked.single.method, 'GET');
      expect(asked.single.url.toString(), 'https://api.xiangqi.com/api/v2/games/my-games');
      expect(asked.single.headers['Authorization'], 'Bearer access-1');
      expect(asked.single.headers['User-Agent'], kXiangqiUserAgent);
      expect(games.single.id, 'By-TxD0QKV');
      expect(games.single.mySide, XiangqiSide.red);
      expect(games.single.gameTimeSeconds, 900);
      expect(games.single.opponent?.name, 'jackson65');
      expect(games.single.opponentRating, 2831);
      expect(games.single.redSecondsLeft, 577);
      expect(games.single.blackSecondsLeft, 660);
    });

    test('a refusal by the server is a failure of this source', () async {
      final container = await makeXiangqiSourceContainer(
        session: xiangqiSession,
        client: MockClient((request) => mockResponse('', 500)),
      );

      await expectLater(
        container.read(xiangqiOngoingGamesSourceProvider.future),
        throwsA(isA<ServerException>()),
      );
    });

    test('an offline device is settled at once rather than asked', () async {
      final requests = <http.Request>[];
      final container = await makeXiangqiSourceContainer(
        session: xiangqiSession,
        online: false,
        client: MockClient((request) {
          requests.add(request);
          return mockResponse('[]', 200);
        }),
      );

      // A [StateError] and not an [Exception]: `lichessProviderRetry` never retries an [Error], so
      // being offline is settled once instead of six times over with a back-off in between.
      await expectLater(
        container.read(xiangqiOngoingGamesSourceProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(xiangqiRequests(requests), isEmpty);
    });
  });
}
