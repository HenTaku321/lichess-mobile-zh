import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_opening_translations.dart';
import 'package:lichess_mobile/src/utils/json.dart';

/// The opening-name overlay that ships with the app, as `scripts/gen-openings-zh.mjs` generated it.
///
/// Assertions are structural — the file is regenerated from lichess.org, where opening names get
/// added and renamed, and pinned counts would fail on every refresh. What they do pin is the one
/// property the generator is responsible for and a hand edit could break: the `keys` section being
/// the `names` section recomposed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> names;
  late Map<String, dynamic> keys;
  late PuzzleOpeningTranslations overlay;

  setUpAll(() async {
    final asset = PuzzleOpeningTranslations.assetFor(const Locale('zh'))!;
    final bytes = await rootBundle.load(asset);
    final json = jsonUtf8Decoder.convert(Uint8List.sublistView(bytes))! as Map<String, dynamic>;
    names = json['names'] as Map<String, dynamic>;
    keys = json['keys'] as Map<String, dynamic>;
    overlay = PuzzleOpeningTranslations.fromJson(json)!;
  });

  test('covers the openings lila serves, in Chinese', () {
    expect(names.length, greaterThan(600));
    expect(keys.length, greaterThan(names.length), reason: 'families and variations alike');

    for (final entry in names.entries) {
      final chinese = entry.value as String;
      expect(chinese.trim(), chinese, reason: '${entry.key} has surrounding space');
      expect(RegExp('[一-鿿]').hasMatch(chinese), isTrue, reason: entry.key);
      // An untranslated word would show up as a run of Latin letters; a chess move ("e6") does not.
      expect(
        RegExp('[A-Za-z]{2}').hasMatch(chinese),
        isFalse,
        reason: '${entry.key} is ${entry.value}',
      );
    }
  });

  test('translates the opening names the puzzle tab shows', () {
    // The names of the puzzle-by-opening list, which is where the English was actually noticed.
    const shown = [
      'Sicilian Defense',
      'Old Sicilian',
      'Alapin Variation',
      'Closed',
      'Bowdler Attack',
      'Najdorf Variation',
      'Modern Variations',
      'Smith-Morra Gambit',
      'McDonnell Attack',
      'Taimanov Variation',
      'Open',
      'French Variation',
      'Nyezhmetdinov-Rossolimo Attack',
      'Accelerated Dragon',
      'Dragon Variation',
      'Kan Variation',
      'Smith-Morra Gambit Accepted',
      'Löwenthal Variation',
    ];
    for (final english in shown) {
      expect(overlay.ofName(english), isNotNull, reason: english);
    }
  });

  test('every key is a lichess opening key', () {
    for (final key in keys.keys) {
      expect(RegExp('^[A-Za-z0-9_-]+\$').hasMatch(key), isTrue, reason: key);
    }
  });

  test('the keys section is the names section composed', () {
    final translated = names.values.cast<String>().toSet();

    for (final entry in keys.entries) {
      final value = entry.value as String;
      final separator = value.indexOf(': ');
      if (separator == -1) {
        // A family key: the displayed name is the family name on its own.
        expect(translated, contains(value), reason: entry.key);
      } else {
        // A variation key: `'${family}: ${child}'`, the way `flatOpeningsListProvider` composes it.
        expect(translated, contains(value.substring(0, separator)), reason: entry.key);
        expect(translated, contains(value.substring(separator + 2)), reason: entry.key);
      }
    }
  });
}
