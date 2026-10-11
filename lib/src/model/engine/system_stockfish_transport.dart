import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:lichess_mobile/src/model/engine/engine_diagnostics.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/engine_transport.dart';
import 'package:logging/logging.dart';

final _logger = Logger('SystemStockfishTransport');

/// How long the engine is given to answer `uci` with `uciok`.
const kSystemEngineHandshakeTimeout = Duration(seconds: 10);

/// How long a `quit` is waited out before the process is killed.
const kSystemEngineQuitTimeout = Duration(seconds: 3);

/// The executable looked up on `PATH`.
const kSystemStockfishExecutable = 'stockfish';

/// How many stderr lines are kept to explain a failure.
const _kStderrHistory = 20;

/// A UCI engine running as a child process: its output, its input, its lifetime.
///
/// The seam [SystemStockfishTransport] is tested through. Everything the transport does to the
/// engine goes through this, so a test can drive a whole session — a handshake, a search, a crash,
/// a quit the engine will not answer — without a stockfish on the machine and without owning a
/// process it cannot control.
abstract class EngineProcess() {
  /// The process's standard output, line by line.
  Stream<String> get lines;

  /// The process's standard error, line by line.
  Stream<String> get errors;

  /// Completes with the exit code when the process exits.
  Future<int> get exitCode;

  /// Writes a line to the process's standard input.
  void write(String line);

  /// Kills the process.
  void kill();
}

/// An [EngineProcess] over the `dart:io` process API.
class SystemEngineProcess(final Process _process) implements EngineProcess {
  /// Starts the stockfish installed on this machine.
  ///
  /// Throws a [ProcessException] when there is no such executable on `PATH`: the one failure of
  /// this backend the user can do something about, and the one `EngineFactory` words for them.
  static Future<SystemEngineProcess> start() async =>
      SystemEngineProcess(await Process.start(kSystemStockfishExecutable, const []));

  // A process's output streams are single-subscription, and are read here once each: they are
  // built on first use rather than in the constructor.
  @override
  late final Stream<String> lines = _decoded(_process.stdout);

  @override
  late final Stream<String> errors = _decoded(_process.stderr);

  static Stream<String> _decoded(Stream<List<int>> bytes) =>
      bytes.transform(utf8.decoder).transform(const LineSplitter());

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(String line) => _process.stdin.writeln(line);

  @override
  void kill() => _process.kill();
}

/// An [EngineTransport] over a UCI engine running as a child process.
///
/// The desktop counterpart of the plugin transports. Two things the plugin does on a transport's
/// behalf have to be done here instead:
///
///  - **the `uci` handshake**, because an [Engine] is handed a transport as an engine that is
///    already ready and answering: `id name` and the `option` declarations must be in the past —
///    and in [_startupLines] — by the time [connect] completes; and
///  - **the process's lifetime**, because nothing else owns it: [death] is answered by the child
///    exiting, whether it quit, crashed, or had to be killed.
class SystemStockfishTransport._(
  final EngineProcess _process,
  @override final SystemStockfishSpec spec,
  final Duration _quitTimeout,
) implements EngineTransport {
  this {
    _controller.onListen = _replayStartupLines;
    _linesSubscription = _process.lines.listen(
      _receive,
      onError: _onOutputError,
      onDone: _onOutputDone,
    );
    _errorsSubscription = _process.errors.listen(_onStderr, onError: _onOutputError);
    unawaited(_process.exitCode.then(_onExit, onError: _onExitError));
  }

  /// Starts the engine and completes when it has answered `uciok`.
  ///
  /// [start] replaces the process, and the two timeouts shorten the waits, for tests.
  ///
  /// Throws what the engine could not do: a [ProcessException] when there is no executable on
  /// `PATH`, a [TimeoutException] when one started but never answered, a [StateError] when one
  /// exited before it answered. Either way the process has been let go of by the time this throws,
  /// so a failed start leaves nothing running.
  static Future<SystemStockfishTransport> connect(
    SystemStockfishSpec spec, {
    Future<EngineProcess> Function()? start,
    Duration handshakeTimeout = kSystemEngineHandshakeTimeout,
    Duration quitTimeout = kSystemEngineQuitTimeout,
  }) async {
    final process = await (start ?? SystemEngineProcess.start)();
    final transport = SystemStockfishTransport._(process, spec, quitTimeout);
    transport.send('uci');
    try {
      // `uciok`, or the exit, whichever comes first: an engine that died on its way up has already
      // said why, so there is no reason to sit out the timeout for an answer that is not coming.
      await Future.any<void>([transport._handshake.future, transport._process.exitCode])
          .timeout(handshakeTimeout);
      if (!transport._handshake.isCompleted) {
        throw StateError(
          'The engine exited with code ${transport._exitCode} before it answered "uci"',
        );
      }
    } catch (e, st) {
      _logger.severe('The $spec did not become ready', e, st);
      await transport.dispose();
      rethrow;
    }
    return transport;
  }

  final _controller = StreamController<String>.broadcast();
  final _death = Completer<EngineFailure?>();

  /// Completed by the engine's `uciok`.
  final _handshake = Completer<void>();

  /// Owned so that they are let go of with the engine: the process's pipes are held open by
  /// whoever is listening to them.
  StreamSubscription<String>? _linesSubscription;
  StreamSubscription<String>? _errorsSubscription;

  /// The lines the engine wrote before anyone could listen, replayed to the first listener.
  final List<String> _startupLines = [];
  bool _replayed = false;

  bool _disposing = false;
  Future<void>? _disposal;

  /// The last command sent, whatever became of it.
  String? _lastCommand;

  /// The engine's last few stderr lines, oldest first.
  final ListQueue<String> _stderr = ListQueue();

  /// The exit code, once the process has exited.
  int? _exitCode;

  final _elapsed = Stopwatch()..start();

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<EngineFailure?> get death => _death.future;

  @override
  bool get isDead => _death.isCompleted;

  @override
  EngineDiagnostics? get diagnostics => EngineDiagnostics(
    phase: 'subprocess',
    step: _step,
    elapsed: _elapsed.elapsed,
    // Nothing here judges a subprocess to be wedged: the plugin's verdict is about native phases
    // this backend does not have. A handshake that never finishes is a failure [connect] raises
    // rather than a state to report from here, and a search that never ends is the layer above's
    // to time out.
    looksStuck: false,
    lastError: _stderr.isEmpty ? null : _stderr.last,
  );

  /// What the engine is doing, as far as a child process can be asked.
  String get _step {
    if (isDead) return 'exited';
    if (!_handshake.isCompleted) return 'handshake';
    return (_lastCommand?.startsWith('go') ?? false) ? 'search' : 'idle';
  }

  @override
  void send(String command) {
    if (_disposing || isDead) {
      _logger.fine('Dropping "$command": the engine is gone or on its way out.');
      return;
    }
    _lastCommand = command;
    try {
      _process.write(command);
    } catch (e, st) {
      // A process whose pipe is closed will never read anything again: the session is over.
      _die(
        _failure(
          EngineFailureKind.command,
          'The engine refused the command "$command"',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  @override
  Future<void> dispose() {
    if (_disposal case final disposal?) return disposal;
    _disposing = true;
    return _disposal = _shutdown();
  }

  /// Asks the engine to quit, and waits for it to be gone — killing it if it will not go.
  ///
  /// Both waits are bounded, because [death] is answered by the exit: whoever comes next cannot
  /// proceed until the process has stopped existing, and a process that has decided not to answer
  /// `quit` must not be able to hold the app up.
  Future<void> _shutdown() async {
    if (!isDead) {
      _lastCommand = 'quit';
      try {
        _process.write('quit');
      } catch (e, st) {
        // Already gone, or it never had a pipe. The exit is all that is left to wait for.
        _logger.fine('The engine could not be told to quit', e, st);
      }
    }

    if (!await _exited()) {
      _logger.warning('The engine did not exit when told to quit; killing it');
      _process.kill();
      if (!await _exited()) {
        _logger.severe('The engine could not be killed; its process may outlive the app');
      }
    }

    _die(null);
  }

  /// Waits [_quitTimeout] for the process to exit, answering whether it did.
  Future<bool> _exited() async {
    if (_exitCode != null) return true;
    try {
      await _process.exitCode.timeout(_quitTimeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _replayStartupLines() {
    if (_replayed) return;
    _replayed = true;
    for (final line in _startupLines) {
      _receive(line);
    }
    _startupLines.clear();
  }

  void _receive(String line) {
    if (_controller.isClosed) return;
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    if (!_handshake.isCompleted && trimmed == 'uciok') _handshake.complete();
    if (_replayed) {
      _controller.add(trimmed);
    } else {
      _startupLines.add(trimmed);
    }
  }

  void _onStderr(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    if (_stderr.length >= _kStderrHistory) _stderr.removeFirst();
    _stderr.add(trimmed);
    _logger.fine('$spec stderr: $trimmed');
  }

  void _onOutputDone() {
    // The engine closed its output but may still be running; the exit code is what ends the
    // session, and whatever it wrote on the way out has already been delivered.
    _logger.fine('$spec closed its output');
  }

  void _onOutputError(Object error, StackTrace stackTrace) {
    _logger.warning('Reading the $spec output failed', error, stackTrace);
    _process.kill();
    _die(
      _failure(
        EngineFailureKind.runtime,
        'The engine output stream failed',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _onExit(int exitCode) {
    _exitCode = exitCode;
    // An engine that was asked to quit and went is not a failure; one that went on its own — or
    // during a start that had already gone wrong — is.
    _die(
      _disposing
          ? null
          : _failure(
              EngineFailureKind.runtime,
              _lastCommand == null
                  ? 'The engine exited with code $exitCode'
                  : 'The engine exited with code $exitCode after "$_lastCommand"',
            ),
    );
  }

  void _onExitError(Object error, StackTrace stackTrace) {
    _die(
      _failure(
        EngineFailureKind.runtime,
        'The engine could not be waited for',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Ends the session: nothing more is sent, nothing more is delivered, and [death] is answered.
  void _die(EngineFailure? failure) {
    if (_death.isCompleted) return;
    _death.complete(failure);
    unawaited(_linesSubscription?.cancel());
    unawaited(_errorsSubscription?.cancel());
    if (!_controller.isClosed) _controller.close();
  }

  EngineFailure _failure(
    EngineFailureKind kind,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => EngineFailure(
    kind: kind,
    message: message,
    engine: spec.label,
    // The exit code rather than [isDead], which is still false while this failure is being built:
    // a process that has exited is what a failure report should call exited, however it ended.
    engineState: _exitCode != null ? 'exited' : 'running',
    diagnostics: diagnostics,
    error: error,
    stackTrace: stackTrace,
  );
}
