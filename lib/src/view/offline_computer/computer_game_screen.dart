import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:material_ui/material_ui.dart';

/// The one computer-game entry, opening whichever game was played last.
///
/// The engine picker inside each game can switch to the other one; this wrapper only chooses the
/// screen for the next visit, so a saved xiangqi game survives the same way a chess game does.
class const ComputerGameScreen() extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const ComputerGameScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xiangqi = ref.watch(
      offlineComputerGamePreferencesProvider.select((p) => p.lastGameWasXiangqi),
    );
    return xiangqi ? const XiangqiGameScreen() : const OfflineComputerGameScreen();
  }
}
