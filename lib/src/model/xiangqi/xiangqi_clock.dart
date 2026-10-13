import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

part 'xiangqi_clock.freezed.dart';

/// The time control a xiangqi game over the board starts on.
///
/// A constant rather than a preference, because there is no xiangqi clock preference and this wave
/// adds none: the over-the-board screen puts the choice in its setup sheet, and this is only what the
/// clock holds before that sheet has been answered. Five minutes with a three-second increment is the
/// shape of the chess game's own default, which is the only reason it is this and not something else.
const kXiangqiDefaultTimeIncrement = TimeIncrement(300, 3);

/// The clock of a xiangqi game played on this device, over the board.
///
/// A parallel of [LocalGameClock] rather than a use of it, and typed on [XiangqiSide] rather than on
/// dartchess's `Side`. The two machines are the same — one side's time runs at a time, a 100 ms tick
/// charges the time run to it, the increment goes to the side that just moved, and a side whose time
/// reaches zero has flagged — but the chess clock is indexed by a `Side` xiangqi has no business
/// with: a xiangqi position speaks red and black, and its moves are not dartchess moves. Making the
/// chess clock generic over its side would change a shared model file for one caller's sake, which is
/// the opposite of what this wave is for, so this is the same thing written again on the names the
/// game actually uses.
///
/// Unlike the chess clock there is no abstract base under it: [LocalGameClock] is split that way
/// because one clock is shared by two screens that each want a different default time control, while
/// this one has a single caller and a single default.
class XiangqiClock() extends Notifier<XiangqiClockState> {
  final Stopwatch _stopwatch = Stopwatch();

  Timer? _updateTimer;

  /// The time control the clock starts on, before any game has set it up.
  static const defaultTimeIncrement = kXiangqiDefaultTimeIncrement;

  @override
  XiangqiClockState build() {
    ref.onDispose(() {
      _updateTimer?.cancel();
    });

    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _flushElapsed());

    return XiangqiClockState.fromTimeIncrement(defaultTimeIncrement);
  }

  /// Charges the time run since the last reading to the side whose clock is running.
  ///
  /// Called on every tick, but also whenever the clock is about to stop or change hands, so that the
  /// fraction of a tick that has run since the last one is not silently given back.
  void _flushElapsed() {
    final activeClock = state.activeClock;
    if (!_stopwatch.isRunning || activeClock == null) return;

    final newTime = state.timeLeft(activeClock)! - _stopwatch.elapsed;
    _stopwatch.reset();

    state = activeClock == .red
        ? state.copyWith(redTimeLeft: newTime)
        : state.copyWith(blackTimeLeft: newTime);

    if (newTime <= Duration.zero) {
      state = state.copyWith(flagSide: activeClock);
    }
  }

  void setupClock(TimeIncrement timeIncrement, {Duration? redTimeLeft, Duration? blackTimeLeft}) {
    _stopwatch.stop();
    _stopwatch.reset();

    state = XiangqiClockState.fromTimeIncrement(
      timeIncrement,
      redTimeLeft: redTimeLeft,
      blackTimeLeft: blackTimeLeft,
    );
  }

  void restart() {
    setupClock(state.timeIncrement);
  }

  void switchSide({required XiangqiSide newSideToMove, required bool addIncrement}) {
    if (state.timeIncrement.isInfinite || state.flagSide != null) return;

    _flushElapsed();
    // Flushing can be what reveals that the side to move has just run out of time.
    if (state.flagSide != null) return;

    final increment = Duration(seconds: addIncrement ? state.timeIncrement.increment : 0);
    state = newSideToMove == .black
        ? state.copyWith(redTimeLeft: state.redTimeLeft! + increment, activeClock: .black)
        : state.copyWith(blackTimeLeft: state.blackTimeLeft! + increment, activeClock: .red);

    _stopwatch.reset();
    _stopwatch.start();
  }

  void onMove({required XiangqiSide newSideToMove}) {
    switchSide(newSideToMove: newSideToMove, addIncrement: state.active);
  }

  void pause() {
    if (_stopwatch.isRunning) {
      _flushElapsed();
      _stopwatch.stop();
      state = state.copyWith(activeClock: null);
    }
  }

  void resume(XiangqiSide newSideToMove) {
    _stopwatch.reset();
    _stopwatch.start();

    state = state.copyWith(activeClock: newSideToMove);
  }
}

final xiangqiClockProvider = NotifierProvider.autoDispose<XiangqiClock, XiangqiClockState>(
  XiangqiClock.new,
  name: 'XiangqiClockProvider',
);

/// The state of a xiangqi clock: what each side has left, whose time is running, and who has flagged.
///
/// Held as red and black rather than as a map so that the common question — how much has one side
/// left — is a field read, and so that it is obvious in the type that there are exactly two sides.
@freezed
sealed class const XiangqiClockState._() with _$XiangqiClockState {
  const factory({
    required TimeIncrement timeIncrement,
    required Duration? redTimeLeft,
    required Duration? blackTimeLeft,
    required XiangqiSide? activeClock,
    required XiangqiSide? flagSide,
  }) = _XiangqiClockState;

  /// A clock on [timeIncrement], both sides holding [timeIncrement]'s time unless told otherwise.
  ///
  /// [redTimeLeft] and [blackTimeLeft] are only for a clock restored to a game already in progress,
  /// which nothing does yet; the nulls are the ordinary case, not a missing value. An unlimited
  /// control has no time to hold at all, and both fields are null.
  factory fromTimeIncrement(
    TimeIncrement timeIncrement, {
    Duration? redTimeLeft,
    Duration? blackTimeLeft,
  }) {
    final initialTime = timeIncrement.isInfinite
        ? null
        : Duration(seconds: max(timeIncrement.time, timeIncrement.increment));

    return XiangqiClockState(
      timeIncrement: timeIncrement,
      redTimeLeft: redTimeLeft ?? initialTime,
      blackTimeLeft: blackTimeLeft ?? initialTime,
      activeClock: null,
      flagSide: null,
    );
  }

  /// Whether the clock has been started — or has already finished, since a flagged clock is one that
  /// ran.
  bool get active => activeClock != null || flagSide != null;

  Duration? timeLeft(XiangqiSide side) => side == .red ? redTimeLeft : blackTimeLeft;
}
