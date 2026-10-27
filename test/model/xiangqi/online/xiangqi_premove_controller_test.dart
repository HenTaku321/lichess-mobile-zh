import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

import 'xiangqi_online_game_controller_test.dart' show makeHarness;
import 'xiangqi_online_game_fixture.dart' as fx;

void main() {
  XiangqiSquare square(String value) => XiangqiSquare.parse(value)!;
  XiangqiMove move(String value) => XiangqiMove.parseIccs(value)!;

  test('dragging an already selected piece submits that move once, without two taps', () async {
    final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame());
    game.controller.tapSquare(square('h2'));
    game.controller.movePiece(square('h2'), square('e2'));
    await pumpEventQueue();
    expect(
      game.channel.sent.whereType<String>().where((frame) => frame.contains('"g_v2.move"')),
      hasLength(1),
    );
    expect(game.state.moves, isEmpty, reason: 'the ack does not confirm a position');
    expect(game.state.selected, isNull);
  });

  test('a premove waits for the opponent incremental confirmation and is sent only once', () async {
    final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame(plies: 1));
    game.controller.movePiece(square('a3'), square('a4'), premoveEnabled: true);
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId))?.move, move('a3a4'));
    expect(
      game.channel.sent.whereType<String>().where((frame) => frame.contains('"g_v2.move"')),
      isEmpty,
    );
    await game.send(fx.xiangqiMoveFrame(2));
    expect(
      game.channel.sent.whereType<String>().where((frame) => frame.contains('"g_v2.move"')),
      hasLength(1),
    );
    expect(game.state.moves, hasLength(2), reason: 'the premove still needs its own confirmation');
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNull);
    await game.send(fx.xiangqiMoveFrame(2));
    expect(
      game.channel.sent.whereType<String>().where((frame) => frame.contains('"g_v2.move"')),
      hasLength(1),
    );
  });

  test('a resync snapshot discards the premove instead of executing stale intent', () async {
    final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame(plies: 1));
    game.controller.movePiece(square('a3'), square('a4'), premoveEnabled: true);
    await game.send(fx.xiangqiSnapshotFrame(plies: 2));
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNull);
    expect(
      game.channel.sent.whereType<String>().where((frame) => frame.contains('"g_v2.move"')),
      isEmpty,
    );
  });

  test('a geometric candidate that remains illegal is discarded at execution', () async {
    final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame(plies: 1));
    game.controller.movePiece(square('a0'), square('a9'), premoveEnabled: true);
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNotNull);
    await game.send(fx.xiangqiMoveFrame(2));
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNull);
    expect(
      game.channel.sent.whereType<String>().where((frame) => frame.contains('"g_v2.move"')),
      isEmpty,
    );
  });

  test('disabled premoves, spectators and history cannot queue moves', () async {
    final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame(plies: 1));
    game.controller.movePiece(square('a3'), square('a4'));
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNull);
    game.controller.goTo(0);
    game.controller.movePiece(square('a3'), square('a4'), premoveEnabled: true);
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNull);
    final spectator = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestSpectatorId));
    await spectator.send(fx.xiangqiSnapshotFrame(plies: 1));
    spectator.controller.movePiece(square('a3'), square('a4'), premoveEnabled: true);
    expect(spectator.container.read(xiangqiPendingPremoveProvider(spectator.gameId)), isNull);
  });

  test('ending or explicitly cancelling a premove clears local intent', () async {
    final game = await makeHarness(fx.xiangqiTestToken(fx.xiangqiTestViewerId));
    await game.send(fx.xiangqiSnapshotFrame(plies: 1));
    game.controller.movePiece(square('a3'), square('a4'), premoveEnabled: true);
    game.controller.cancelPremove();
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNull);
    game.controller.movePiece(square('a3'), square('a4'), premoveEnabled: true);
    await game.send(fx.xiangqiEndFrame());
    expect(game.container.read(xiangqiPendingPremoveProvider(game.gameId)), isNull);
  });
}
