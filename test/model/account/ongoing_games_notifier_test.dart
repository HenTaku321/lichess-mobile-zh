// Tests for the merged ongoing-games list.
//
// This list is one of the places where the two backends meet, and the merge is where its rules
// live: both backends' games in one list, lichess first and each backend's own order kept, a row
// key namespaced so that two backends handing out the same id cannot collide, and a failure rule
// that keeps a backend's identity off the screen. None of that is a widget concern — the screen
// only renders the list it is handed — so it is tested here, against the provider itself.
//
// The lichess side comes off the HTTP mock like every other server-backed test. The xiangqi side is
// a plain [FutureProvider] with no network under it, so it is overridden directly — see AGENTS.md
// on when a direct override is the right thing.
//
// The xiangqi source is empty in this wave, so the games overridden in here are made-up ones: there
// is nothing real to fetch yet.

import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_open_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/http.dart';

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
}
