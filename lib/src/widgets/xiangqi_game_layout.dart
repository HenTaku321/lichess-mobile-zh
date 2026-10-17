import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:material_ui/material_ui.dart';

/// How wide an evaluation bar is drawn, in logical pixels.
///
/// The same two numbers the chess screens' own `EngineGauge` is drawn at, and for the same reason:
/// a bar is a margin note beside the board, and anything wider would be a column of its own. The
/// gauge itself cannot be reused here — it is typed to a dartchess `Position` and `Eval` from its
/// constructor down — so this is the same shape at the same size rather than a second opinion
/// about how large one should be. See `engine_gauge.dart`.
const double _kEvalGaugeSize = 24.0;
const double _kEvalGaugeFontSize = 11.0;

double xiangqiEvalGaugeWidth(BuildContext context) =>
    isTabletOrLarger(context) ? _kEvalGaugeSize : _kEvalGaugeSize - 2.0;

double xiangqiEvalGaugeFontSize(BuildContext context) =>
    isTabletOrLarger(context) ? _kEvalGaugeFontSize : _kEvalGaugeFontSize - 2.0;

/// How tall the board is for a given width.
///
/// Nine files by ten ranks of play, plus the margin the board reserves around them: half a cell
/// when the coordinates are off, a whole one when they are on, since the labels sit in it. That is
/// `9 + 2 * margin` over `8 + 2 * margin` for a margin of a half or one, which is the same sum
/// [`XiangqiBoardGeometry.fit`] makes — and it has to be the same, because the two boxes are
/// different shapes. A board laid out into the wrong one comes out smaller than the room allows,
/// sitting in the gap it did not use.
double _boardHeightRatio(BoardPrefs boardPrefs) => boardPrefs.coordinates ? 11 / 10 : 10 / 9;

/// The board and everything around it, arranged for the room the screen has.
///
/// Modelled on [GameLayout], the chess screens' own layout, rather than reusing it: that one is
/// typed to dartchess from its parameters down — a `Side` for its orientation, a chessboard for its
/// board — and none of it survives the crossing into nine files by ten ranks. Only the arrangement
/// is shared. On a portrait screen the board sits in the middle with a table above and below it; on
/// a landscape one the board sits on the left or the right — whichever [BoardPrefs
/// .landscapeBoardPosition] says — with everything else in a column beside it. A tablet gets side
/// padding so the board is not edge to edge; a short screen drops the inline move list, which is
/// the first thing there is no room for.
///
/// The board is sized here rather than by the caller, because the evaluation bar beside it has to
/// be exactly as tall as it is, and only one of the two can measure the other.
class const XiangqiGameLayout({
  /// The board itself, already wrapped in whatever colour filter the user's settings ask for.
  required final Widget board,

  /// The row above the board: the opponent, on a portrait screen.
  final Widget topTable = const SizedBox.shrink(),

  /// The row below the board: the player.
  final Widget bottomTable = const SizedBox.shrink(),

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
  /// A card is what the chess screens draw whenever the board is not the whole width of the
  /// screen — a tablet, or any landscape — and a flush board is what they draw on a portrait
  /// phone. That split is made here (`Styles.boardBorderRadius` on a tablet or in landscape,
  /// none on a portrait phone) unless this overrides it; the judgement is made here rather than
  /// by each screen, so no screen can disagree with another about it.
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
  /// Wraps [board] in the card the chess screens put their board in: the shared radius's rounding
  /// with the shared shadows under it, clipped so nothing the board draws spills past the corner.
  Widget _boardCard(Widget board, BorderRadius radius) {
    return Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: boardShadows),
      child: ClipRRect(borderRadius: radius, child: board),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final heightRatio = _boardHeightRatio(boardPrefs);
    final showMoveList = moveListVisible && boardPrefs.moveListDisplay && moves != null;
    final gaugeWidth = evalGauge == null ? 0.0 : xiangqiEvalGaugeWidth(context);
    final isTablet = isTabletOrLarger(context);
    final sidePadding = isTablet ? kTabletBoardTableSidePadding : 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final radius = boardRadius ?? (isTablet || isLandscape ? Styles.boardBorderRadius : null);
        final boardInCard = radius != null ? _boardCard(board, radius) : board;

        if (isLandscape) {
          final maxBoardHeight = constraints.maxHeight - kTabletBoardTableSidePadding * 2;
          final maxBoardWidth =
              (constraints.maxWidth - kTabletBoardTableSidePadding * 2) / kGoldenRatio;
          final boardWidth = math.min(maxBoardHeight / heightRatio, maxBoardWidth);
          final boardHeight = boardWidth * heightRatio;

          return Padding(
            padding: const EdgeInsets.all(kTabletBoardTableSidePadding),
            child: Row(
              // The preference says which side of the screen the board is on; the other things go
              // in the column beside it either way.
              textDirection: switch (boardPrefs.landscapeBoardPosition) {
                .left => TextDirection.ltr,
                .right => TextDirection.rtl,
              },
              mainAxisSize: MainAxisSize.max,
              children: [
                SizedBox(width: boardWidth, height: boardHeight, child: boardInCard),
                if (evalGauge != null) ...[
                  const SizedBox(width: 4.0),
                  SizedBox(width: gaugeWidth, height: boardHeight, child: evalGauge),
                ],
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      topTable,
                      if (showMoveList)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: MoveList(
                              type: MoveListType.stacked,
                              slicedMoves: moves!.asMap().entries.slices(2),
                              currentMoveIndex: currentMoveIndex,
                              pieceNotation: PieceNotation.letter,
                              onSelectMove: onSelectMove,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (userActionsBar != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: userActionsBar,
                        ),
                      bottomTable,
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final isShortScreen = isShortVerticalScreen(context);
        final defaultBoardWidth = constraints.biggest.shortestSide;
        var boardWidth =
            (isTablet ? defaultBoardWidth - kTabletBoardTableSidePadding * 2 : defaultBoardWidth) -
            (evalGauge == null ? 0.0 : gaugeWidth + 4.0);

        // Room for the tables, the actions bar, and — when it is shown — the inline move list, so
        // that the board is never asked to give up more than it has to.
        final maxBoardHeight = constraints.maxHeight - 180.0;
        if (boardWidth * heightRatio > maxBoardHeight) {
          boardWidth = maxBoardHeight / heightRatio;
        }
        if (isShortScreen) {
          boardWidth -= 16;
        }
        final boardHeight = boardWidth * heightRatio;

        return Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showMoveList && !isShortScreen)
              MoveList(
                type: MoveListType.inline,
                slicedMoves: moves!.asMap().entries.slices(2),
                currentMoveIndex: currentMoveIndex,
                pieceNotation: PieceNotation.letter,
                onSelectMove: onSelectMove,
              ),
            Expanded(
              flex: topTableFlex,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                child: topTable,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (evalGauge != null) ...[
                  SizedBox(width: gaugeWidth, height: boardHeight, child: evalGauge),
                  const SizedBox(width: 4.0),
                ],
                SizedBox(width: boardWidth, height: boardHeight, child: boardInCard),
              ],
            ),
            Expanded(
              flex: bottomTableFlex,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                child: bottomTable,
              ),
            ),
            ?userActionsBar,
          ],
        );
      },
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

  super.key,
}) extends StatelessWidget {
  /// The colour of the part of the bar the position has not claimed.
  static Color backgroundColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? lighten(ColorScheme.of(context).surface, .07)
      : lighten(ColorScheme.of(context).onSurface, .17);

  /// The colour of the part that has been claimed — red's, whoever the bar is drawn from.
  static Color valueColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? darken(ColorScheme.of(context).onSurface, .1)
      : darken(ColorScheme.of(context).surface, .01);

  @override
  Widget build(BuildContext context) {
    final isRedAtBottom = orientation == XiangqiSide.red;
    final redIsAhead = redWinProbability >= 0.5;
    final label = _scoreLabel(evaluation);

    // The label sits at the end the advantage is on: on the claimed half of the bar when ahead,
    // on the unclaimed one behind it. The claimed half is the lighter tone of the theme and the
    // unclaimed the darker, so the ink is whichever of the scheme's pair reads on that half.
    final scheme = ColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = TextStyle(
      color: redIsAhead
          ? (isDark ? scheme.surface : scheme.onSurface).withValues(alpha: 0.7)
          : (isDark ? scheme.onSurface : scheme.surface).withValues(alpha: 0.8),
      fontSize: xiangqiEvalGaugeFontSize(context),
      letterSpacing: -0.8,
      fontWeight: FontWeight.bold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      label: label ?? context.l10n.mobileEngineEvaluation,
      child: CustomPaint(
        painter: _XiangqiEvalGaugePainter(
          backgroundColor: backgroundColor(context),
          valueColor: valueColor(context),
          value: redWinProbability,
          isRedAtBottom: isRedAtBottom,
        ),
        child: label == null
            ? null
            : Align(
                // The label sits at the end of the bar the advantage is on, so a bar that reads
                // "red is winning" also reads from red's side.
                alignment: redIsAhead == isRedAtBottom
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 3.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: style),
                  ),
                ),
              ),
      ),
    );
  }
}

/// What the number on the bar says: a mate count, or centipawns to one decimal.
///
/// Red's point of view, to match the bar — a positive score is red's, a negative one black's, and
/// a mate count is signed the same way. Null when there is no score yet, so a bar with nothing to
/// report draws no number rather than a zero it does not mean.
String? _scoreLabel(XiangqiEvaluation? evaluation) {
  if (evaluation == null) return null;
  final mate = evaluation.mate;
  if (mate != null) return mate > 0 ? 'M$mate' : 'M${-mate}';
  final cp = evaluation.cp;
  if (cp == null) return null;
  final pawns = cp / 100.0;
  return '${pawns > 0 ? '+' : ''}${pawns.toStringAsFixed(1)}';
}

class const _XiangqiEvalGaugePainter({
  required final Color backgroundColor,
  required final Color valueColor,
  required final double value,
  required final bool isRedAtBottom,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, paint);

    paint.color = valueColor;

    // Red's share grows from red's own end of the bar. The board turns around under the player and
    // the bar turns with it, so red is always at the end of the screen red is at.
    final height = value.clamp(0.0, 1.0) * size.height;
    if (height > 0.0) {
      canvas.drawRect(
        (isRedAtBottom ? Offset(0.0, size.height - height) : Offset.zero) &
            Size(size.width, height),
        paint,
      );
    }

    final midY = size.height / 2;
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = (value >= 0.5 ? backgroundColor : valueColor).withValues(alpha: 0.35)
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_XiangqiEvalGaugePainter oldPainter) {
    return oldPainter.backgroundColor != backgroundColor ||
        oldPainter.valueColor != valueColor ||
        oldPainter.value != value ||
        oldPainter.isRedAtBottom != isRedAtBottom;
  }
}
