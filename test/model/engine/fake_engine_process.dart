import 'dart:async';

import 'package:lichess_mobile/src/model/engine/system_stockfish_transport.dart';

/// An [EngineProcess] a test drives by hand.
///
/// The seam [SystemStockfishTransport] runs a desktop engine through: the real implementation is
/// the stockfish installed on the machine, and a test has none to start. This is the other end of
/// that pipe — the lines written to it are recorded, and the lines it answers with are the test's
/// to choose.
class FakeEngineProcess({final bool ignoresQuit = false}) implements EngineProcess {
  final _lines = StreamController<String>();
  final _errors = StreamController<String>();
  final _exitCode = Completer<int>();

  /// Every line written to the process, in order.
  ///
  /// Without a line ending: adding one is [SystemEngineProcess]'s doing, and what a line consists
  /// of is what the transport above is answerable for.
  final List<String> writes = [];

  bool _killed = false;

  /// Whether the process was killed rather than left to quit.
  bool get wasKilled => _killed;

  /// Whether the process has exited.
  bool get hasExited => _exitCode.isCompleted;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  void write(String line) {
    // A pipe to a process that is gone, the way writing to one answers: the transport has to be
    // able to survive being handed a process it has not yet been told the death of.
    if (hasExited) throw StateError('The process is gone; cannot write "$line"');
    writes.add(line);
    // The engine that behaves: it goes when it is told to, which is why the transport has nothing
    // left to kill.
    if (line == 'quit' && !ignoresQuit) exit(0);
  }

  @override
  void kill() {
    _killed = true;
    // What a process killed the way [Process.kill] kills one exits with.
    exit(-15);
  }

  /// Answers with a line on the process's standard output, as the engine would.
  void emit(String line) {
    if (!_lines.isClosed) _lines.add(line);
  }

  /// Answers with a line on the process's standard error, as an engine that is unhappy does.
  void emitError(String line) {
    if (!_errors.isClosed) _errors.add(line);
  }

  /// Ends the process with [code], closing its pipes as a process that exits does.
  void exit(int code) {
    if (hasExited) return;
    if (!_lines.isClosed) unawaited(_lines.close());
    if (!_errors.isClosed) unawaited(_errors.close());
    _exitCode.complete(code);
  }
}
