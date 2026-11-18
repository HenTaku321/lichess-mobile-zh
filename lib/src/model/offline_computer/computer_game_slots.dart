import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/game_family.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';

/// The home screen reads the same save slots and eligibility checks as the game screens.
/// A finished game still identifies a returning player.
enum ComputerSlotStatus() {
  empty,
  resumable,
  finished,
}

final computerGameSlotProvider = FutureProvider.autoDispose.family<ComputerSlotStatus, GameFamily>((
  ref,
  family,
) async {
  final canResume = switch (family) {
    GameFamily.chess =>
      (await ref.watch(offlineComputerGameStorageProvider).fetchGame())?.canResume,
    GameFamily.xiangqi => (await ref.watch(xiangqiGameStorageProvider).fetchGame())?.canResume,
  };
  return switch (canResume) {
    true => ComputerSlotStatus.resumable,
    false => ComputerSlotStatus.finished,
    null => ComputerSlotStatus.empty,
  };
}, name: 'ComputerGameSlotProvider');
