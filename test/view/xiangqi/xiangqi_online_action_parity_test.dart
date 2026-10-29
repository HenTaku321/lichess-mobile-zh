import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import 'xiangqi_online_game_screen_test.dart' as online;

List<BottomBarButton> actions(WidgetTester tester) => tester
    .widgetList<BottomBarButton>(
      find.descendant(of: find.byType(BottomBar), matching: find.byType(BottomBarButton)),
    )
    .toList();

void main() {
  TestLichessBinding.ensureInitialized();

  for (final spectator in [false, true]) {
    testWidgets('online actions use chess ordering, spectator: $spectator', (tester) async {
      final factory = await online.pumpGame(
        tester,
        token: fx.xiangqiTestToken(spectator ? fx.xiangqiTestSpectatorId : fx.xiangqiTestViewerId),
        failOnOverflow: true,
      );
      await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 4));

      final buttons = actions(tester);
      expect(buttons.first.icon, Icons.menu);
      expect(buttons[buttons.length - 2].icon, CupertinoIcons.chevron_back);
      expect(buttons.last.icon, CupertinoIcons.chevron_forward);
      expect(buttons.map((button) => button.icon), isNot(contains(CupertinoIcons.xmark)));
      expect(
        buttons.map((button) => button.icon),
        isNot(contains(CupertinoIcons.arrow_2_squarepath)),
      );
      expect(buttons, hasLength(spectator ? 4 : 5));
    });
  }

  testWidgets('flipping through the shared menu preserves the selected history', (tester) async {
    final factory = await online.pumpGame(
      tester,
      token: fx.xiangqiTestToken(fx.xiangqiTestViewerId),
      failOnOverflow: true,
    );
    await online.receive(tester, factory, fx.xiangqiSnapshotFrame(plies: 4));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(XiangqiOnlineGameScreen)),
    );
    final provider = xiangqiOnlineGameControllerProvider(fx.xiangqiTestGameId);
    container.read(provider.notifier).goTo(2);
    await tester.pump();
    final before = online.board(tester).position;
    final orientation = online.board(tester).orientation;

    await tester.tap(online.barButton(Icons.menu));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Flip board'), findsOneWidget);
    await tester.tap(find.text('Flip board'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(online.board(tester).orientation, orientation.opposite);
    expect(online.board(tester).position, before);
    expect(container.read(provider).requireValue.viewCursor, 2);
    expect(container.read(provider).requireValue.moves, hasLength(4));
  });
}
