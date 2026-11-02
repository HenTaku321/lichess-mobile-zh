import 'package:chessground/chessground.dart' show DragTargetKind, PieceSet, PieceShiftMethod;
import 'package:flutter/widgets.dart' show Locale, basicLocaleListResolution;
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';

/// Enumerates the actual compiled enum values and their persistence projection, not a hand-written
/// subset that would silently discard new board/piece/sound choices after a dependency change.
Map<String, Object?> visualCatalogue() => {
  'localeResolution': {
    for (final locale in const [Locale('en', 'GB'), Locale('zh', 'CN')])
      locale.toLanguageTag(): basicLocaleListResolution([
        locale,
      ], AppLocalizations.supportedLocales).toLanguageTag(),
  },
  'axes': {
    'boardTheme': [
      for (final value in BoardTheme.values)
        BoardPrefs.defaults.copyWith(boardTheme: value).toJson()['boardTheme'],
    ],
    'pieceSet': [
      for (final value in PieceSet.values)
        BoardPrefs.defaults.copyWith(pieceSet: value).toJson()['pieceSet'],
    ],
    'pieceShiftMethod': [
      for (final value in PieceShiftMethod.values)
        BoardPrefs.defaults.copyWith(pieceShiftMethod: value).toJson()['pieceShiftMethod'],
    ],
    'dragTargetKind': [
      for (final value in DragTargetKind.values)
        BoardPrefs.defaults.copyWith(dragTargetKind: value).toJson()['dragTargetKind'],
    ],
    'shapeColor': [
      for (final value in ShapeColor.values)
        BoardPrefs.defaults.copyWith(shapeColor: value).toJson()['shapeColor'],
    ],
    'landscapeBoardPosition': [
      for (final value in LandscapeBoardPosition.values)
        BoardPrefs.defaults
            .copyWith(landscapeBoardPosition: value)
            .toJson()['landscapeBoardPosition'],
    ],
    'clockPosition': [
      for (final value in ClockPosition.values)
        BoardPrefs.defaults.copyWith(clockPosition: value).toJson()['clockPosition'],
    ],
    'materialDifferenceFormat': [
      for (final value in MaterialDifferenceFormat.values)
        BoardPrefs.defaults
            .copyWith(materialDifferenceFormat: value)
            .toJson()['materialDifferenceFormat'],
    ],
    'showRatings': [
      for (final value in ShowRatings.values)
        defaultAccountPreferences.copyWith(showRatings: value).toJson()['showRatings'],
    ],
    'clockTenths': [
      for (final value in ClockTenths.values)
        defaultAccountPreferences.copyWith(clockTenths: value).toJson()['clockTenths'],
    ],
    'booleanPref': [
      for (final value in const [BooleanPref(false), BooleanPref(true)])
        defaultAccountPreferences.copyWith(clockSound: value).toJson()['clockSound'],
    ],
    'soundTheme': [
      for (final value in SoundTheme.values)
        GeneralPrefs.defaults.copyWith(soundTheme: value).toJson()['soundTheme'],
    ],
  },
  'defaults': {
    'board': BoardPrefs.defaults.toJson(),
    'general': GeneralPrefs.defaults.copyWith(systemColors: false).toJson(),
    'account': defaultAccountPreferences.toJson(),
    'analysis': AnalysisPrefs.defaults.toJson(),
    'engineEvaluation': EngineEvaluationPrefState.defaults.toJson(),
    'offlineComputerGame': OfflineComputerGamePrefs.defaults.toJson(),
    'puzzle': PuzzlePrefs.defaults().toJson(),
  },
  'storageKeys': {for (final category in PrefCategory.values) category.name: category.storageKey},
};
