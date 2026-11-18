import 'dart:math' as math;

import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/game_table_column.dart';
import 'package:material_ui/material_ui.dart';

/// Places the solver's prompt, position, progress, history and actions on the training screen.
class const TrainingBoardLayout({
  required final Widget Function(Size size) boardBuilder,
  final double boardHeightRatio = 1,
  final bool boardOnRight = false,
  required final Widget feedback,
  required final Widget status,
  final Widget? landscapeHistory,
  final Widget? portraitHistory,
  required final Widget actions,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tablet = isTabletOrLarger(context);
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(16) / 16);
    return SafeArea(
      maintainBottomViewPadding: true,
      child: LayoutBuilder(
        builder: (context, limits) {
          final height = limits.maxHeight;
          final width = limits.maxWidth;
          Widget board(double extent) {
            final size = applyBoxFit(
              BoxFit.contain,
              Size(1, boardHeightRatio),
              Size.square(extent),
            ).destination;
            return SizedBox.square(
              dimension: extent,
              child: Center(
                child: SizedBox.fromSize(size: size, child: boardBuilder(size)),
              ),
            );
          }

          if (width > height) {
            const padding = kTabletBoardTableSidePadding;
            final available = math.max(0.0, height - padding * 2);
            final extent = width - available >= 250
                ? available
                : math.min(available, math.max(0.0, width / kGoldenRatio - padding * 2));
            return Padding(
              padding: const EdgeInsets.all(padding),
              child: Row(
                textDirection: boardOnRight ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  board(extent),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GameTableColumn(
                      topTable: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: feedback),
                          status,
                        ],
                      ),
                      bottomTable: const SizedBox.shrink(),
                      moves: landscapeHistory == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: landscapeHistory,
                            ),
                      minimumMoveHeight: landscapeHistory == null ? 0 : 48 * scale,
                      actions: Padding(padding: const EdgeInsets.only(bottom: 16), child: actions),
                    ),
                  ),
                ],
              ),
            );
          }

          final padding = EdgeInsets.symmetric(
            horizontal: tablet ? kTabletBoardTableSidePadding : 12,
          );
          final extent = math.max(
            0.0,
            math.min(
              width - (tablet ? 2 * kTabletBoardTableSidePadding : 0),
              height - kBottomBarHeight - 128 * scale,
            ),
          );
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: padding,
                  child: Center(child: SingleChildScrollView(primary: false, child: feedback)),
                ),
              ),
              board(extent),
              Expanded(
                child: Padding(
                  padding: padding,
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [status, ?portraitHistory],
                    ),
                  ),
                ),
              ),
              actions,
            ],
          );
        },
      ),
    );
  }
}
