import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/review/xiangqi_review_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_review_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../test_helpers.dart';
import 'xiangqi_review_screen_test.dart' as review;

const _gameId = 'RvWxYz9012';
const _scores = <Map<String, Object?>>[
  {'cp': 30},
  {'cp': 20},
  {'cp': 40},
  {'cp': 10},
  {'mate': 1},
];

/// Real repository and screen over the protocol fixture; the initial position is not assumed.
Future<ProviderContainer> _loadReview(
  WidgetTester tester, {
  List<String> moves = const ['h3e3', 'h10g8', 'h1g3', 'b10c8'],
  List<Map<String, Object?>> scores = _scores,
  String initialFen = kXiangqiInitialFen,
}) async {
  final factory = await review.pumpReview(tester);
  final channel = factory.channel;
  channel.ackOverrides['g_v2.get'] = fx.xiangqiRedirectAck;
  channel.fromServer(fx.openFrame);
  channel.fromServer(fx.connectAckFrame);
  await pumpUntil(tester, () => channel.hasSentEvent('game.archived.get'));

  var finalPosition = XiangqiPosition.fromFen(initialFen);
  for (final uci in moves) {
    finalPosition = rules.play(finalPosition, xiangqiMoveFromComUci(uci)!);
  }
  channel.fromServer(
    fx.xiangqiEventFrame('game.get.success', {
      ...fx.xiangqiSnapshotPayload(ended: true),
      'id': _gameId,
      'archive': true,
      'initial_fen': initialFen,
      'fen': finalPosition.toFen(),
      'move_history': [for (final uci in moves) '$uci 600/120 600/120 1'],
    }),
  );
  await pumpUntil(tester, () => channel.hasSentEvent('g_v2.review'));
  channel.fromServer(
    fx.xiangqiEventFrame('game.review.success', {
      'progress': 100,
      'analysis': [
        for (var ply = 0; ply < scores.length; ply++)
          {
            'ply': ply,
            'bm': ply < moves.length ? moves[ply] : '',
            'd': 16,
            's': scores[ply],
            'pv': ply < moves.length ? moves[ply] : '',
          },
      ],
    }),
  );
  await pumpUntil(
    tester,
    () =>
        find.byType(XiangqiBoard).evaluate().isNotEmpty ||
        find.text('The review could not be loaded.').evaluate().isNotEmpty ||
        find.byType(ErrorWidget).evaluate().isNotEmpty,
  );
  return ProviderScope.containerOf(tester.element(find.byType(XiangqiReviewScreen)));
}

XiangqiEvalGauge _gauge(WidgetTester tester) =>
    tester.widget<XiangqiEvalGauge>(find.byType(XiangqiEvalGauge));

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('review gauge evaluates the displayed position, including the last one', (
    tester,
  ) async {
    await _loadReview(tester);
    expect(_gauge(tester).evaluation?.mate, 1);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pump();
    expect(_gauge(tester).evaluation?.cp, -10);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pump();
    expect(_gauge(tester).evaluation?.cp, 40);
  });

  testWidgets('a zero-move archived review shows its single evaluated position', (tester) async {
    await _loadReview(
      tester,
      moves: const [],
      scores: const [
        {'cp': 42},
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(_gauge(tester).evaluation?.cp, 42);
    expect(find.textContaining('Accuracy '), findsNothing);
  });

  testWidgets('an incomplete review is a retryable repository failure, not a widget crash', (
    tester,
  ) async {
    final container = await _loadReview(tester, scores: _scores.take(4).toList());
    expect(tester.takeException(), isNull);
    expect(container.read(xiangqiReviewProvider(_gameId)).hasError, isTrue);
    expect(find.text('The review could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a malformed review score is refused instead of read as a neutral evaluation', (
    tester,
  ) async {
    final container = await _loadReview(
      tester,
      scores: [
        _scores[0],
        const {'cp': 'not-a-score'},
        ..._scores.skip(2),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(container.read(xiangqiReviewProvider(_gameId)).hasError, isTrue);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a black-first review attributes moves and evaluation signs to black', (
    tester,
  ) async {
    final container = await _loadReview(
      tester,
      initialFen: kXiangqiInitialFen.replaceFirst(' w ', ' b '),
      moves: const ['h10g8'],
      scores: const [
        {'cp': 1200},
        {'cp': 1200},
      ],
    );
    final data = container.read(xiangqiReviewProvider(_gameId)).requireValue;
    expect(data.reviews.single.side, XiangqiSide.black);
    expect(data.accuracyOf(XiangqiSide.red), isNull);
    expect(data.accuracyOf(XiangqiSide.black), isNotNull);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pump();
    expect(_gauge(tester).evaluation?.cp, -1200);
  });

  testWidgets('review flip rotates the board, gauge and both player rows together', (tester) async {
    await _loadReview(tester);
    expect(find.byIcon(CupertinoIcons.arrow_2_squarepath), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.arrow_2_squarepath));
    await tester.pump();
    expect(review.board(tester).orientation, XiangqiSide.black);
    expect(_gauge(tester).orientation, XiangqiSide.black);
    expect(
      tester.widgetList<XiangqiPlayerRow>(find.byType(XiangqiPlayerRow)).map((row) => row.side),
      [XiangqiSide.red, XiangqiSide.black],
    );
  });
}
