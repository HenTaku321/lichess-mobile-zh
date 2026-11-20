import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_factory.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';

import 'fake_engine.dart';
import 'fake_transport.dart';

/// A minimal search, for checking which engine answers it.
SearchRequest makeRequest({SearchLimit limit = const SearchLimit.movetime(Duration(seconds: 1))}) =>
    SearchRequest(
      initialPosition: Chess.initial,
      moves: const IListConst([]),
      variant: Variant.standard,
      limit: limit,
      game: 'test',
    );

/// A factory that starts [engine] instead of a real one.
EngineFactory factoryFor(FakeEngine engine) => EngineFactory(connect: engine.connect);

class FailedDisposeTransport() extends FakeTransport {
  @override
  Future<void> dispose() async => throw TimeoutException('native reader is still alive');
}

void main() {
  group('EngineFactory', () {
    test('starts an engine that answers its handshake', () async {
      final engine = FakeEngine();
      final factory = factoryFor(engine);

      final started = await factory.create(const StockfishSpec.light());
      addTearDown(started.dispose);
      await pumpEventQueue();

      expect(started.spec, const StockfishSpec.light());
      expect(started.name.value, 'Stockfish 19');
    });

    test('a create waits for the engine it replaces to finish exiting', () async {
      final engine = FakeEngine(quitDelay: const Duration(milliseconds: 50));
      final factory = factoryFor(engine);

      final first = await factory.create(const StockfishSpec.light());

      // Let go of it without waiting: this is what a provider being disposed looks like.
      unawaited(first.dispose());

      final second = await factory.create(const StockfishSpec.light());
      addTearDown(second.dispose);

      // The native library only frees the slot once the engine has actually exited, so the second
      // create must not have started before the first quit finished.
      expect(engine.quitCount, 1);
      expect(engine.startCount, 2);
      expect(engine.maxConcurrentOps, 1);
      expect(first.isDisposed, isTrue);
    });

    test('two live engines on one slot are a programming error, not a restart', () async {
      final factory = factoryFor(FakeEngine());

      final live = await factory.create(const StockfishSpec.light());
      addTearDown(live.dispose);

      await expectLater(
        factory.create(const StockfishSpec.light()),
        throwsA(
          isA<EngineCreationException>().having(
            (e) => e.failure.error,
            'error',
            isA<AssertionError>(),
          ),
        ),
      );
    });

    test('an engine the plugin refuses to start is reported as a start failure', () async {
      final factory = factoryFor(ThrowingStartEngine());

      await expectLater(
        factory.create(const StockfishSpec.light()),
        throwsA(
          isA<EngineCreationException>().having(
            (e) => e.failure.kind,
            'kind',
            EngineFailureKind.start,
          ),
        ),
      );
    });

    test('an engine that reports a failure instead of readiness is a start failure', () async {
      final factory = factoryFor(ErrorEngine());

      await expectLater(
        factory.create(const StockfishSpec.light()),
        throwsA(
          isA<EngineCreationException>().having(
            (e) => e.failure.kind,
            'kind',
            EngineFailureKind.start,
          ),
        ),
      );
    });

    test('a create that never returns is reported as stuck', () {
      final factory = factoryFor(StuckEngine());

      fakeAsync((async) {
        Object? error;
        factory
            .create(const StockfishSpec.light())
            .then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(kEngineCreateTimeout - const Duration(seconds: 1));
        expect(error, isNull, reason: 'the engine is still starting, and may yet succeed');

        async.elapse(const Duration(seconds: 2));

        expect(error, isA<EngineCreationException>());
        expect((error! as EngineCreationException).failure.kind, EngineFailureKind.stuck);
        expect((error! as EngineCreationException).failure.isUnrecoverable, isTrue);
      });
    });

    test('an engine that arrives after its create gave up is disposed', () {
      // The engine starts, but not before the create waiting for it has timed out.
      final engine = FakeEngine(startDelay: kEngineCreateTimeout + const Duration(seconds: 5));
      final factory = factoryFor(engine);

      fakeAsync((async) {
        Object? error;
        factory
            .create(const StockfishSpec.light())
            .then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(kEngineCreateTimeout + const Duration(seconds: 1));
        expect(error, isA<EngineCreationException>());

        // A future cannot be cancelled, so the create runs on and the engine still arrives. It
        // has no owner and nobody will ever quit it, so it must be quit here: a native slot an
        // abandoned engine holds is not free again until the app restarts.
        async.elapse(const Duration(seconds: 10));

        expect(engine.startCount, 1);
        expect(engine.quitCount, 1);
        expect(engine.isRunning, isFalse);
      });
    });

    test('a second create on one slot never runs beside the first', () async {
      final engine = FakeEngine(startDelay: const Duration(milliseconds: 50));
      final factory = factoryFor(engine);

      final firstRequest = factory.create(const StockfishSpec.light());

      // Listened to straight away: this one is expected to fail, and an error nobody is waiting
      // for yet would surface as an unhandled async error instead.
      Object? secondError;
      final secondRequest = factory
          .create(const StockfishSpec.light())
          .then<Engine?>(
            (engine) => engine,
            onError: (Object e) {
              secondError = e;
              return null;
            },
          );

      final first = await firstRequest;
      addTearDown(first.dispose);

      expect(await secondRequest, isNull, reason: 'one slot cannot host two engines');
      expect(secondError, isA<EngineCreationException>());

      // The native library hosts one engine per slot, so it must never be asked to start a second
      // one while the first is still starting.
      expect(engine.startCount, 1);
      expect(engine.maxConcurrentOps, 1);
    });

    test('engines for different slots are independent', () async {
      // Two flavours, two native libraries: nothing has to be quit to make room.
      final engine = FakeEngine();
      final factory = factoryFor(engine);

      final light = await factory.create(const StockfishSpec.light());
      addTearDown(light.dispose);
      final fairy = await factory.create(const StockfishSpec.fairy());
      addTearDown(fairy.dispose);

      expect(engine.quitCount, 0);
      expect(light.spec, isNot(fairy.spec));
    });

    test('failed background cleanup remains visible to shutdown', () async {
      final transport = FailedDisposeTransport();
      final factory = EngineFactory(connect: (_) async => transport);
      await factory.create(const StockfishSpec.light());
      transport.die(
        const EngineFailure(
          kind: EngineFailureKind.runtime,
          message: 'native reader failed',
          engine: 'test',
        ),
      );
      await pumpEventQueue();
      await expectLater(factory.shutdown(), throwsA(isA<TimeoutException>()));
    });

    test('shutdown joins a quit in progress and drains every live slot', () async {
      final engine = FakeEngine(quitDelay: const Duration(milliseconds: 50));
      final factory = factoryFor(engine);
      final light = await factory.create(const StockfishSpec.light());
      final fairy = await factory.create(const StockfishSpec.fairy());
      final analysis = fairy.search(makeRequest(limit: const SearchLimit.infinite()));
      await pumpEventQueue();
      expect(fairy.isSearching.value, isTrue);
      final quitting = light.dispose();
      final closing = factory.shutdown();

      expect(light.dispose(), same(quitting));
      expect(factory.shutdown(), same(closing));
      await closing;
      expect(await analysis.bestMove, isNull);
      expect(engine.isRunning, isFalse);
      expect(engine.quitCount, 2);
      await expectLater(factory.create(const Lc0Spec()), throwsA(isA<EngineCreationException>()));
      expect(engine.startCount, 2);
    });

    test(
      'shutdown drains an engine still starting without starting its queued replacement',
      () async {
        final engine = FakeEngine();
        final releaseStart = Completer<void>();
        var starts = 0;
        final factory = EngineFactory(
          connect: (spec) async {
            starts++;
            await releaseStart.future;
            return await engine.connect(spec);
          },
        );
        const spec = StockfishSpec.light();
        final starting = expectLater(factory.create(spec), throwsA(isA<EngineCreationException>()));
        final queued = expectLater(factory.create(spec), throwsA(isA<EngineCreationException>()));
        var closed = false;
        final closing = factory.shutdown().then((_) => closed = true);
        await pumpEventQueue();
        expect(closed, isFalse);
        releaseStart.complete();
        await closing;
        expect(starts, 1);
        expect(engine.quitCount, 1);
        expect(engine.isRunning, isFalse);
        await Future.wait([starting, queued]);
      },
    );

    test('an LC0 engine and a Stockfish engine are live at once, each with its '
        'own output', () async {
      // The point of giving both plugins private I/O. Before it, whichever
      // engine booted second took the process's fd 0 and fd 1 with it, and the
      // first one's output arrived on the second one's channel.
      // An engine that answers nothing by itself, so that every line below is
      // put on a session on purpose.
      final engine = ThrottleTestEngine();
      final factory = factoryFor(engine);

      final stockfish = await factory.create(const StockfishSpec.light());
      addTearDown(stockfish.dispose);
      final lc0 = await factory.create(const Lc0Spec());
      addTearDown(lc0.dispose);
      await pumpEventQueue();

      expect(engine.sessions, hasLength(2));
      expect(engine.quitCount, 0, reason: 'neither is quit to make room');

      // Each engine read its own handshake, from its own session.
      expect(stockfish.name.value, 'Stockfish 19');
      expect(lc0.name.value, 'Lc0 v0.32.1');

      // And each search is answered by the engine it was given to.
      final stockfishSearch = stockfish.search(makeRequest());
      final lc0Search = lc0.search(makeRequest());
      await pumpEventQueue();
      engine.sessions[0].emit('readyok');
      engine.sessions[1].emit('readyok');
      await pumpEventQueue();

      engine.sessions[0].emit('bestmove e2e4');
      engine.sessions[1].emit('bestmove d2d4');

      expect(await stockfishSearch.bestMove, 'e2e4');
      expect(await lc0Search.bestMove, 'd2d4');
    });
  });
}
