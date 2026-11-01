import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_clock.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_otb_game_storage.dart';
import 'package:material_ui/material_ui.dart';

/// One local route owns one game and clock. The engine itself remains inherited/shared; its
/// opponent, evaluation and hint requests remain separately owned Search instances.
class const XiangqiLocalGameScope({
  required final Widget child,
  final bool transient = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<XiangqiLocalGameScope> createState() => _XiangqiLocalGameScopeState();
}

class _XiangqiLocalGameScopeState() extends State<XiangqiLocalGameScope> {
  // Overrides stay stable across a theme, text-scale or locale change.
  late final _overrides = [
    xiangqiGameControllerProvider.overrideWith(XiangqiGameController.new),
    xiangqiClockProvider.overrideWith(XiangqiClock.new),
    xiangqiEngineAnalysisProvider.overrideWith(XiangqiEngineAnalysis.new),
    if (widget.transient) ...[
      xiangqiGameStorageProvider.overrideWith((_) => _TransientComputerStorage()),
      xiangqiOtbGameStorageProvider.overrideWith((_) => _TransientOtbStorage()),
    ],
  ];

  @override
  Widget build(BuildContext context) => ProviderScope(overrides: _overrides, child: widget.child);
}

// Continuing an analysis opens an auxiliary route, not the primary game's save slot. Its own
// save/restore calls remain functional within this route without overwriting the hidden parent.
class _TransientComputerStorage() extends XiangqiGameStorage {
  SavedXiangqiGame? _saved;
  @override
  Future<SavedXiangqiGame?> fetchGame() async => _saved;
  @override
  Future<void> save(SavedXiangqiGame game) async {
    _saved = game;
  }

  @override
  Future<void> delete() async {
    _saved = null;
  }
}

class _TransientOtbStorage() extends XiangqiOtbGameStorage {
  SavedXiangqiGame? _saved;
  @override
  Future<SavedXiangqiGame?> fetchGame() async => _saved;
  @override
  Future<void> save(SavedXiangqiGame game) async {
    _saved = game;
  }

  @override
  Future<void> delete() async {
    _saved = null;
  }
}
