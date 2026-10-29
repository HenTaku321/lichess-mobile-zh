import 'dart:convert';
import 'dart:io';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _logger = Logger('XiangqiGameStorage');

final xiangqiGameStorageProvider = Provider<XiangqiGameStorage>((Ref ref) {
  return XiangqiGameStorage();
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
    'practiceComments': [
      for (final entry in state.practiceComments.entries)
        {
          'ply': entry.key,
          'verdict': entry.value.verdict.name,
          'bestMove': entry.value.bestMove?.iccs,
          'cp': entry.value.evaluation?.cp,
          'mate': entry.value.evaluation?.mate,
        },
    ],
    'redTimeLeftMs': redTimeLeft?.inMilliseconds,
    'blackTimeLeftMs': blackTimeLeft?.inMilliseconds,
  };

  static SavedXiangqiGame? fromJson(Map<String, dynamic> json) {
    try {
      final positions = (json['positions'] as List)
          .map((fen) => XiangqiPosition.fromFen(fen as String))
          .toList();
      final moves = (json['moves'] as List)
          .map((move) => XiangqiMove.parseIccs(move as String)!)
          .toList();
      if (positions.isEmpty || positions.length != moves.length + 1) return null;
      for (var i = 0; i < moves.length; i++) {
        if (!rules.isLegal(positions[i], moves[i]) ||
            rules.play(positions[i], moves[i]) != positions[i + 1])
          return null;
      }
      final playerSide = XiangqiSide.values.byName(json['playerSide'] as String);
      final comments = <int, XiangqiPracticeComment>{};
      if (json['practiceComments'] case final List entries) {
        for (final entry in entries) {
          if (entry is! Map<String, dynamic>) continue;
          try {
            final ply = entry['ply'] as int;
            if (ply <= 0 || ply > moves.length || positions[ply - 1].turn != playerSide) continue;
            final cp = entry['cp'] as int?;
            final mate = entry['mate'] as int?;
            if ((cp == null) == (mate == null)) continue;
            final best = entry['bestMove'];
            final move = best == null ? null : XiangqiMove.parseIccs(best as String);
            if (best != null && (move == null || !rules.isLegal(positions[ply - 1], move)))
              continue;
            comments[ply] = XiangqiPracticeComment(
              verdict: MoveVerdict.values.byName(entry['verdict'] as String),
              bestMove: move,
              evaluation: XiangqiEvaluation(cp: cp, mate: mate),
              suggestionNotation: move == null
                  ? null
                  : xiangqiMoveNotation(positions[ply - 1], move),
              evalAfter: ExternalEval(cp: cp, mate: mate).evalString,
            );
          } on Object catch (_) {
            // Optional feedback may be corrupt without invalidating the legal game history.
            continue;
          }
        }
      }
      final increment = json['timeIncrement'] as Map<String, dynamic>;
      final red = json['redTimeLeftMs'];
      final black = json['blackTimeLeftMs'];
      return SavedXiangqiGame(
        state: XiangqiGameState(
          playerSide: playerSide,
          difficulty: XiangqiDifficulty.values.byName(json['difficulty'] as String),
          opponent: XiangqiOpponent.values.byName(json['opponent'] as String? ?? 'engine'),
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
          practiceComments: IMap(comments),
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

class XiangqiGameStorage() {
  Future<void> _pending = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    // A failed operation must not poison the queue for a subsequent save or deletion.
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning('Xiangqi storage operation failed', error, stackTrace);
      },
    );
    return result;
  }

  Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$kXiangqiGameFileName');
  }

  Future<SavedXiangqiGame?> fetchGame() => _enqueue(() async {
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
  });

  Future<void> save(SavedXiangqiGame game) {
    final contents = jsonEncode(game.toJson());
    return _enqueue(() async {
      File? temporary;
      try {
        final file = await _getFile();
        await file.parent.create(recursive: true);
        temporary = File('${file.path}.tmp');
        await temporary.writeAsString(contents, flush: true);
        await temporary.rename(file.path);
      } catch (error, stackTrace) {
        _logger.warning('Failed to save xiangqi game', error, stackTrace);
        try {
          if (temporary != null && await temporary.exists()) await temporary.delete();
        } catch (error, stackTrace) {
          _logger.warning('Failed to remove temporary xiangqi game', error, stackTrace);
        }
      }
    });
  }

  Future<void> delete() => _enqueue(() async {
    try {
      final file = await _getFile();
      if (await file.exists()) await file.delete();
    } catch (error, stackTrace) {
      _logger.warning('Failed to delete xiangqi game', error, stackTrace);
    }
  });
}
