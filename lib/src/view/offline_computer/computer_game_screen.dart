import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:lichess_mobile/src/model/offline_computer/xiangqi_computer_setup.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:material_ui/material_ui.dart';

/// The one computer-game entry.
///
/// The chess and xiangqi screens replace each other inside this single route. Switching games is
/// therefore not navigation: the route beneath stays the screen the reader entered from, and the
/// system back button leaves the computer game altogether rather than landing on the other board.
class const ComputerGameScreen() extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const ComputerGameScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xiangqi = ref.watch(
      offlineComputerGamePreferencesProvider.select((p) => p.lastGameWasXiangqi),
    );
    final setup = ref.watch(pendingXiangqiComputerSetupProvider);

    if (!xiangqi) return const OfflineComputerGameScreen();
    if (setup == null) return const XiangqiGameScreen();
    return XiangqiGameScreen(
      initialSide: setup.side,
      initialDifficulty: setup.difficulty,
      initialTimeIncrement: setup.timeIncrement,
      initialPracticeMode: setup.practiceMode,
    );
  }
}
