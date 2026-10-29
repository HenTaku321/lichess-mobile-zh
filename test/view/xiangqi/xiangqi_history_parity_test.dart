import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_online_game_screen_test.dart' as online;
import 'xiangqi_over_the_board_screen_test.dart' as otb;
import 'xiangqi_review_screen_test.dart' as review;

BottomBarButton historyButton(WidgetTester tester, IconData icon) => tester.widget<BottomBarButton>(
  find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton)),
);

/// Exercise the actual gesture arena, including Tooltip's competing long-press recognizer.
Future<void> holdHistoryButton(WidgetTester tester, IconData icon) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byIcon(icon)));
  await tester.pump(const Duration(milliseconds: 600));
  for (final delay in const [200, 180, 100, 40, 60, 60]) {
    await tester.pump(Duration(milliseconds: delay));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  testWidgets('online history holds reach both ends without sending a move', (tester) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestSpectatorId),
    );
    await online.playTheGame(tester, factory);
    final lastPosition = online.board(tester).position;

    await holdHistoryButton(tester, CupertinoIcons.chevron_back);
    expect(online.board(tester).position.toFen(), XiangqiPosition.initial().toFen());
    expect(historyButton(tester, CupertinoIcons.chevron_back).onTap, isNull);

    await holdHistoryButton(tester, CupertinoIcons.chevron_forward);
    expect(online.board(tester).position, lastPosition);
    expect(historyButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
    expect(factory.channel.hasSentEvent('g_v2.move'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('online return-to-live button blinks when the player has the move', (tester) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 4));
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pump();

    expect(historyButton(tester, CupertinoIcons.chevron_forward).blink, isTrue);
    expect(historyButton(tester, CupertinoIcons.chevron_back).showTooltip, isFalse);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_forward));
    await tester.pump();
    expect(historyButton(tester, CupertinoIcons.chevron_forward).blink, isFalse);
    expect(factory.channel.hasSentEvent('g_v2.move'), isFalse);
  });

  testWidgets('OTB history holds browse without taking any moves back', (tester) async {
    await otb.pumpOtbScreen(tester);
    for (final square in ['h2', 'e2', 'h9', 'g7', 'h0', 'g2', 'b9', 'c7']) {
      await otb.tapSquare(tester, square);
    }
    final afterMoves = fx.xiangqiTestPositions[4];

    await holdHistoryButton(tester, CupertinoIcons.chevron_back);
    expect(find.text('炮二平五'), findsOneWidget);
    expect(historyButton(tester, CupertinoIcons.chevron_back).onTap, isNull);

    await holdHistoryButton(tester, CupertinoIcons.chevron_forward);
    expect(historyButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
    final game = otb.containerOf(tester).read(xiangqiGameControllerProvider);
    expect(game.moves, hasLength(4));
    expect(game.position, afterMoves);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analysis history holds use the latest cursor and preserve the line', (tester) async {
    await analysis.pumpAnalysisScreen(tester, engineEvaluation: false);
    for (final square in ['h2', 'e2', 'h9', 'g7', 'h0', 'g2', 'b9', 'c7']) {
      await analysis.tapSquare(tester, square);
    }
    final lastPosition = analysis.board(tester).position;

    await holdHistoryButton(tester, CupertinoIcons.chevron_back);
    expect(analysis.board(tester).position.toFen(), XiangqiPosition.initial().toFen());
    expect(historyButton(tester, CupertinoIcons.chevron_back).onTap, isNull);

    await holdHistoryButton(tester, CupertinoIcons.chevron_forward);
    expect(analysis.board(tester).position, lastPosition);
    expect(historyButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review history holds stop at the ends rather than showing a tooltip', (
    tester,
  ) async {
    final factory = await review.pumpReview(tester);
    await review.loadReview(tester, factory);
    final lastPosition = review.board(tester).position;

    await holdHistoryButton(tester, CupertinoIcons.chevron_back);
    expect(review.board(tester).position.toFen(), XiangqiPosition.initial().toFen());
    expect(historyButton(tester, CupertinoIcons.chevron_back).onTap, isNull);

    await holdHistoryButton(tester, CupertinoIcons.chevron_forward);
    expect(review.board(tester).position, lastPosition);
    expect(historyButton(tester, CupertinoIcons.chevron_forward).onTap, isNull);
    expect(tester.takeException(), isNull);
  });
}
