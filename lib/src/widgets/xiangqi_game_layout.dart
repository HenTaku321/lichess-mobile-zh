import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/evaluation_gauge.dart';
import 'package:lichess_mobile/src/widgets/game_surface_layout.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:material_ui/material_ui.dart';

/// Compatibility helpers; both games use the same evaluation-gauge presentation.
double xiangqiEvalGaugeWidth(BuildContext context) => evaluationGaugeWidth(context);

double xiangqiEvalGaugeFontSize(BuildContext context) => evaluationGaugeFontSize(context);

/// How tall the board is for a given width.
///
/// Nine files by ten ranks of play, plus the margin the board reserves around them: half a cell
/// when the coordinates are off, a whole one when they are on, since the labels sit in it. That is
/// `9 + 2 * margin` over `8 + 2 * margin` for a margin of a half or one, which is the same sum
/// [`XiangqiBoardGeometry.fit`] makes — and it has to be the same, because the two boxes are
/// different shapes. A board laid out into the wrong one comes out smaller than the room allows,
/// sitting in the gap it did not use.
double xiangqiBoardHeightRatio(BoardPrefs boardPrefs) => boardPrefs.coordinates ? 11 / 10 : 10 / 9;

/// Thin xiangqi adapter for the shared game layout. Only rectangular board geometry, notation
/// and the piece surface are supplied here; sizing, player-table placement and chrome are common.
class const XiangqiGameLayout({
  /// The board itself, already wrapped in whatever colour filter the user's settings ask for.
  required final Widget board,

  /// The row above the board: the opponent, on a portrait screen.
  final Widget topTable = const SizedBox.shrink(),

  /// The row below the board: the player.
  final Widget bottomTable = const SizedBox.shrink(),
  final bool topTableUpsideDown = false,
  final bool bottomTableUpsideDown = false,

  final int topTableFlex = 1,
  final int bottomTableFlex = 1,

  /// The evaluation bar drawn beside the board, or null when there is no evaluation to show.
  final Widget? evalGauge,

  /// The moves played, written in the notation of the game, or null for no move list at all.
  final IList<String>? moves,

  /// Which move the list marks as the current one, in the list's own counting: 0 is before the
  /// first move, so the move at index `n` is current when this is `n + 1`.
  final int currentMoveIndex = 0,

  /// Called with a move's index when it is tapped, in the same counting as [currentMoveIndex].
  final void Function(int moveIndex)? onSelectMove,

  /// The rounding the board is drawn as a card with, or null for it to sit flush to the edge.
  ///
  /// Matches GameLayout: tablets use Styles.boardBorderRadius; phones remain flush in either
  /// orientation. Analysis screens may override this when using a card presentation.
  final BorderRadius? boardRadius,

  /// The bar of actions under everything else.
  final Widget? userActionsBar,

  /// Whether the move list should be shown at all, over and above the user's own preference.
  ///
  /// [BoardPrefs.moveListDisplay] is the setting; this is the screen's own toggle on top of it, so
  /// that a player can put the panel away for a game without changing a preference that outlives
  /// the game.
  final bool moveListVisible = true,

  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(boardPreferencesProvider);
    final radius = boardRadius ?? (isTabletOrLarger(context) ? Styles.boardBorderRadius : null);
    final framedBoard = radius == null
        ? board
        : Container(
            decoration: BoxDecoration(borderRadius: radius, boxShadow: boardShadows),
            child: ClipRRect(borderRadius: radius, child: board),
          );
    return GameSurfaceLayout(
      boardBuilder: (_, _) => framedBoard,
      boardHeightRatio: xiangqiBoardHeightRatio(prefs),
      topTableBuilder: (_, _) =>
          RotatedBox(quarterTurns: topTableUpsideDown ? 2 : 0, child: topTable),
      bottomTableBuilder: (_, _) =>
          RotatedBox(quarterTurns: bottomTableUpsideDown ? 2 : 0, child: bottomTable),
      topTableFlex: topTableFlex,
      bottomTableFlex: bottomTableFlex,
      evalGauge: evalGauge,
      gaugeWidth: xiangqiEvalGaugeWidth(context),
      moveListVisible: moveListVisible,
      moveListBuilder: moves == null
          ? null
          : (type) => MoveList(
              type: type,
              slicedMoves: moves!.asMap().entries.slices(2),
              currentMoveIndex: currentMoveIndex,
              pieceNotation: PieceNotation.letter,
              onSelectMove: onSelectMove,
            ),
      userActionsBar: userActionsBar,
    );
  }
}

/// How a game of xiangqi is doing, as a bar beside the board.
///
/// Red's share of the position, drawn from red's own end of the board: the board at the bottom of
/// the screen has red at the bottom of it, so the bar has red at the bottom too, and turning the
/// board around turns the bar with it. The share is [XiangqiEvaluation.redWinProbability], which is
/// already red's — no side is worked out here, and nothing is flipped: the model hands over a
/// number between 0 and 1 and this draws it.
class const XiangqiEvalGauge({
  /// Red's chance of winning, from 0 for black winning outright to 1 for red, 0.5 level.
  required final double redWinProbability,

  /// The side drawn at the bottom of the board, which is the side drawn at the bottom of the bar.
  required final XiangqiSide orientation,

  /// The score the bar is drawn from, for the line of text on it. Nothing is drawn without one.
  final XiangqiEvaluation? evaluation,

  /// Non-null only when this displayed position has an outcome; null winner means a draw.
  final ({XiangqiSide? winner})? outcome,

  final bool disabled = false,

  super.key,
}) extends StatelessWidget {
  static Color backgroundColor(BuildContext context) => EvaluationGauge.backgroundColor(context);
  static Color valueColor(BuildContext context) => EvaluationGauge.valueColor(context);

  @override
  Widget build(BuildContext context) => EvaluationGauge(
    value: outcome != null
        ? outcome!.winner == null
              ? 0.5
              : outcome!.winner == .red
              ? 1.0
              : 0.0
        : evaluation == null
        ? null
        : redWinProbability,
    referenceSideAtBottom: orientation == .red,
    label: outcome != null
        ? outcome!.winner == null
              ? '0.0'
              : '#'
        : _scoreLabel(evaluation),
    disabled: disabled,
  );
}

/// What the number on the bar says: a mate count, or centipawns to one decimal.
///
/// Red's point of view, to match the bar — a positive score is red's, a negative one black's, and
/// a mate count is signed the same way. Null when there is no score yet, so a bar with nothing to
/// report draws no number rather than a zero it does not mean.
String? _scoreLabel(XiangqiEvaluation? evaluation) {
  if (evaluation == null) return null;
  if (evaluation.cp == null && evaluation.mate == null) return null;
  final label = evaluation.evalString!;
  // xiangqi.com writes a mate count as `M3`/`M-3`; keep the sign but use that convention rather
  // than leaking the chess notation used by the shared evaluation string.
  if (label.startsWith('#')) return 'M${label.substring(1)}';
  final integerPart = label.split('.').first;
  return integerPart.length > 2 ? integerPart : label;
}
