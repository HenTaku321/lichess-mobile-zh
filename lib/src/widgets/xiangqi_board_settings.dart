import 'package:chessground/chessground.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:material_ui/material_ui.dart';

/// The interaction settings shared with the chess board. Kept in the widget layer: controllers
/// receive moves, not Flutter colours or chessground widgets.
@immutable
class const XiangqiBoardSettings({
  final PieceShiftMethod pieceShiftMethod = .either,
  final bool moveOnRelease = false,
  final bool boardHighlights = true,
  final bool enableShapeDrawings = true,
  final Color shapeColor = const Color(0xAA15781B),
}) {
  factory fromPreferences(BoardPrefs prefs, {bool annotations = true}) => XiangqiBoardSettings(
    pieceShiftMethod: prefs.pieceShiftMethod,
    moveOnRelease: prefs.moveOnRelease,
    boardHighlights: prefs.boardHighlights,
    enableShapeDrawings: annotations && prefs.enableShapeDrawings,
    shapeColor: prefs.shapeColor.color,
  );
}
