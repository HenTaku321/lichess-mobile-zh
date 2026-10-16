// Tests for reading the courses, and for the one translation a chapter's position needs.
//
// The shapes are the ones the 2026-10-16 probe measured — see `xiangqi-com-re/docs/lesson.md` — with
// every value replaced. Not one topic id, lesson id or position here is the capture's.
//
// Two of the cases are about the translation rather than the reading, because that is where this
// domain's uncertainty is: the lesson FEN spells its side `r` and its general `j`, and the second of
// those is an inference the model says outright is one.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// One topic of `lessons/levels`.
Map<String, Object?> topic({
  String id = 'AbCdEf',
  String title = 'A topic',
  int levelId = 1,
  String levelTitle = 'NewBie',
  int totalLessons = 7,
  int completeLessons = 0,
}) => {
  'encrypted_id': id,
  'topic_title': title,
  'level_id': levelId,
  'level_title': levelTitle,
  'description': 'What it teaches',
  'image_url': 'https://api.xiangqi.com/api/media/https://example.invalid/a.png',
  'total_lessons': totalLessons,
  'complete_lessons': completeLessons,
};

/// One lesson of a topic.
Map<String, Object?> lesson({
  String id = 'GhIjKl',
  String title = 'A lesson',
  int order = 1,
  int totalChaps = 6,
  int compChaps = 0,
}) => {
  'encrypted_id': id,
  'title': title,
  'description': 'What it teaches',
  'image_url': 'https://api.xiangqi.com/api/media/https://example.invalid/b.png',
  'order': order,
  'total_chaps': totalChaps,
  'comp_chaps': compChaps,
};

/// One chapter, with the fields the endpoint was measured to carry.
Map<String, Object?> chapter({
  String id = 'MnOpQr',
  int order = 1,
  String fen = '9/9/9/9/9/9/9/9/9/8R r - - 0 1',
  List<Map<String, Object?>>? moves,
  bool completed = false,
}) => {
  'encrypted_id': id,
  'order': order,
  'description': 'Move the chariot',
  'initial_fen': fen,
  'moves':
      moves ??
      <Map<String, Object?>>[
        // The placeholder every chapter starts with: an empty `uci` and the hints.
        <String, Object?>{
          'uci': '',
          'arrows': <Object?>[
            <String, Object?>{'c1': 'i', 'r1': 1, 'c2': 'i', 'r2': 10},
          ],
          'intersections': <Object?>[],
        },
        <String, Object?>{
          'uci': 'i1i10',
          'next_move': 'b',
          'arrows': <Object?>[],
          'intersections': <Object?>[],
        },
      ],
  'answer_type': 'single',
  'auto_transition': false,
  'flip_board': false,
  'puzzle_type': null,
  'completed': completed,
};

void main() {
  group('the topics', () {
    test('are read field for field', () {
      final topics = xiangqiTopicsFromJson(<String, Object?>{
        'levels': <Object?>[],
        'topics': <Object?>[topic()],
      });
      expect(topics.length, 1);
      final first = topics.single;
      expect(first.id, 'AbCdEf');
      expect(first.title, 'A topic');
      expect(first.levelId, 1);
      expect(first.levelTitle, 'NewBie');
      expect(first.totalLessons, 7);
      expect(first.completeLessons, 0);
      expect(first.isComplete, isFalse);
    });

    test('are complete when every lesson is done', () {
      expect(
        xiangqiTopicsFromJson(<String, Object?>{
          'topics': <Object?>[topic(completeLessons: 7)],
        }).single.isComplete,
        isTrue,
      );
      // A topic with no lessons at all is not a topic that is finished; it is a topic with nothing
      // in it, and a tick beside it would say the reader had done something.
      expect(
        xiangqiTopicsFromJson(<String, Object?>{
          'topics': <Object?>[topic(totalLessons: 0)],
        }).single.isComplete,
        isFalse,
      );
    });

    test('are empty for a body that is not a list of them', () {
      expect(xiangqiTopicsFromJson(null), isEmpty);
      expect(xiangqiTopicsFromJson(const {'topics': 'nope'}), isEmpty);
      expect(xiangqiTopicsFromJson(const {'topics': <Object?>[]}), isEmpty);
    });

    test('drop a row with no id or no title', () {
      final topics = xiangqiTopicsFromJson({
        'topics': [
          topic(id: 'a'),
          {...topic(id: 'b')}..remove('topic_title'),
          topic(id: 'c'),
        ],
      });
      expect(topics.map((t) => t.id), ['a', 'c']);
    });
  });

  group('a topic with its lessons', () {
    test('is read with the lessons in the order the server lists them', () {
      final detail = xiangqiTopicDetailFromJson({
        ...topic(),
        'lessons': [lesson(id: 'one', order: 1), lesson(id: 'two', order: 2)],
      })!;
      expect(detail.topic.id, 'AbCdEf');
      expect(detail.lessons.map((l) => l.id), ['one', 'two']);
      expect(detail.lessons.first.totalChapters, 6);
      expect(detail.lessons.first.isComplete, isFalse);
    });

    test('is null for a body that is not a topic', () {
      expect(xiangqiTopicDetailFromJson(null), isNull);
      expect(xiangqiTopicDetailFromJson(const {'lessons': <Object?>[]}), isNull);
    });
  });

  group('a chapter', () {
    test('drops the placeholder the script starts with', () {
      // Every chapter's first entry carries an empty `uci` and the hints for the position; the
      // moves themselves are the entries after it. Measured on 2026-10-16, on all six chapters of
      // the first lesson.
      final chapters = xiangqiChaptersFromJson({
        'chapters': [chapter()],
      });
      final first = chapters.single;
      expect(first.id, 'MnOpQr');
      expect(first.order, 1);
      expect(first.moves.length, 1);
      expect(first.moves.single, XiangqiMove.parseIccs('i0i9'));
    });

    test('reads a longer script in order', () {
      final chapters = xiangqiChaptersFromJson({
        'chapters': [
          chapter(
            moves: [
              {'uci': ''},
              {'uci': 'i1i10'},
              {'uci': 'i10h10'},
            ],
          ),
        ],
      });
      expect(chapters.single.moves, [XiangqiMove.parseIccs('i0i9'), XiangqiMove.parseIccs('i9h9')]);
    });

    test('carries whether this account has done it', () {
      expect(
        xiangqiChaptersFromJson({
          'chapters': [chapter(completed: true)],
        }).single.isCompleted,
        isTrue,
      );
    });

    test('is empty for a body that is not a list of them', () {
      expect(xiangqiChaptersFromJson(null), isEmpty);
      expect(xiangqiChaptersFromJson(const {'chapters': <Object?>[]}), isEmpty);
    });
  });

  group("a chapter's position", () {
    test('is read with the side letter the site spells red with', () {
      // The site writes a red-to-move position `r` and this app writes it `w`; the shipped client
      // makes the same substitution before it hands a lesson FEN to its own board.
      final position = xiangqiChapterPositionOf('9/9/9/9/9/9/9/9/9/8R r - - 0 1');
      expect(position, isNotNull);
      expect(position!.turn, XiangqiSide.red);
      expect(position.toFen(), '9/9/9/9/9/9/9/9/9/8R w - - 0 1');
    });

    test('is read with the general the site spells with a j', () {
      // **An inference, not a measurement.** `j` is not in the site's own piece set, and it is read
      // as the black general because that is the piece the lesson positions are missing and the
      // only letter they use that the set does not have. See the model, which says so.
      final position = xiangqiChapterPositionOf('j8/9/9/9/9/9/9/9/9/9 r - - 0 1');
      expect(position, isNotNull);
      expect(position!.pieceAt(XiangqiSquare.parse('a9')!), isNotNull);
    });

    test('is null when the position cannot be read at all', () {
      expect(xiangqiChapterPositionOf(null), isNull);
      expect(xiangqiChapterPositionOf('not a position'), isNull);
      expect(xiangqiChapterPositionOf('9/9/9/9/9/9/9/9/9/8X r - - 0 1'), isNull);
    });
  });
}
