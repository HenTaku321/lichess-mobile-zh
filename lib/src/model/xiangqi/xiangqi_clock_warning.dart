/// The same initial-control threshold as the local Lichess clocks.
Duration xiangqiEmergencyThreshold(int initialSeconds) =>
    Duration(seconds: (initialSeconds * 0.125).clamp(10, 60).toInt());

/// One warning per low-time crossing, with the ChessClock cooldown and hysteresis.
class XiangqiLowTimeWarning() {
  bool _armed = true;
  DateTime? _next;

  bool shouldNotify({
    required Duration timeLeft,
    required Duration threshold,
    required DateTime now,
    required bool active,
  }) {
    if (timeLeft > threshold * 1.5) {
      _armed = true;
    }
    if (!active ||
        timeLeft <= Duration.zero ||
        timeLeft > threshold ||
        !_armed ||
        (_next != null && now.isBefore(_next!))) {
      return false;
    }
    _armed = false;
    _next = now.add(const Duration(seconds: 20));
    return true;
  }
}
