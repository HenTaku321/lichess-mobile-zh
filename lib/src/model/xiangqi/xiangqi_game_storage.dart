import 'dart:convert';
import 'dart:io';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _logger = Logger('XiangqiGameStorage');

final xiangqiGameStorageProvider = Provider<XiangqiGameStorage>((Ref ref) {
  return const XiangqiGameStorage();
}, name: 'XiangqiGameStorageProvider');

const kXiangqiGameFileName = 'xiangqi_computer_game.json';

/// A xiangqi computer game as it survives a trip to disk.
final class const SavedXiangqiGame({
  required final XiangqiGameState state,
  required final TimeIncrement timeIncrement,
  final Duration? redTimeLeft,
  final Duration? blackTimeLeft,
}) {
  Map<String, dynamic> toJson() => {
    'playerSide': state.playerSide.name,
    'difficulty': state.difficulty.name,
    'opponent': state.opponent.name,
    'positions': [for (final position in state.positions) position.toFen()],
    'moves': [for (final move in state.moves) move.iccs],
    'resignedBy': state.resignedBy?.name,
    'flaggedSide': state.flaggedSide?.name,
    'timeIncrement': {'time': timeIncrement.time, 'increment': timeIncrement.increment},
    'practiceMode': state.practiceMode,
    'redTimeLeftMs': redTimeLeft?.inMilliseconds,
    'blackTimeLeftMs': blackTimeLeft?.inMilliseconds,
  };

  static SavedXiangqiGame? fromJson(Map<String, dynamic> json) {
    try {
      final positions = (json['positions'] as List)
          .whereType<String>()
          .map(XiangqiPosition.fromFen)
          .toList();
      final moves = (json['moves'] as List)
          .whereType<String>()
          .map(XiangqiMove.parseIccs)
          .whereType<XiangqiMove>()
          .toList();
      if (positions.isEmpty) return null;
      final increment = json['timeIncrement'] as Map<String, dynamic>;
      final red = json['redTimeLeftMs'];
      final black = json['blackTimeLeftMs'];
      return SavedXiangqiGame(
        state: XiangqiGameState(
          playerSide: XiangqiSide.values.byName(json['playerSide'] as String),
          difficulty: XiangqiDifficulty.values.byName(json['difficulty'] as String),
          opponent: XiangqiOpponent.values.byName(json['opponent'] as String),
          positions: positions.lock,
          moves: moves.lock,
          resignedBy: json['resignedBy'] == null
              ? null
              : XiangqiSide.values.byName(json['resignedBy'] as String),
          flaggedSide: json['flaggedSide'] == null
              ? null
              : XiangqiSide.values.byName(json['flaggedSide'] as String),
          timeIncrement: TimeIncrement(
            (increment['time'] as num).toInt(),
            (increment['increment'] as num).toInt(),
          ),
          practiceMode: json['practiceMode'] == true,
        ),
        timeIncrement: TimeIncrement(
          (increment['time'] as num).toInt(),
          (increment['increment'] as num).toInt(),
        ),
        redTimeLeft: red is num ? Duration(milliseconds: red.toInt()) : null,
        blackTimeLeft: black is num ? Duration(milliseconds: black.toInt()) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

class const XiangqiGameStorage() {
  Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$kXiangqiGameFileName');
  }

  Future<SavedXiangqiGame?> fetchGame() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return SavedXiangqiGame.fromJson(json);
    } catch (error, stackTrace) {
      _logger.warning('Failed to fetch xiangqi game', error, stackTrace);
      return null;
    }
  }

  Future<void> save(SavedXiangqiGame game) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(game.toJson()));
    } catch (error, stackTrace) {
      _logger.warning('Failed to save xiangqi game', error, stackTrace);
    }
  }

  Future<void> delete() async {
    try {
      final file = await _getFile();
      if (await file.exists()) await file.delete();
    } catch (error, stackTrace) {
      _logger.warning('Failed to delete xiangqi game', error, stackTrace);
    }
  }
}
