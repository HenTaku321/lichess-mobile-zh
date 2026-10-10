import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/practice/practice_structure.dart';
import 'package:lichess_mobile/src/model/practice/practice_translations.dart';

/// The overlay that closes the gap upstream leaves: chapter names and descriptions are authored
/// English prose with no l10n path, because lila has no translation source below the study level.
void main() {
  final asset = {
    'sections': [
      {
        'id': 'checkmates',
        'name': 'Checkmates',
        'studies': [
          {
            'id': 'study1',
            'slug': 'study-one',
            'name': 'Study one',
            'description': 'The first study',
            'chapters': [
              {
                'id': 'engine01',
                'name': 'Queen mate',
                'kind': 'practice',
                'orientation': 'white',
                'fen': '8/8/3k4/8/8/4K3/8/Q6R w - - 0 1',
                'description': 'Use your rocks to restrict the king.',
                'goal': {'result': 'mateIn', 'moves': 4},
              },
              {
                'id': 'gamebk01',
                'name': 'Finish it',
                'kind': 'gamebook',
                'orientation': 'black',
                'fen': '8/8/3k4/8/8/4K3/8/Q6R b - - 0 1',
                'pgn': '{ Find the move }',
                'hints': [null, 'A hint'],
                'deviations': [null, 'Not that one'],
              },
              {
                'id': 'lesson01',
                'name': 'Lesson',
                'kind': 'lesson',
                'orientation': 'white',
                'fen': '8/8/3k4/8/8/4K3/8/Q6R w - - 0 1',
                'description': 'Nothing to solve.',
                'pgn': '1. Qa6+ *',
              },
            ],
          },
        ],
      },
    ],
  };

  group('PracticeTranslations', () {
    final overlay = PracticeTranslations.fromJson({
      'Queen mate': '后的将杀',
      'Use your rocks to restrict the king.': '用车封锁王的退路。',
      'A hint': '提示',
      // Sections and studies are localized through `AppLocalizations`, so the overlay must leave
      // them alone even when it happens to know the string.
      'Study one': '研习一',
    });

    test('replaces the chapter prose it knows', () {
      final structure = PracticeStructure.fromJson(asset, translations: overlay);
      final chapters = structure.study(const StudyId('study1'))!.chapters;

      final engine = chapters.first as PracticeEngineChapter;
      expect(engine.name, '后的将杀');
      expect(engine.description, '用车封锁王的退路。');
      expect(engine.fen, '8/8/3k4/8/8/4K3/8/Q6R w - - 0 1', reason: 'the position is not prose');
    });

    test('leaves the section and study levels to l10n', () {
      final structure = PracticeStructure.fromJson(asset, translations: overlay);

      expect(structure.sections.first.name, 'Checkmates');
      expect(structure.study(const StudyId('study1'))!.name, 'Study one');
      expect(structure.study(const StudyId('study1'))!.description, 'The first study');
    });

    test('keeps the English of every string it does not know', () {
      final structure = PracticeStructure.fromJson(asset, translations: overlay);
      final chapters = structure.study(const StudyId('study1'))!.chapters;

      final lesson = chapters.last as PracticeLessonChapter;
      expect(lesson.name, 'Lesson');
      expect(lesson.description, 'Nothing to solve.');
    });

    test('translates hints and deviations without shifting them off their ply', () {
      final structure = PracticeStructure.fromJson(asset, translations: overlay);
      final gamebook =
          structure.study(const StudyId('study1'))!.chapters[1] as PracticeGamebookChapter;

      // Both lists are indexed by ply, so an entry the overlay misses keeps its English and an
      // empty one stays empty.
      expect(gamebook.hints, [null, '提示']);
      expect(gamebook.deviations, [null, 'Not that one']);
    });

    test('is null when there is nothing usable to apply', () {
      expect(PracticeTranslations.fromJson(null), isNull);
      expect(PracticeTranslations.fromJson({}), isNull);
      expect(PracticeTranslations.fromJson({'a': 1, 'b': '  '}), isNull);

      final partial = PracticeTranslations.fromJson({'a': 1, 'b': 'ok'})!;
      expect(partial.of('a'), isNull);
      expect(partial.of('b'), 'ok');
      expect(partial.of(null), isNull);
      expect(partial.of('unknown'), isNull);
    });
  });
}
