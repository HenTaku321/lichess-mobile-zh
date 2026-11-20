import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

typedef AudioProcessStarter = Future<Process> Function(String executable, List<String> arguments);

final _logger = Logger('LinuxAudioProcesses');

/// Owns the external audio players, including launches still waiting for Process.start.
class LinuxAudioProcesses({AudioProcessStarter? start}) {
  final AudioProcessStarter _start = start ?? Process.start;
  final Set<_Playback> _playbacks = {};
  Future<void>? _shutdown;

  Future<void> play(String executable, List<String> arguments) async {
    if (_shutdown != null || _playbacks.length >= 2) return;
    final playback = _Playback();
    _playbacks.add(playback);
    try {
      final process = await _start(executable, arguments);
      playback.process = process;
      playback.pipes =
          [process.stdout.drain<void>(), process.stderr.drain<void>(), process.stdin.close()]
              .map(
                (pipe) => pipe.catchError((Object error, StackTrace stack) {
                  _logger.fine('Audio pipe closed', error, stack);
                }),
              )
              .toList();
      unawaited(
        process.exitCode.then<void>(
          (_) {
            playback.exited = true;
            _playbacks.remove(playback);
          },
          onError: (Object error, StackTrace stack) {
            _logger.warning('Could not observe audio process exit', error, stack);
          },
        ),
      );
    } catch (error, stack) {
      _logger.warning('Could not start audio playback', error, stack);
      if (playback.process == null) _playbacks.remove(playback);
    } finally {
      playback.started.complete();
    }
  }

  /// Seals the owner synchronously, then joins launches and reaps all owned children.
  Future<void> shutdown() => _shutdown ??= Future.microtask(() async {
    await Future.wait<void>([for (final playback in _playbacks.toList()) playback.stop()]);
  });
}

class _Playback() {
  final started = Completer<void>();
  Process? process;
  bool exited = false;
  List<Future<void>> pipes = [];

  Future<void> stop() async {
    await started.future;
    final child = process;
    if (child == null) return;
    if (!exited) {
      child.kill();
      try {
        await child.exitCode.timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 2));
      }
    }
    await Future.wait(pipes).timeout(const Duration(seconds: 2));
  }
}
