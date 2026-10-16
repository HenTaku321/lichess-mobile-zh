import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'xiangqi_saved.freezed.dart';

/// The two kinds of thing the folder tree holds.
///
/// The two spellings are the server's own and **neither is derivable from the other**: the URL a
/// folder is filed under uses [wireSlug] (`puzzle`, `game_note`) and the body that creates one uses
/// [itemType] (`2`, `3`). The shipped client's own map spells the second slug `note`, which the
/// server answers `400 Invalid item type` — see `xiangqi-com-re/docs/saved.md`.
enum XiangqiSavedKind(final String wireSlug, final int itemType) {
  /// The puzzles this account has created.
  puzzle('puzzle', 2),

  /// The game notes this account has saved.
  note('game_note', 3),
}

/// One folder of the tree, from `GET /api/items/folders/<user>/<slug>/`.
@freezed
sealed class const XiangqiSavedFolder._() with _$XiangqiSavedFolder {
  const factory({
    required String id,
    required String name,

    /// Which kind of content the folder holds, as the server numbers it.
    required int itemType,

    /// The folder this one sits in, or null when it is at the root.
    String? parentId,

    /// Whether this is a folder at the root of the tree.
    required bool isRoot,
  }) = _XiangqiSavedFolder;
}

/// A page of folders.
@freezed
sealed class const XiangqiSavedFolders._() with _$XiangqiSavedFolders {
  const factory({
    required IList<XiangqiSavedFolder> folders,

    /// The trail from the root to the folder being listed, as the server sends it.
    ///
    /// **Kept as it arrived, and not drawn.** The field is this endpoint's own — no other list on
    /// the site has it — and it was `null` on every read this project could make, so what it holds
    /// is not pinned. Keeping it whole is the honest thing to do with a shape nobody has seen: a
    /// reader that guessed at it would be inventing a trail.
    Object? breadcrumbs,
    required int totalPages,
    int? nextPage,
  }) = _XiangqiSavedFolders;
}

/// One puzzle this account has created, from `GET /api/puzzle/puzzles/<user>`.
@freezed
sealed class const XiangqiSavedPuzzle._() with _$XiangqiSavedPuzzle {
  const factory({
    required String id,

    /// The theme the puzzle is filed under, as the server numbers it: `1` is a mate and `2` a
    /// tactic — see `xiangqi-com-re/docs/puzzle.md`.
    int? theme,

    /// The puzzle's own rating, or null when it has none yet.
    int? rating,

    /// When it was made, as the server spells it, or null.
    String? createdOn,
  }) = _XiangqiSavedPuzzle;
}

/// One game note this account has saved, from `GET /api/game-note/game-notes/<user>`.
///
/// **The item shape is inferred, not measured.** Every read of this endpoint this project could make
/// answered with an empty list — the one account has saved no notes — so the fields here are the
/// ones the site's own note objects carry everywhere else they appear, and every one of them is
/// optional. See `xiangqi-com-re/docs/saved.md`.
@freezed
sealed class const XiangqiSavedNote._() with _$XiangqiSavedNote {
  const factory({
    /// The note's id, or null when the payload did not carry one this app could read.
    String? id,
    String? title,
    String? description,
    String? createdOn,
  }) = _XiangqiSavedNote;
}

/// A page of saved puzzles.
@freezed
sealed class const XiangqiSavedPuzzles._() with _$XiangqiSavedPuzzles {
  const factory({
    required IList<XiangqiSavedPuzzle> puzzles,
    required int totalPages,
    int? nextPage,
  }) = _XiangqiSavedPuzzles;
}

/// A page of saved notes.
@freezed
sealed class const XiangqiSavedNotes._() with _$XiangqiSavedNotes {
  const factory({required IList<XiangqiSavedNote> notes, required int totalPages, int? nextPage}) =
      _XiangqiSavedNotes;
}

/// The folders of a `items/folders/<user>/<slug>/` body.
XiangqiSavedFolders xiangqiSavedFoldersFromJson(Object? json) {
  final map = _map(json);
  final folders = <XiangqiSavedFolder>[];
  final rows = map?['items'];
  if (rows is List) {
    for (final row in rows) {
      final entry = _map(row);
      if (entry == null) continue;
      final id = _string(entry['encrypted_id']);
      final name = _string(entry['name']);
      if (id == null || name == null) continue;
      folders.add(
        XiangqiSavedFolder(
          id: id,
          name: name,
          itemType: _int(entry['item_type']) ?? 0,
          parentId: _string(entry['parent_encrypted_id']),
          isRoot: entry['is_root'] == true,
        ),
      );
    }
  }
  return XiangqiSavedFolders(
    folders: folders.lock,
    breadcrumbs: map?['breadcrumbs'],
    totalPages: _int(map?['total_pages']) ?? 0,
    nextPage: _int(map?['next_page_num']),
  );
}

/// The puzzles of a `puzzle/puzzles/<user>` body.
XiangqiSavedPuzzles xiangqiSavedPuzzlesFromJson(Object? json) {
  final map = _map(json);
  final puzzles = <XiangqiSavedPuzzle>[];
  final rows = map?['items'];
  if (rows is List) {
    for (final row in rows) {
      final entry = _map(row);
      if (entry == null) continue;
      final id = _string(entry['puzzle_id']);
      if (id == null) continue;
      puzzles.add(
        XiangqiSavedPuzzle(
          id: id,
          theme: _int(entry['theme']),
          rating: _int(entry['p_rating']),
          createdOn: _string(entry['created_on']),
        ),
      );
    }
  }
  return XiangqiSavedPuzzles(
    puzzles: puzzles.lock,
    totalPages: _int(map?['total_pages']) ?? 0,
    nextPage: _int(map?['next_page_num']),
  );
}

/// The notes of a `game-note/game-notes/<user>` body.
XiangqiSavedNotes xiangqiSavedNotesFromJson(Object? json) {
  final map = _map(json);
  final notes = <XiangqiSavedNote>[];
  final rows = map?['items'];
  if (rows is List) {
    for (final row in rows) {
      final entry = _map(row);
      if (entry == null) continue;
      notes.add(
        XiangqiSavedNote(
          id: _string(entry['encrypted_id']) ?? _string(entry['id']),
          title: _string(entry['title']) ?? _string(entry['name']),
          description: _string(entry['description']),
          createdOn: _string(entry['created_on']),
        ),
      );
    }
  }
  return XiangqiSavedNotes(
    notes: notes.lock,
    totalPages: _int(map?['total_pages']) ?? 0,
    nextPage: _int(map?['next_page_num']),
  );
}

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;
