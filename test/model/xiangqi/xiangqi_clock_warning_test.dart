import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock_warning.dart';

void main() {
  test('clock threshold follows the initial control and clamps at ten and sixty seconds', () {
    expect(xiangqiEmergencyThreshold(15), const Duration(seconds: 10));
    expect(xiangqiEmergencyThreshold(300), const Duration(seconds: 37));
    expect(xiangqiEmergencyThreshold(3600), const Duration(seconds: 60));
  });

  test('low time is emitted once per crossing, with cooldown and hysteresis', () {
    final warning = XiangqiLowTimeWarning();
    final now = DateTime.utc(2026);
    const threshold = Duration(seconds: 20);
    bool check(int seconds, int elapsed, {bool active = true}) => warning.shouldNotify(
      timeLeft: Duration(seconds: seconds),
      threshold: threshold,
      now: now.add(Duration(seconds: elapsed)),
      active: active,
    );
    expect(check(19, 0, active: false), isFalse);
    expect(check(19, 0), isTrue);
    expect(check(18, 30), isFalse);
    expect(check(31, 31), isFalse);
    expect(check(19, 32), isTrue);
    expect(check(31, 33), isFalse);
    expect(check(19, 34), isFalse);
    expect(check(19, 52), isTrue);
  });
}
