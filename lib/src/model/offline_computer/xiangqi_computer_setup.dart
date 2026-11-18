import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// A xiangqi computer game chosen in the unified computer-game setup.
///
/// This is deliberately a one-shot handoff rather than a saved preference: it describes the game
/// the reader has just asked to start. Once the xiangqi screen consumes it, the saved-game storage
/// is again the only thing that decides what opens next time.
final class const XiangqiComputerSetup({
  required final XiangqiSide side,
  required final XiangqiDifficulty difficulty,
  required final TimeIncrement timeIncrement,
  required final bool practiceMode,
});
