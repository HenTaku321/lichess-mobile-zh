// Tests for the screen a finished xiangqi.com game is gone through on.
//
// The screen is driven end to end over the socket the online game screen's own tests use: a fake
// channel under the socket client's provider, the redirect a finished game answers `g_v2.get` with,
// the snapshot behind it, and the one frame the analysis comes back in. Nothing here is a live host.
//
// The frames are the shapes the 2026-10-16 probe measured — see `xiangqi-com-re/docs/review.md` —
// with every value replaced. Not one game id, username, rating or move here is the capture's.

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_review_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The game the review is of, and one that is not the fixture's own.
const _gameId = 'RvWxYz9012';

/// The moves of the reviewed game, in xiangqi.com's rank-1 UCI.
///
/// The fixture's own opening, cut short at four plies: a review reads the same snapshot the live
/// screen does, so taking its moves is what keeps the two from drifting apart.
final _uciMoves = fx.xiangqiTestMoveUcis.take(4).toList();

/// The evaluations the server sends, one per **position** — so one more than there are moves — in
/// the **side to move's** point of view, which is the shape `game.review.success` uses.
///
/// The last one is a mate for red, which is what makes the final move a blunder for black: red's
/// score goes from level to mate, and black is the one who let it.
const _scores = <Map<String, Object?>>[
  {'cp': 30},
  {'cp': 20},
  {'cp': 40},
  {'cp': 10},
  {'mate': 1},
];

/// The `game.review.success` frame for [_uciMoves] and [_scores].
String reviewFrame() => fx.xiangqiEventFrame('game.review.success', {
  'progress': 100,
  'analysis': [
    for (var ply = 0; ply < _scores.length; ply++)
      {
        'ply': ply,
        'bm': ply < _uciMoves.length ? _uciMoves[ply] : '',
        'd': 16,
        's': _scores[ply],
        'pv': ply < _uciMoves.length ? _uciMoves[ply] : '',
      },
  ],
});

/// The snapshot of the reviewed game.
///
/// The fixture's own payload with the three fields a review needs and a live screen does not: the
/// id, the `archive` flag a finished game carries, and `initial_fen`. The last one is what the
/// moves are replayed from, and the server really does send it — measured on 2026-10-16 — because a
/// game need not start from the opening position.
Map<String, Object?> snapshotPayload() => {
  ...fx.xiangqiSnapshotPayload(plies: _uciMoves.length, ended: true),
  'id': _gameId,
  'archive': true,
  'initial_fen': XiangqiPosition.initial().toFen(),
};

/// Pumps the review screen over a fake socket, and hands the factory back.
Future<fx.FakeXiangqiChannelFactory> pumpReview(
  WidgetTester tester, {
  bool signedIn = true,
  SoundService? sound,
}) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final client = XiangqiSocketClient(
    channelFactory: factory,
    getToken: () async => fx.xiangqiTestToken(fx.xiangqiTestViewerId),
  );
  addTearDown(client.dispose);

  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        home: XiangqiReviewScreen(gameId: _gameId),
      ),
      overrides: {
        if (sound != null) soundServiceProvider: soundServiceProvider.overrideWithValue(sound),
        // A real client over a fake transport, and not `overrideWithValue`: the client holds a
        // heartbeat timer, and the provider's teardown is the only thing that cancels it before the
        // harness looks for pending ones.
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((Ref ref) {
          ref.onDispose(client.dispose);
          return client;
        }),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
          (ref) => fx.FakeXiangqiAuthStorage(
            signedIn ? fx.xiangqiTestSession(fx.xiangqiTestToken(fx.xiangqiTestViewerId)) : null,
          ),
        ),
      },
    ),
  );

  // Wait for the CONNECT frame, not merely for the channel object: the client attaches its stream
  // listener immediately before writing that frame, and this fake stream does not replay frames
  // pushed before there is a listener.
  await pumpUntil(
    tester,
    () => factory.channels.isNotEmpty && factory.channel.sentConnect,
    reason: 'the review screen is expected to open a socket',
  );
  return factory;
}

/// Walks the socket through the two requests a review makes, and draws what came back.
///
/// The redirect is the one thing about this that is not obvious: a finished game answers `g_v2.get`
/// with an ack naming another event, and the snapshot only comes after that event is sent. The
/// fixture's channel answers the redirect itself, so the test only has to push the two frames.
Future<void> loadReview(WidgetTester tester, fx.FakeXiangqiChannelFactory factory) async {
  final channel = factory.channel;
  channel.ackOverrides['g_v2.get'] = fx.xiangqiRedirectAck;
  channel.fromServer(fx.openFrame);
  channel.fromServer(fx.connectAckFrame);

  // The redirect is emitted only after the `g_v2.get` acknowledgement. Waiting for that second
  // request is a stronger synchronisation point than pumping a fixed number of frames.
  await pumpUntil(
    tester,
    () => channel.hasSentEvent('game.archived.get'),
    reason: 'the archived game is expected to be requested after the redirect',
  );

  // The snapshot, which arrives under the plain name however it was asked for — measured on
  // 2026-10-16, where `game.archived.get` came back as `game.get.success`.
  channel.fromServer(fx.xiangqiEventFrame('game.get.success', snapshotPayload()));

  // The analysis, which is only asked for once the snapshot has been read: the request is keyed by
  // the game's moves, so a review cannot be asked for before they are in hand.
  await pumpUntil(
    tester,
    () => channel.hasSentEvent('g_v2.review'),
    reason: 'the review is expected to be requested once the moves are in hand',
  );
  channel.fromServer(reviewFrame());
  await pumpUntil(
    tester,
    () => find.byType(XiangqiBoard).evaluate().isNotEmpty,
    reason: 'the answered review is expected to draw its board',
  );
}

/// The board the screen has drawn.
XiangqiBoard board(WidgetTester tester) => tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));

/// The bar button under [icon].
BottomBarButton barButton(WidgetTester tester, IconData icon) => tester.widget<BottomBarButton>(
  find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton)),
);

void main() {
  TestLichessBinding.ensureInitialized();

  setUp(() {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.FINE;
    final logs = Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'XiangqiReviewRepository' ||
          record.loggerName == 'XiangqiSocketClient') {
        // CI is the execution environment; retain the failing protocol stage in its logs.
        debugPrint('${record.loggerName}: ${record.message} ${record.error ?? ''}');
      }
    });
    addTearDown(() async {
      await logs.cancel();
      Logger.root.level = previousLevel;
    });
  });

  group('XiangqiReviewScreen', () {
    testWidgets('opens on the last position, with the game marked up', (tester) async {
      final factory = await pumpReview(tester);
      await loadReview(tester, factory);

      expect(find.byType(XiangqiBoard), findsOneWidget);
      // The board is the position after the last move, which is where a review opens.
      final moves = IList([for (final uci in _uciMoves) xiangqiMoveFromComUci(uci)!]);
      var position = XiangqiPosition.initial();
      for (final move in moves) {
        position = rules.play(position, move);
      }
      expect(board(tester).position.toFen(), position.toFen());

      // Both players, by name.
      expect(find.text(fx.xiangqiTestRedName), findsOneWidget);
      expect(find.text(fx.xiangqiTestBlackName), findsOneWidget);
    });

    testWidgets('says what the engine made of the move that led to the position', (tester) async {
      final factory = await pumpReview(tester);
      await loadReview(tester, factory);

      // The last move is black's, and it hands red a mate in one: the score goes from level, from
      // black's point of view, to a mate for red.
      expect(find.text('Blunder'), findsOneWidget);
      expect(find.text('Accuracy'), findsNothing, reason: 'the label is part of the player rows');

      // Walking back one move puts a move of black's that gave nothing up on the board instead.
      await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
      await tester.pump();
      expect(find.text('Blunder'), findsNothing);
    });

    testWidgets("shows each side's accuracy once it has moves to average", (tester) async {
      final factory = await pumpReview(tester);
      await loadReview(tester, factory);

      // Two moves each, so both rows carry a number. The exact values are the model's own business
      // — its tests pin the curve — and what is pinned here is that the row draws one at all.
      expect(find.textContaining('Accuracy '), findsNWidgets(2));
    });

    testWidgets('offers no way to play the game', (tester) async {
      final factory = await pumpReview(tester);
      await loadReview(tester, factory);

      // A review is read, not played: the board takes no tap and no drag, and there is no move to
      // make on it.
      expect(board(tester).onTapSquare, isNull);
      expect(board(tester).onDragMove, isNull);
      expect(board(tester).moves, isEmpty);
    });

    testWidgets('steps through the game with the bar buttons, and stops at the ends', (
      tester,
    ) async {
      final factory = await pumpReview(tester);
      await loadReview(tester, factory);

      // Opens on the last position, so the way forward is already spent.
      expect(barButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.chevron_back).onTap, isNotNull);

      for (var i = 0; i < _uciMoves.length; i++) {
        await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
        await tester.pump();
      }

      // Back at the start: nothing before it.
      expect(barButton(tester, CupertinoIcons.chevron_back).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.chevron_forward).onTap, isNotNull);
      expect(board(tester).position.toFen(), XiangqiPosition.initial().toFen());
    });

    testWidgets('a device with no session is not asked for one', (tester) async {
      // **A review needs no account.** The socket opens a guest session of its own when there is
      // none, and a guest was measured being handed a whole archived game's analysis — so the screen
      // behind this one draws the game rather than a sign-in prompt. The socket is stubbed here, so
      // what this pins is the screen's own half: no session is not a reason to refuse.
      final factory = await pumpReview(tester, signedIn: false);
      await loadReview(tester, factory);

      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(find.text('Sign in to xiangqi.com'), findsNothing);
    });

    testWidgets('a review the server does not answer offers the way to ask again', (tester) async {
      final factory = await pumpReview(tester);
      final channel = factory.channel;
      channel.fromServer(fx.openFrame);
      channel.fromServer(fx.connectAckFrame);
      await pumpUntil(
        tester,
        () => channel.hasSentEvent('g_v2.get'),
        reason: 'the review is expected to ask for its game before the server hangs up',
      );

      // The ack is not a redirect, so the screen waits for a snapshot that never comes. The socket
      // is closed instead, which is the failure the screen has to survive.
      channel.closeFromServer();
      await pumpUntil(
        tester,
        () => find.text('The review could not be loaded.').evaluate().isNotEmpty,
        reason: 'closing the socket is expected to surface the review error',
      );

      expect(find.text('The review could not be loaded.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
