import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:path_provider/path_provider.dart';

final xiangqiOtbGameStorageProvider = Provider<XiangqiOtbGameStorage>(
  (Ref ref) => const XiangqiOtbGameStorage(),
  name: 'XiangqiOtbGameStorageProvider',
);

const kXiangqiOtbGameFileName = 'xiangqi_otb_game.json';

/// The xiangqi over-the-board game stored between visits.
///
/// The encoded game is the same value the computer game already stores; only the file name differs,
/// so a game against Pikafish and a game with two people at the board cannot overwrite one another.
class const XiangqiOtbGameStorage() {
  Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$kXiangqiOtbGameFileName');
  }

  Future<SavedXiangqiGame?> fetchGame() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return SavedXiangqiGame.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> save(SavedXiangqiGame game) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(game.toJson()));
    } on Object {
      // A game in progress is still playable when persistence is unavailable; the next move tries
      // again rather than taking the board down with a filesystem error.
    }
  }

  Future<void> delete() async {
    final file = await _getFile();
    if (await file.exists()) await file.delete();
  }
}
