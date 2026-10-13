import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// A container with the clock in it and nothing else: the clock is the whole of what is under test,
/// so nothing is put beside it.
///
/// The clock is watched rather than read once, because it is an `autoDispose` provider and a bare
/// `read` is not a watcher: without something holding it, the clock would be thrown away between two
/// lines of a test and would be a new clock — with a new stopwatch — by the time the next one ran.
ProviderContainer makeContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final watched = container.listen(xiangqiClockProvider, (_, _) {});
  addTearDown(watched.close);
  return container;
}

XiangqiClock clockOf(ProviderContainer container) => container.read(xiangqiClockProvider.notifier);

XiangqiClockState stateOf(ProviderContainer container) => container.read(xiangqiClockProvider);

/// How many times the clock has begun to flag, which is a different question from whether it is
/// flagged: the flag is a fact that stays in the state, and the state is written on every tick.
///
/// An object rather than a returned `int`, because the answer is not known when the count starts:
/// every flag in this file is announced on the clock's own timer, after the call that asked for it,
/// so what a test holds has to be something the listener is still able to write to.
class FlagCounter() {
  int count = 0;
}

FlagCounter countFlags(ProviderContainer container) {
  final counter = FlagCounter();
  final subscription = container.listen(xiangqiClockProvider.select((c) => c.flagSide), (
    previous,
    flagSide,
  ) {
    if (previous == null && flagSide != null) counter.count++;
  });
  addTearDown(subscription.close);
  return counter;
}

/// How much time the clock may have charged between two calls that are adjacent in a test.
///
/// The clock reads a real stopwatch, and a test that hands the clock over between two synchronous
/// calls still spends microseconds doing it. A tick of the clock's own timer is the widest that
/// slop can plausibly be, so it is the slack the range assertions are written with.
const _aTick = Duration(milliseconds: 100);

void main() {
  group('XiangqiClock', () {
    test('the clock starts on the first move, and the increment goes to the side that moved', () {
      final container = makeContainer();
      final clock = clockOf(container);

      clock.setupClock(const TimeIncrement(60, 3));

      // Setting the clock up is not starting it: nothing runs until a move has been made, which is
      // the same hand the chess clock over the board starts on.
      expect(stateOf(container).activeClock, isNull);
      expect(stateOf(container).active, isFalse);
      expect(stateOf(container).timeLeft(XiangqiSide.red), const Duration(seconds: 60));
      expect(stateOf(container).timeLeft(XiangqiSide.black), const Duration(seconds: 60));

      // Red's first move: black's time starts, and red has earned nothing, since the increment is
      // paid for a move that was made with time already running.
      clock.onMove(newSideToMove: XiangqiSide.black);
      expect(stateOf(container).activeClock, XiangqiSide.black);
      expect(stateOf(container).timeLeft(XiangqiSide.red), const Duration(seconds: 60));

      // Black's answer: the clock goes back to red, and black is paid the three seconds. Black's time
      // is three seconds richer and a hair poorer, the hair being the microseconds the clock ran
      // between the two calls, so the assertion is a range rather than an exact number.
      clock.onMove(newSideToMove: XiangqiSide.red);
      expect(stateOf(container).activeClock, XiangqiSide.red);
      final blackTimeLeft = stateOf(container).timeLeft(XiangqiSide.black)!;
      expect(blackTimeLeft, greaterThanOrEqualTo(const Duration(seconds: 63) - _aTick));
      expect(blackTimeLeft, lessThanOrEqualTo(const Duration(seconds: 63)));
      expect(stateOf(container).timeLeft(XiangqiSide.red), const Duration(seconds: 60));
    });

    test('a paused clock charges nothing, and a resumed one charges again', () async {
      final container = makeContainer();
      final clock = clockOf(container);

      clock.setupClock(const TimeIncrement(60, 0));
      clock.resume(XiangqiSide.red);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      clock.pause();

      final afterRunning = stateOf(container).timeLeft(XiangqiSide.red)!;
      expect(afterRunning, lessThan(const Duration(seconds: 60)));
      expect(stateOf(container).activeClock, isNull);

      // The tick timer keeps running while the clock is paused — it is the clock's whole life — and
      // what stops time being charged is the stopwatch being stopped, not the timer being cancelled.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        stateOf(container).timeLeft(XiangqiSide.red),
        afterRunning,
        reason: 'a paused clock charges nothing',
      );

      clock.resume(XiangqiSide.red);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(stateOf(container).timeLeft(XiangqiSide.red), lessThan(afterRunning));
    });

    test('a side whose time runs out flags, and the clock does not move on', () async {
      final container = makeContainer();
      final clock = clockOf(container);
      final flags = countFlags(container);

      // A clock that starts at nothing, so that the flag is the first tick away rather than a minute
      // of a test's own time spent waiting for one. Red has the move.
      clock.setupClock(const TimeIncrement(1, 0), redTimeLeft: Duration.zero);
      clock.resume(XiangqiSide.red);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(stateOf(container).flagSide, XiangqiSide.red);
      expect(stateOf(container).timeLeft(XiangqiSide.red)! <= Duration.zero, isTrue);

      // The flag is announced once. Every later tick writes the state again — the time keeps running
      // past zero, in the arithmetic — and what keeps that from being a second flag is that the side
      // it names is the one already in the state.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(flags.count, 1, reason: 'a clock that has run out has run out once');
      expect(stateOf(container).flagSide, XiangqiSide.red);

      // A move and a flag can land in the same frame, and the side that lost is the side whose clock
      // it was. Nothing hands the clock over once it has run out.
      clock.onMove(newSideToMove: XiangqiSide.black);
      expect(stateOf(container).flagSide, XiangqiSide.red);
      expect(stateOf(container).activeClock, XiangqiSide.red);
      expect(stateOf(container).timeLeft(XiangqiSide.black), const Duration(seconds: 1));
    });

    test('an unlimited control has no time to run out', () {
      final container = makeContainer();
      final clock = clockOf(container);

      clock.setupClock(const TimeIncrement.infinite());

      expect(stateOf(container).timeIncrement.isInfinite, isTrue);
      // No time is held at all, rather than a very large amount of it: nothing is drawn for a field
      // that has no time in it, and nothing can reach zero either.
      expect(stateOf(container).timeLeft(XiangqiSide.red), isNull);
      expect(stateOf(container).timeLeft(XiangqiSide.black), isNull);

      clock.onMove(newSideToMove: XiangqiSide.black);
      expect(stateOf(container).activeClock, isNull, reason: 'there is no time to be running');
      expect(stateOf(container).active, isFalse);
    });

    test('restart puts both sides back on the time control the clock was given', () {
      final container = makeContainer();
      final clock = clockOf(container);

      clock.setupClock(const TimeIncrement(60, 3), redTimeLeft: const Duration(seconds: 10));
      expect(stateOf(container).timeLeft(XiangqiSide.red), const Duration(seconds: 10));
      expect(stateOf(container).timeLeft(XiangqiSide.black), const Duration(seconds: 60));

      clock.restart();

      // Both sides, and the side with less time is not the one that decides: a restarted clock is a
      // clock of the same control with nobody having moved.
      expect(stateOf(container).timeLeft(XiangqiSide.red), const Duration(seconds: 60));
      expect(stateOf(container).timeLeft(XiangqiSide.black), const Duration(seconds: 60));
      expect(stateOf(container).flagSide, isNull);
      expect(stateOf(container).activeClock, isNull);
      expect(stateOf(container).active, isFalse);
    });
  });
}
