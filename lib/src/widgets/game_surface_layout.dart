import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/game_table_column.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:material_ui/material_ui.dart';

typedef GameSurfaceBuilder = Widget Function(BuildContext context, Size boardSize);

/// Game-screen geometry shared by both board adapters. This widget never owns a board controller,
/// a clock or a search. Piece pockets and feedback are supplied in the player-table slots.
class const GameSurfaceLayout({
  required final GameSurfaceBuilder boardBuilder,
  required final double boardHeightRatio,
  required final GameSurfaceBuilder topTableBuilder,
  required final GameSurfaceBuilder bottomTableBuilder,
  final int topTableFlex = 1,
  final int bottomTableFlex = 1,
  final Widget Function(MoveListType)? moveListBuilder,
  final Widget? userActionsBar,
  final Widget? evalGauge,
  final double gaugeWidth = 0,
  final bool moveListVisible = true,
  final bool zenMode = false,
  final bool allowPortraitMoveList = true,
  final double portraitBoardWidthReduction = 0,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(boardPreferencesProvider);
    final tablet = isTabletOrLarger(context);
    final shortScreen = isShortVerticalScreen(context);
    final showMoves = prefs.moveListDisplay && moveListVisible && moveListBuilder != null;
    final gaugeSpace = evalGauge == null ? 0.0 : gaugeWidth + 4;

    return LayoutBuilder(
      builder: (context, limits) {
        final landscape = limits.maxWidth > limits.maxHeight;
        final padding = landscape || tablet ? kTabletBoardTableSidePadding : 0.0;
        final width = math.max(0.0, limits.maxWidth - padding * 2);
        final height = math.max(0.0, limits.maxHeight - (landscape ? padding * 2 : 0));
        final double boardWidth;
        if (landscape) {
          final naturalWidth = height / boardHeightRatio;
          final sideWidth = limits.maxWidth - naturalWidth - gaugeSpace;
          boardWidth = math.max(
            0.0,
            math.min(
              naturalWidth,
              math.min(
                sideWidth >= 250 ? naturalWidth : limits.maxWidth / kGoldenRatio - padding * 2,
                width - gaugeSpace - 16,
              ),
            ),
          );
        } else {
          final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(16) / 16);
          final maximumBoardHeight = math.max(0.0, height - 180 * scale);
          boardWidth = math.max(
            0.0,
            math.min(
                  width - portraitBoardWidthReduction - gaugeSpace,
                  maximumBoardHeight / boardHeightRatio,
                ) -
                (shortScreen ? 16 : 0),
          );
        }
        final size = Size(boardWidth, boardWidth * boardHeightRatio);
        final board = SizedBox.fromSize(size: size, child: boardBuilder(context, size));
        final top = topTableBuilder(context, size);
        final bottom = bottomTableBuilder(context, size);

        if (landscape) {
          return Padding(
            padding: EdgeInsets.all(padding),
            child: Row(
              textDirection: prefs.landscapeBoardPosition == .left
                  ? TextDirection.ltr
                  : TextDirection.rtl,
              children: [
                board,
                if (evalGauge != null) ...[
                  const SizedBox(width: 4),
                  SizedBox(width: gaugeWidth, height: size.height, child: evalGauge),
                ],
                const SizedBox(width: 16),
                Expanded(
                  child: GameTableColumn(
                    topTable: top,
                    bottomTable: bottom,
                    moves: showMoves && !zenMode
                        ? Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: moveListBuilder!(MoveListType.stacked),
                          )
                        : null,
                    minimumMoveHeight: showMoves && !zenMode
                        ? 48 * math.max(1.0, MediaQuery.textScalerOf(context).scale(16) / 16)
                        : 0,
                    actions: userActionsBar == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: userActionsBar,
                          ),
                  ),
                ),
              ],
            ),
          );
        }

        final tablePadding = EdgeInsets.symmetric(horizontal: tablet ? padding : 12);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showMoves && !shortScreen && allowPortraitMoveList)
              if (zenMode)
                const MoveList(type: MoveListType.inline, slicedMoves: [], currentMoveIndex: 0)
              else
                moveListBuilder!(MoveListType.inline),
            Expanded(
              flex: topTableFlex,
              child: Padding(padding: tablePadding, child: top),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (evalGauge != null) ...[
                    SizedBox(width: gaugeWidth, height: size.height, child: evalGauge),
                    const SizedBox(width: 4),
                  ],
                  board,
                ],
              ),
            ),
            Expanded(
              flex: bottomTableFlex,
              child: Padding(padding: tablePadding, child: bottom),
            ),
            ?userActionsBar,
          ],
        );
      },
    );
  }
}
