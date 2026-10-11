import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/system_stockfish_transport.dart';

import 'fake_engine_process.dart';
import 'fake_transport.dart';

/// Starts a [SystemStockfishTransport] over [process].
///
/// The timeouts are shortened from the ones the app runs with: a test that means to wait a
/// handshake or a quit out should not sit through what a user would, and one that does not mean to
/// should not set the wait off at all.
Future<SystemStockfishTransport> connectTo(
  FakeEngineProcess process, {
  Duration handshakeTimeout = const Duration(seconds: 1),
  Duration quitTimeout = const Duration(milliseconds: 100),
}) => SystemStockfishTransport.connect(
  const SystemStockfishSpec(),
  start: () async => process,
  handshakeTimeout: handshakeTimeout,
  quitTimeout: quitTimeout,
);

/// Both of the above: starts the transport and answers its `uci`, as an engine that works does.
///
/// Where every test that is not about the handshake itself starts from, because a transport is only
/// handed to an [Engine] once it is ready: nothing else these tests do can be reached before that.
Future<SystemStockfishTransport> connectToReadyEngine(FakeEngineProcess process) async {
  final connecting = connectTo(process);
  await pumpEventQueue();
  answerHandshake(process);
  return await connecting;
}

/// Answers a `uci` the way a UCI engine does: what it calls itself, its options, then `uciok`.
void answerHandshake(FakeEngineProcess process) {
  process.emit('Stockfish 19 by the Stockfish developers');
  process.emit('id name Stockfish 19');
  for (final line in kFakeOptionDeclarations) {
    process.emit(line);
  }
  process.emit('uciok');
}

void main() {
  group('SystemStockfishTransport', () {
    test('asks the engine for uci, and is ready once it answers uciok', () async {
      final process = FakeEngineProcess();
      var ready = false;
      final connecting = connectTo(process).then((transport) {
        ready = true;
        return transport;
      });

      await pumpEventQueue();
      expect(process.writes, ['uci']);

      // Everything the handshake consists of up to the last line is not the answer it waits for.
      process.emit('id name Stockfish 19');
      for (final line in kFakeOptionDeclarations) {
        process.emit(line);
      }
      await pumpEventQueue();
      expect(ready, isFalse);

      process.emit('uciok');
      final transport = await connecting;
      addTearDown(transport.dispose);

      expect(ready, isTrue);
      expect(transport.isDead, isFalse);
      expect(transport.spec, const SystemStockfishSpec());
    });

    test('replays what the engine said before anything could listen', () async {
      final process = FakeEngineProcess();
      final transport = await connectToReadyEngine(process);
      addTearDown(transport.dispose);

      // Whoever drives the engine is given one that is already ready, so the handshake it never
      // saw has to be handed over afterwards.
      final lines = <String>[];
      transport.lines.listen(lines.add);
      await pumpEventQueue();

      expect(lines, [
        'Stockfish 19 by the Stockfish developers',
        'id name Stockfish 19',
        ...kFakeOptionDeclarations,
        'uciok',
      ]);
    });

    test('is understood by the engine layer that drives it', () async {
      final process = FakeEngineProcess();
      final transport = await connectToReadyEngine(process);

      // The name is read off the replayed handshake, and what follows a `uciok` is the only place
      // it is ever stated.
      final engine = Engine(transport);
      addTearDown(engine.dispose);
      await pumpEventQueue();

      expect(engine.name.value, 'Stockfish 19');
    });

    test('writes commands through, and drops them once the engine is gone', () async {
      final process = FakeEngineProcess();
      final transport = await connectToReadyEngine(process);
      addTearDown(transport.dispose);

      transport.send('ucinewgame');
      transport.send('position startpos');
      transport.send('go movetime 100');

      expect(process.writes, ['uci', 'ucinewgame', 'position startpos', 'go movetime 100']);

      process.exit(0);
      await transport.death;

      // A dead engine answers nothing, so a command sent to it is not worth the pipe it would be
      // written to — nor the throw that writing to a gone process would raise.
      transport.send('stop');
      expect(process.writes, ['uci', 'ucinewgame', 'position startpos', 'go movetime 100']);
    });

    test('is dead, with the exit code, when the process exits', () async {
      final process = FakeEngineProcess();
      final transport = await connectToReadyEngine(process);
      addTearDown(transport.dispose);

      transport.send('go movetime 100');
      process.exit(3);
      final failure = await transport.death;

      expect(transport.isDead, isTrue);
      expect(failure?.kind, EngineFailureKind.runtime);
      expect(failure?.message, contains('3'));
      expect(failure?.message, contains('go movetime 100'));
      expect(failure?.engine, 'system stockfish');
      expect(failure?.engineState, 'exited');
    });

    test('says what it is doing, and keeps the engine stderr to explain it', () async {
      final process = FakeEngineProcess();
      final transport = await connectToReadyEngine(process);
      addTearDown(transport.dispose);

      expect(transport.diagnostics?.phase, 'subprocess');
      expect(transport.diagnostics?.step, 'idle');
      expect(transport.diagnostics?.lastError, isNull);
      expect(transport.diagnostics?.looksStuck, isFalse);

      transport.send('go movetime 100');
      expect(transport.diagnostics?.step, 'search');

      process.emitError('info string NNUE evaluation using nn-1c0000000000.nnue');
      process.emitError('Terminating: could not allocate');
      await pumpEventQueue();
      expect(transport.diagnostics?.lastError, 'Terminating: could not allocate');

      process.exit(1);
      await transport.death;
      expect(transport.diagnostics?.step, 'exited');
    });

    test('disposes by asking the engine to quit', () async {
      final process = FakeEngineProcess();
      final transport = await connectToReadyEngine(process);

      await transport.dispose();

      expect(process.writes, ['uci', 'quit']);
      expect(process.wasKilled, isFalse);
      expect(process.hasExited, isTrue);
      expect(transport.isDead, isTrue);
      // An engine that quit when it was told to did not fail.
      expect(await transport.death, isNull);
    });

    test('kills an engine that will not quit', () async {
      final process = FakeEngineProcess(ignoresQuit: true);
      final transport = await connectToReadyEngine(process);

      await transport.dispose();

      expect(process.writes, ['uci', 'quit']);
      expect(process.wasKilled, isTrue);
      expect(process.hasExited, isTrue);
      expect(transport.isDead, isTrue);
      expect(await transport.death, isNull);
    });

    test('fails, and lets the engine go, when it never answers uci', () async {
      final process = FakeEngineProcess();

      await expectLater(
        connectTo(process, handshakeTimeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );

      // Nothing is left running behind a start that failed: the engine was told to quit, and went.
      expect(process.writes, ['uci', 'quit']);
      expect(process.hasExited, isTrue);
    });

    test('fails when the engine exits before it answers', () async {
      final process = FakeEngineProcess();
      final connecting = connectTo(process);
      await pumpEventQueue();

      process.exit(1);

      // Waited out rather than timed out: a process that is gone has said why it is not answering.
      await expectLater(connecting, throwsA(isA<StateError>()));
      expect(process.writes, ['uci']);
    });
  });
}
