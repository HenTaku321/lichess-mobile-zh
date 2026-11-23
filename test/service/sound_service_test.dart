import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';

import '../test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.lichess/sound_effect');
  final loaded = <String, String>{};
  final previews = <String?>[];
  late Completer<void> oldLoad;
  late Completer<void> loading;

  setUp(() {
    loaded.clear();
    previews.clear();
    oldLoad = Completer<void>();
    loading = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        final args = call.arguments as Map<Object?, Object?>?;
        switch (call.method) {
          case 'load':
            final id = args!['soundId']! as String;
            final path = args['path']! as String;
            if (id == 'move' && path.contains('/piano/')) {
              loading.complete();
              await oldLoad.future;
            }
            loaded[id] = path;
          case 'release':
            loaded.clear();
          case 'play':
            previews.add(loaded[args!['soundId']]);
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test('last sound theme wins when an earlier load completes late', () async {
    final container = await makeContainer(
      overrides: {soundServiceProvider: soundServiceProvider.overrideWith(SoundService.new)},
    );
    final service = container.read(soundServiceProvider);
    final old = service.changeTheme(SoundTheme.piano, playSound: true);
    await loading.future;
    final latest = service.changeTheme(SoundTheme.nes, playSound: true);
    await pumpEventQueue();
    oldLoad.complete();
    await Future.wait([old, latest]);
    expect(loaded['move'], contains('/nes/'));
    expect(previews, [contains('/nes/')]);
    expect(loaded.values.any((path) => path.contains('/piano/')), isFalse);
    await service.release();
  });

  test('release drains pending loads without resurrecting sounds or previews', () async {
    final container = await makeContainer(
      overrides: {soundServiceProvider: soundServiceProvider.overrideWith(SoundService.new)},
    );
    final service = container.read(soundServiceProvider);
    final change = service.changeTheme(SoundTheme.piano, playSound: true);
    await loading.future;
    final release = service.release();
    await pumpEventQueue();
    oldLoad.complete();
    await Future.wait([change, release]);
    expect(loaded, isEmpty);
    expect(previews, isEmpty);
  });
  test('shutdown seals the service while a load is still pending', () async {
    final container = await makeContainer(
      overrides: {soundServiceProvider: soundServiceProvider.overrideWith(SoundService.new)},
    );
    final service = container.read(soundServiceProvider);
    final change = service.changeTheme(SoundTheme.piano, playSound: true);
    await loading.future;
    final shutdown = SoundService.shutdown();
    await service.changeTheme(SoundTheme.nes, playSound: true);
    oldLoad.complete();
    await Future.wait([change, shutdown]);
    await service.play(Sound.move);
    expect(loaded, isEmpty);
    expect(previews, isEmpty);
  });
}
