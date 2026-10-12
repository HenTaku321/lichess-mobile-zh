import 'dart:async';

import 'package:lichess_mobile/src/model/engine/engine_diagnostics.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/engine_transport.dart';

/// The `option` declarations a Stockfish-like engine prints during its `uci` handshake.
///
/// Only the ones the app ever sets, which are the only ones option hygiene has to put back.
const kFakeOptionDeclarations = [
  'option name Threads type spin default 1 min 1 max 1024',
  'option name Hash type spin default 16 min 1 max 33554432',
  'option name MultiPV type spin default 1 min 1 max 256',
  'option name Skill Level type spin default 20 min -20 max 20',
  'option name UCI_Chess960 type check default false',
  'option name UCI_Variant type combo default chess var chess var crazyhouse var atomic',
];

/// The `option` declarations LC0 prints during its `uci` handshake, as far as the app cares.
///
/// Two differences from [kFakeOptionDeclarations] carry the whole point: there is **no `Hash`**,
/// and there is no `Temperature` — LC0 accepts that one by name but declares it "pro only", so it
/// never reaches the handshake.
const kFakeLc0OptionDeclarations = [
  'option name Threads type spin default 2 min 1 max 128',
  'option name MultiPV type spin default 1 min 1 max 500',
  'option name WeightsFile type string default <autodiscover>',
  'option name MinibatchSize type spin default 256 min 1 max 1024',
  'option name UCI_Chess960 type check default false',
];

/// The lines Pikafish prints when it is asked `uci`, transcribed from the engine this app ships.
///
/// What matters about it is what is **missing**. There is no `Skill Level` and no
/// `UCI_LimitStrength` — Pikafish has no strength setting at all, where Fairy-Stockfish's negative
/// skill levels are how the app's weakest chess opponents are made — so how hard it plays can only
/// be said with a search limit. There is no `UCI_Variant` either, so it is never told which game it
/// is playing from an option: a xiangqi position reaches it as a FEN and nothing else. And there is
/// no `UCI_Chess960`, which is why a xiangqi search sends no options at all.
///
/// The banner and the `id name` are what the build calls itself, which Pikafish derives from the
/// build date and the git state it was built in rather than from the commit; nothing asserts on
/// them.
const kPikafishHandshake = [
  'Pikafish dev-20261012-nogit by the Pikafish developers (see AUTHORS file)',
  'id name Pikafish dev-20261012-nogit',
  'id author the Pikafish developers (see AUTHORS file)',
  'option name Debug Log File type string default <empty>',
  'option name NumaPolicy type string default auto',
  'option name Threads type spin default 1 min 1 max 1024',
  'option name Hash type spin default 16 min 1 max 33554432',
  'option name Clear Hash type button',
  'option name Ponder type check default false',
  'option name MultiPV type spin default 1 min 1 max 128',
  'option name Move Overhead type spin default 10 min 0 max 5000',
  'option name nodestime type spin default 0 min 0 max 10000',
  'option name UCI_ShowWDL type check default false',
  'option name EvalFile type string default pikafish.nnue',
  'uciok',
];

/// An [EngineTransport] that records what was sent to it and lets a test answer by hand.
///
/// This is the seam for testing the UCI protocol itself: no plugin, no isolates, no engine — just
/// the lines in and the lines out.
class FakeTransport({
  @override final EngineSpec spec = const StockfishSpec.light(),
  List<String> startupLines = const [
    'Stockfish 19 by the Stockfish developers',
    'id name Stockfish 19',
    ...kFakeOptionDeclarations,
    'uciok',
  ],
}) implements EngineTransport {
  this {
    _pending.addAll(startupLines);
    _controller.onListen = () {
      if (_replayed) return;
      _replayed = true;
      for (final line in _pending) {
        _controller.add(line);
      }
      _pending.clear();
    };
  }

  /// Every command the engine was sent, in order.
  final List<String> commands = [];

  final _controller = StreamController<String>.broadcast();
  final _death = Completer<EngineFailure?>();
  final _pending = <String>[];
  bool _replayed = false;

  /// The commands sent since the last [takeCommands].
  List<String> takeCommands() {
    final taken = List<String>.of(commands);
    commands.clear();
    return taken;
  }

  /// Answers with a line, as the engine would.
  void emit(String line) {
    if (!_controller.isClosed) _controller.add(line);
  }

  /// Kills the engine, with [failure] if it died badly.
  void die([EngineFailure? failure]) {
    if (_death.isCompleted) return;
    _death.complete(failure);
    if (!_controller.isClosed) _controller.close();
  }

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<EngineFailure?> get death => _death.future;

  @override
  bool get isDead => _death.isCompleted;

  @override
  EngineDiagnostics? get diagnostics => const EngineDiagnostics(
    phase: 'idle',
    step: 'idle',
    elapsed: Duration.zero,
    looksStuck: false,
  );

  @override
  void send(String command) {
    if (isDead) return;
    commands.add(command);
  }

  @override
  Future<void> dispose() async {
    die();
  }
}
