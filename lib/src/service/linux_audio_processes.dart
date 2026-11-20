import 'dart:io';

typedef AudioProcessStarter = Future<Process> Function(String executable, List<String> arguments);

/// Owns the external audio players used by the Linux sound service.
class LinuxAudioProcesses({AudioProcessStarter? start}) {
  final AudioProcessStarter _start = start ?? Process.start;

  Future<void> play(String executable, List<String> arguments) async {
    await _start(executable, arguments);
  }

  Future<void> shutdown() async {}
}
