import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// The Chinese overlay for the practice prose bundled in `assets/practice.json`.
///
/// Practice content ships inside the app: `scripts/gen_practice.dart` bakes the live lichess
/// practice data into an asset, and the chapter names and descriptions are authored English prose.
/// Upstream localizes the *section* and *study* level through `AppLocalizations` (see
/// [PracticeSection.l10nName] and [PracticeStudy.l10nName]), but lila has no translation source
/// below that — `translation/source/practice.xml` covers sections, study names and study
/// descriptions only — so chapter text is English on lichess.org too, in every language.
///
/// This overlay closes that gap. It is generated once, offline, by `scripts/gen-practice-zh.mjs`
/// and keyed by the English source string rather than by chapter id, which makes it
/// content-addressed: a reworded chapter simply misses and falls back to English, ids changing is
/// a non-event, and a string repeated across chapters is stored once.
///
/// Applying it replaces the English in the parsed model, so every screen keeps reading
/// `chapter.name` and `chapter.description` as before and none of them needs to know about it.
class const PracticeTranslations(final Map<String, String> _byEnglish) {
  /// Parses an overlay asset, or returns null when there is nothing usable in it.
  ///
  /// Unreadable input is not an error: the app is meant to run with the English text rather than
  /// fail, so anything that is not a string-to-string object yields null.
  static PracticeTranslations? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final byEnglish = <String, String>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) byEnglish[entry.key] = value;
    }
    return byEnglish.isEmpty ? null : PracticeTranslations(byEnglish);
  }

  /// The overlay for [english], or null when it does not cover it or [english] is null.
  String? of(String? english) => english == null ? null : _byEnglish[english];

  /// The overlay for a list indexed by ply.
  ///
  /// Positional nulls are load-bearing — the lists are indexed by ply, so an entry the overlay
  /// does not cover keeps its English rather than being dropped or shifted.
  IList<String?> ofList(IList<String?> english) =>
      english.map((text) => of(text) ?? text).toIList();
}
