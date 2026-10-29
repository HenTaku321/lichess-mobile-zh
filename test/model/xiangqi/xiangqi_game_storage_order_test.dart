import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

import '../../binding.dart';

SavedXiangqiGame saved(XiangqiDifficulty difficulty) => SavedXiangqiGame(
  state: XiangqiGameState(
    playerSide: .red,
    difficulty: difficulty,
    positions: IList([XiangqiPosition.initial()]),
    moves: const IListConst([]),
  ),
  timeIncrement: const TimeIncrement.infinite(),
);

Future<({XiangqiGameStorage storage, Directory directory, Completer<String> blocked})>
harness() async {
  final directory = await Directory.systemTemp.createTemp('xiangqi-storage-');
  final blocked = Completer<String>();
  var calls = 0;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) {
    if (++calls == 1) return blocked.future;
    return Future.value(directory.path);
  });
  addTearDown(() async {
    if (!blocked.isCompleted) blocked.complete(directory.path);
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
  return (storage: const XiangqiGameStorage(), directory: directory, blocked: blocked);
}

void main() {
  TestLichessBinding.ensureInitialized();

  test('a delayed old save cannot resurrect a game deleted by a new-game action', () async {
    final fixture = await harness();
    final saving = fixture.storage.save(saved(.level1));
    await pumpEventQueue();
    final deleting = fixture.storage.delete();
    await pumpEventQueue();
    fixture.blocked.complete(fixture.directory.path);
    await Future.wait([saving, deleting]);
    expect(await File('${fixture.directory.path}/$kXiangqiGameFileName').exists(), isFalse);
  });

  test('the most recent save wins even when an older directory lookup is delayed', () async {
    final fixture = await harness();
    final older = fixture.storage.save(saved(.level1));
    await pumpEventQueue();
    final newer = fixture.storage.save(saved(.level6));
    await pumpEventQueue();
    fixture.blocked.complete(fixture.directory.path);
    await Future.wait([older, newer]);
    final file = File('${fixture.directory.path}/$kXiangqiGameFileName');
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(json['difficulty'], 'level6');
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });
}
