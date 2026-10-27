import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_opening.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_opening_translations.dart';

/// The overlay that closes the gap lila leaves: opening names are English in every language, because
/// there is no translation source for them at all.
void main() {
  group('PuzzleOpeningTranslations', () {
    final overlay = PuzzleOpeningTranslations.fromJson({
      'names': {'Sicilian Defense': '西西里防御', 'Alapin Variation': '阿拉平变例', 'Closed': '封闭变例'},
      'keys': {'Sicilian_Defense': '西西里防御', 'Sicilian_Defense_Alapin_Variation': '西西里防御: 阿拉平变例'},
    });

    final families = <PuzzleOpeningFamily>[
      (
        key: 'Sicilian_Defense',
        name: 'Sicilian Defense',
        count: 100,
        openings: IList(const [
          (key: 'Sicilian_Defense_Alapin_Variation', name: 'Alapin Variation', count: 40),
          (key: 'Sicilian_Defense_Bowdler_Attack', name: 'Bowdler Attack', count: 10),
        ]),
      ),
      (
        key: 'Caro-Kann_Defense',
        name: 'Caro-Kann Defense',
        count: 90,
        openings: const IList.empty(),
      ),
    ];

    test('replaces the names it knows, family and variation alike', () {
      final translated = overlay!.apply(families.toIList());

      expect(translated.first.name, '西西里防御');
      expect(translated.first.openings.first.name, '阿拉平变例');
    });

    test('keeps every key, count and name it does not know', () {
      final translated = overlay!.apply(families.toIList());

      // A variation's name is relative to its family ("Closed"), so the translation of the two is
      // independent; the key is what the app asks lichess for and must never be touched.
      expect(translated.first.key, 'Sicilian_Defense');
      expect(translated.first.count, 100);
      expect(translated.first.openings.first.key, 'Sicilian_Defense_Alapin_Variation');
      expect(translated.first.openings.first.count, 40);
      expect(translated.first.openings.last.name, 'Bowdler Attack', reason: 'not in the overlay');
      expect(translated.last.name, 'Caro-Kann Defense', reason: 'not in the overlay');
      expect(translated.last.openings, isEmpty);
    });

    test('answers by name and by key, and stays silent about what it does not know', () {
      expect(overlay!.ofName('Sicilian Defense'), '西西里防御');
      expect(overlay.ofName('Closed'), '封闭变例', reason: 'a name several families share');
      expect(overlay.ofName('Caro-Kann Defense'), isNull);
      expect(overlay.ofName(null), isNull);

      // The offline saved-opening list has nothing but the key, so this is the whole displayed name,
      // family included — the way `flatOpeningsListProvider` composes it.
      expect(overlay.ofKey('Sicilian_Defense_Alapin_Variation'), '西西里防御: 阿拉平变例');
      expect(overlay.ofKey('Sicilian_Defense_Bowdler_Attack'), isNull);
      expect(overlay.ofKey(null), isNull);
    });

    test('is null when there is nothing usable to apply', () {
      expect(PuzzleOpeningTranslations.fromJson(null), isNull);
      expect(PuzzleOpeningTranslations.fromJson({}), isNull);
      expect(PuzzleOpeningTranslations.fromJson({'names': <String, dynamic>{}}), isNull);
      expect(
        PuzzleOpeningTranslations.fromJson({
          'names': {'a': 1, 'b': '  '},
        }),
        isNull,
      );
      // Keys alone are not an overlay: the list itself would stay English.
      expect(
        PuzzleOpeningTranslations.fromJson({
          'keys': {'a': '甲'},
        }),
        isNull,
      );

      final partial = PuzzleOpeningTranslations.fromJson({
        'names': {'a': 1, 'b': 'ok'},
        'keys': 'not a map',
      })!;
      expect(partial.ofName('a'), isNull);
      expect(partial.ofName('b'), 'ok');
      expect(partial.ofKey('b'), isNull, reason: 'a broken keys section is not an error');
    });

    test('resolves the locale to the asset that ships for it', () {
      expect(PuzzleOpeningTranslations.assetFor(const Locale('zh')), 'assets/openings.zh.json');
      expect(
        PuzzleOpeningTranslations.assetFor(const Locale('zh', 'CN')),
        'assets/openings.zh.json',
      );
      expect(PuzzleOpeningTranslations.assetFor(const Locale('fr')), isNull);
      expect(PuzzleOpeningTranslations.assetFor(const Locale('fr', 'CA')), isNull);
    });
  });
}
