// Tests for reading the account's own content library.
//
// The folder shapes are the ones the 2026-10-16 probe measured — see
// `xiangqi-com-re/docs/saved.md` — with every value replaced. The note item shape is **not**
// measured: every read of that endpoint answered with an empty list, so what is pinned here is that
// the reader takes the fields the site's own note objects carry and drops what it cannot place,
// rather than that it reads a shape somebody saw.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/saved/xiangqi_saved.dart';

/// A page envelope, which every list in this domain uses.
Map<String, Object?> page(List<Map<String, Object?>> items, {int? nextPage, int totalPages = 3}) =>
    {
      'items': items,
      'breadcrumbs': null,
      'total_pages': totalPages,
      'next_page_num': nextPage,
      'prev_page_num': null,
      'has_next_page': nextPage != null,
    };

/// One folder.
Map<String, Object?> folder({
  String id = 'AbCdEf',
  String name = 'A folder',
  int itemType = 2,
  Object? parentId,
  bool isRoot = true,
}) => {
  'encrypted_id': id,
  'name': name,
  'item_type': itemType,
  'parent_encrypted_id': parentId,
  'is_root': isRoot,
};

void main() {
  group('the two kinds of content', () {
    test('carry the two spellings the server uses, which are not derivable from each other', () {
      // The URL a folder is filed under takes the slug and the body that creates one takes the
      // number. The shipped client's own map spells the second slug `note`, which the server
      // answers `400 Invalid item type`.
      expect(XiangqiSavedKind.puzzle.wireSlug, 'puzzle');
      expect(XiangqiSavedKind.puzzle.itemType, 2);
      expect(XiangqiSavedKind.note.wireSlug, 'game_note');
      expect(XiangqiSavedKind.note.itemType, 3);
    });
  });

  group('the folders', () {
    test('are read field for field', () {
      final folders = xiangqiSavedFoldersFromJson(page([folder()]));
      expect(folders.folders.length, 1);
      final first = folders.folders.single;
      expect(first.id, 'AbCdEf');
      expect(first.name, 'A folder');
      expect(first.itemType, 2);
      expect(first.parentId, isNull);
      expect(first.isRoot, isTrue);
    });

    test('carry a parent when they sit inside one', () {
      final folders = xiangqiSavedFoldersFromJson(
        page([folder(parentId: 'PaReNt', isRoot: false)]),
      );
      expect(folders.folders.single.parentId, 'PaReNt');
      expect(folders.folders.single.isRoot, isFalse);
    });

    test('keep the breadcrumbs whole, because what they hold is not pinned', () {
      // This endpoint's own field — no other list on the site has it — and it was null on every
      // read this project could make. Keeping it as it arrived is the honest thing to do with a
      // shape nobody has seen.
      final folders = xiangqiSavedFoldersFromJson({
        ...page(const []),
        'breadcrumbs': [
          {'name': 'a', 'id': 'x'},
        ],
      });
      expect(folders.breadcrumbs, isA<List<Object?>>());
    });

    test('are empty for a body that is not a list of them', () {
      expect(xiangqiSavedFoldersFromJson(null).folders, isEmpty);
      expect(xiangqiSavedFoldersFromJson(const {'items': 'nope'}).folders, isEmpty);
    });

    test('drop a row with no id or no name', () {
      final folders = xiangqiSavedFoldersFromJson(
        page([
          folder(id: 'a'),
          {...folder(id: 'b')}..remove('name'),
          folder(id: 'c'),
        ]),
      );
      expect(folders.folders.map((f) => f.id), ['a', 'c']);
    });
  });

  group('the puzzles', () {
    test('are read from the envelope the puzzle domain uses', () {
      final puzzles = xiangqiSavedPuzzlesFromJson(
        page([
          {'puzzle_id': 'AbCdEf', 'theme': 1, 'p_rating': 1500, 'created_on': '2026-10-15'},
        ]),
      );
      final first = puzzles.puzzles.single;
      expect(first.id, 'AbCdEf');
      expect(first.theme, 1);
      expect(first.rating, 1500);
      expect(first.createdOn, '2026-10-15');
    });

    test('are empty for an account that has made none', () {
      expect(xiangqiSavedPuzzlesFromJson(page(const [])).puzzles, isEmpty);
      expect(xiangqiSavedPuzzlesFromJson(null).puzzles, isEmpty);
    });
  });

  group('the notes', () {
    test("are read for whatever the site's own note objects carry", () {
      // The item shape is inferred rather than measured — every read answered with an empty list —
      // so the reader takes the names the site uses elsewhere and leaves everything optional.
      final notes = xiangqiSavedNotesFromJson(
        page([
          {
            'encrypted_id': 'GhIjKl',
            'title': 'A note',
            'description': 'What it says',
            'created_on': '2026-10-15',
          },
        ]),
      );
      final first = notes.notes.single;
      expect(first.id, 'GhIjKl');
      expect(first.title, 'A note');
      expect(first.description, 'What it says');
      expect(first.createdOn, '2026-10-15');
    });

    test('are read with nothing filled in when the payload is thin', () {
      final notes = xiangqiSavedNotesFromJson(page([const <String, Object?>{}]));
      expect(notes.notes.single.id, isNull);
      expect(notes.notes.single.title, isNull);
    });

    test('are empty for an account that has saved none', () {
      expect(xiangqiSavedNotesFromJson(page(const [])).notes, isEmpty);
      expect(xiangqiSavedNotesFromJson(null).notes, isEmpty);
    });
  });
}
