import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/game_family.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:lichess_mobile/src/model/offline_computer/xiangqi_computer_setup.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Both computer boards share this route. A family link opens that family's save slot. The
/// generic Play entry uses the last family. An opponent picked here belongs only to this route.
class const ComputerGameScreen({final GameFamily? initialFamily, super.key})
    extends ConsumerStatefulWidget {
  static Route<void> buildRoute({GameFamily? family}) =>
      buildScreenRoute(screen: ComputerGameScreen(initialFamily: family));

  @override
  ConsumerState<ComputerGameScreen> createState() => _ComputerGameScreenState();
}

class _ComputerGameScreenState() extends ConsumerState<ComputerGameScreen> {
  late GameFamily _family;
  XiangqiComputerSetup? _setup;

  @override
  void initState() {
    super.initState();
    final previous = ref.read(offlineComputerGamePreferencesProvider).lastGameWasXiangqi;
    _family = widget.initialFamily ?? (previous ? GameFamily.xiangqi : GameFamily.chess);
    if (_family.isXiangqi != previous) _rememberFamily();
  }

  void _rememberFamily() => unawaited(
    ref
        .read(offlineComputerGamePreferencesProvider.notifier)
        .setLastGameWasXiangqi(_family.isXiangqi),
  );

  void _switch(GameFamily family, [XiangqiComputerSetup? setup]) {
    setState(() {
      _family = family;
      _setup = setup;
    });
    _rememberFamily();
  }

  @override
  Widget build(BuildContext context) => switch (_family) {
    GameFamily.chess => OfflineComputerGameScreen(
      onStartXiangqi: (setup) => _switch(.xiangqi, setup),
    ),
    GameFamily.xiangqi => XiangqiGameScreen.withOwnSession(
      XiangqiGameScreen(
        onSwitchToChess: () => _switch(.chess),
        initialSide: _setup?.side,
        initialDifficulty: _setup?.difficulty,
        initialTimeIncrement: _setup?.timeIncrement,
        initialPracticeMode: _setup?.practiceMode ?? false,
      ),
    ),
  };
}
