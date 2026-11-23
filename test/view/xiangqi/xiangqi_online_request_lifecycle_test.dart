import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import 'xiangqi_online_game_screen_test.dart' as online;

final _provider = xiangqiOnlineGameControllerProvider(fx.xiangqiTestGameId);

class _Game(final fx.FakeXiangqiChannelFactory factory, final ProviderContainer container) {
  XiangqiOnlineGameController get controller => container.read(_provider.notifier);
  XiangqiOnlineGameState get state => container.read(_provider).requireValue;
  fx.FakeXiangqiChannel get channel => factory.channel;
}

Future<_Game> _loadGame(WidgetTester tester) async {
  final factory = await online.pumpGame(tester, token: fx.xiangqiTestToken(fx.xiangqiTestViewerId));
  await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
  return _Game(
    factory,
    ProviderScope.containerOf(tester.element(find.byType(XiangqiOnlineGameScreen))),
  );
}

Future<void> _resync(WidgetTester tester, _Game game) async {
  game.channel.autoAck = true;
  unawaited(game.controller.resync());
  await tester.pump();
  await online.receive(tester, game.factory, fx.xiangqiSnapshotFrame());
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('an old move ack timeout cannot disconnect a freshly resynchronised game', (
    tester,
  ) async {
    final game = await _loadGame(tester);
    game.channel.autoAck = false;
    final moving = game.controller.playMove(fx.xiangqiTestMoves.first);
    await tester.pump(const Duration(seconds: 2));
    await _resync(tester, game);
    expect(game.state.isConnected, isTrue);
    expect(game.controller.pendingMove, isFalse);

    await tester.pump(const Duration(seconds: 9));
    expect(await moving, isFalse);
    expect(game.state.error, isNull);
    expect(game.state.isConnected, isTrue);
    expect(game.state.moves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old move failure cannot clear a newer move confirmation timer', (tester) async {
    final game = await _loadGame(tester);
    game.channel.autoAck = false;
    final first = game.controller.playMove(fx.xiangqiTestMoves.first);
    await tester.pump(const Duration(seconds: 2));
    await _resync(tester, game);
    unawaited(game.controller.playMove(fx.xiangqiTestMoves[2]));
    await tester.pump();
    expect(game.controller.pendingMove, isTrue);

    await tester.pump(const Duration(seconds: 8));
    expect(await first, isFalse);
    expect(game.controller.pendingMove, isTrue);
    expect(game.state.error, isNull);
    expect(game.state.isConnected, isTrue);
    final before = game.channel.sent.length;
    await tester.pump(const Duration(seconds: 2));
    expect(game.controller.pendingMove, isFalse);
    expect(game.channel.sent.length, greaterThan(before));
    expect(game.state.isConnected, isFalse, reason: 'the newer move still needs resynchronising');
    await online.receive(tester, game.factory, fx.xiangqiSnapshotFrame());
    expect(game.state.isConnected, isTrue);
  });

  testWidgets('a move from a disposed build cannot fail the rebuilt controller', (tester) async {
    final game = await _loadGame(tester);
    game.channel.autoAck = false;
    final moving = game.controller.playMove(fx.xiangqiTestMoves.first);
    game.container.invalidate(_provider);
    await tester.pump();
    await tester.pump();
    await _resync(tester, game);

    await tester.pump(const Duration(seconds: 11));
    expect(await moving, isFalse);
    expect(game.state.error, isNull);
    expect(game.state.isConnected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a confirmed resignation survives its missing acknowledgement', (tester) async {
    final game = await _loadGame(tester);
    game.channel.autoAck = false;
    final resigning = game.controller.resign();
    await tester.pump();
    game.channel.autoAck = true;
    await online.receive(tester, game.factory, fx.xiangqiEndFrame());
    await online.receive(tester, game.factory, fx.xiangqiSnapshotFrame(ended: true));
    expect(game.state.isFinished, isTrue);

    await tester.pump(const Duration(seconds: 11));
    await resigning;
    expect(game.state.error, isNull);
    expect(game.state.isConnected, isTrue);
    expect(game.state.isFinished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a superseded resignation cannot fail a fresh live snapshot', (tester) async {
    final game = await _loadGame(tester);
    game.channel.autoAck = false;
    final resigning = game.controller.resign();
    await tester.pump(const Duration(seconds: 2));
    await _resync(tester, game);
    await tester.pump(const Duration(seconds: 9));
    await resigning;
    expect(game.state.error, isNull);
    expect(game.state.isConnected, isTrue);
    expect(game.state.isFinished, isFalse);
  });

  testWidgets('an unconfirmed resignation still reports its transport failure', (tester) async {
    final game = await _loadGame(tester);
    game.channel.autoAck = false;
    final resigning = game.controller.resign();
    await tester.pump(const Duration(seconds: 11));
    await resigning;
    expect(game.state.error, kXiangqiOnlineConnectionFailed);
    expect(game.state.isConnected, isFalse);
    expect(game.state.isFinished, isFalse);
  });

  testWidgets('a confirmed move remains successful when its acknowledgement is missing', (
    tester,
  ) async {
    final game = await _loadGame(tester);
    game.channel.autoAck = false;
    final moving = game.controller.playMove(fx.xiangqiTestMoves.first);
    await online.receive(tester, game.factory, fx.xiangqiMoveFrame(1));
    await tester.pump(const Duration(seconds: 11));
    expect(await moving, isTrue);
    expect(game.state.error, isNull);
    expect(game.state.moves, [fx.xiangqiTestMoves.first]);
    expect(game.state.isConnected, isTrue);
  });
}
