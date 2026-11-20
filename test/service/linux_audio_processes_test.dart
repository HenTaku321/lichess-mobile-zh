import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/service/linux_audio_processes.dart';
import 'package:mocktail/mocktail.dart';

Future<Process> sleeper() => Process.start('python3', [
  '-u',
  '-c',
  'import signal, time\n'
      'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
      'print("ready", flush=True)\n'
      'time.sleep(60)\n',
]);

class ObservedProcess extends Mock implements Process {}

void main() {
  test('shutdown reaps playback even when SIGTERM is ignored', () async {
    if (!Platform.isLinux) return;
    final child = await sleeper();
    await child.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
    int? code;
    final exited = child.exitCode.then((value) => code = value);
    addTearDown(() async {
      if (code == null) child.kill(ProcessSignal.sigkill);
      await exited;
    });
    final observed = ObservedProcess();
    when(() => observed.stdout).thenAnswer((_) => const Stream<List<int>>.empty());
    when(() => observed.stderr).thenAnswer((_) => child.stderr);
    when(() => observed.stdin).thenReturn(child.stdin);
    when(() => observed.exitCode).thenAnswer((_) => child.exitCode);
    when(() => observed.kill()).thenAnswer((_) => child.kill());
    when(() => observed.kill(ProcessSignal.sigkill))
        .thenAnswer((_) => child.kill(ProcessSignal.sigkill));
    final player = LinuxAudioProcesses(start: (_, _) async => observed);
    await player.play('player', []);
    await player.shutdown();
    expect(code, -9);
  });

  test('shutdown waits for a pending start and rejects new playback', () async {
    if (!Platform.isLinux) return;
    final starting = Completer<Process>();
    var starts = 0;
    final player = LinuxAudioProcesses(
      start: (_, _) {
        starts++;
        return starting.future;
      },
    );
    final playing = player.play('player', []);
    var stopped = false;
    final stopping = player.shutdown().then((_) => stopped = true);
    await pumpEventQueue();
    expect(stopped, isFalse);
    final child = await sleeper();
    addTearDown(() async {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    });
    starting.complete(child);
    await playing;
    await stopping;
    await player.play('player', []);
    expect(starts, 1);
  });

  test('pending process starts count toward the two-player limit', () async {
    final starts = <Completer<Process>>[];
    final player = LinuxAudioProcesses(
      start: (_, _) {
        final pending = Completer<Process>();
        starts.add(pending);
        return pending.future;
      },
    );
    final calls = [for (var i = 0; i < 8; i++) player.play('player', [])];
    await pumpEventQueue();
    final numberStarted = starts.length;
    for (final pending in starts) {
      pending.completeError(const ProcessException('player', [], 'unavailable'));
    }
    await Future.wait(calls);
    await player.shutdown();
    expect(numberStarted, 2);
  });

  test('a failed process start does not escape to the UI', () async {
    final player = LinuxAudioProcesses(
      start: (_, _) async {
        throw const ProcessException('player', [], 'unavailable');
      },
    );
    await expectLater(player.play('player', []), completes);
    await player.shutdown();
  });
}
