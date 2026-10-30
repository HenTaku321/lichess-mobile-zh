import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:material_ui/material_ui.dart';

const kBoardAnalysisHeaderHeight = 26.0;
const kBoardAnalysisSmallScale = 0.8;

typedef AnalysisBoardSurfaceBuilder = Widget Function(
  BuildContext context,
  Size size,
  BorderRadius? radius,
);

/// Responsive analysis chrome shared by both games. Rules, pieces, tabs and evaluation data are
/// supplied by adapters; the shell only owns geometry and presentation.
class const BoardAnalysisLayout({
  required final AnalysisBoardSurfaceBuilder boardBuilder,
  required final double boardHeightRatio,
  required final Widget panel,
  final Widget? boardHeader,
  final Widget? boardFooter,
  final Widget? engineLines,
  final double engineLinesHeight = 72,
  final Widget? evalGauge,
  final double gaugeWidth = 24,
  final Widget? bottomBar,
  final bool smallBoard = false,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(boardPreferencesProvider);
    final tablet = isTabletOrLarger(context);
    return Column(
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, limits) {
                final landscape = limits.maxWidth > limits.maxHeight;
                final padding = landscape || tablet ? kTabletBoardTableSidePadding : 0.0;
                final width = math.max(0.0, limits.maxWidth - padding * 2);
                final height = math.max(0.0, limits.maxHeight - padding * 2);
                final headerHeight = MediaQuery.textScalerOf(context)
                    .scale(kBoardAnalysisHeaderHeight);
                final tables =
                    (boardHeader == null ? 0.0 : headerHeight) +
                    (boardFooter == null ? 0.0 : headerHeight);
                final lineHeight = engineLines == null
                    ? 0.0
                    : math.min(
                        height / 3,
                        MediaQuery.textScalerOf(context).scale(engineLinesHeight),
                      );
                final effectiveGaugeWidth = evalGauge == null ? 0.0 : gaugeWidth;
                final gaugeSpace = effectiveGaugeWidth + (landscape && evalGauge != null ? 4 : 0);
                final naturalWidth = math.max(0.0, (height - tables) / boardHeightRatio);
                final boardWidth = landscape
                    ? math.max(
                        0.0,
                        math.min(
                          naturalWidth,
                          math.min(
                            width - naturalWidth - gaugeSpace - 16 >= 250
                                ? naturalWidth
                                : limits.maxWidth / kGoldenRatio -
                                      padding * 2 -
                                      tables / boardHeightRatio,
                            width - gaugeSpace - 16,
                          ),
                        ),
                      )
                    : math.max(
                        0.0,
                        math.min(
                          (smallBoard ? kBoardAnalysisSmallScale : 1.0) *
                              (width - effectiveGaugeWidth),
                          (height -
                                  tables -
                                  lineHeight -
                                  math.min(
                                    height / 3,
                                    MediaQuery.textScalerOf(context).scale(88),
                                  )) /
                              boardHeightRatio,
                        ),
                      );
                final size = Size(boardWidth, boardWidth * boardHeightRatio);
                final radius = tablet ? Styles.boardBorderRadius : null;
                Widget table(Widget child) => SizedBox(
                  width: size.width,
                  height: headerHeight,
                  child: ClipRect(child: child),
                );
                Widget board() {
                  final child = SizedBox.fromSize(
                    size: size,
                    child: boardBuilder(context, size, radius),
                  );
                  return radius == null ? child : ClipRRect(borderRadius: radius, child: child);
                }

                Widget lines() => SizedBox(
                  height: lineHeight,
                  child: SingleChildScrollView(child: engineLines),
                );
                Widget contentPanel() => landscape
                    ? Card(clipBehavior: Clip.hardEdge, semanticContainer: false, child: panel)
                    : ColoredBox(
                        color: ColorScheme.of(context).surfaceContainerLowest,
                        child: panel,
                      );
                final boardColumn = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (boardHeader != null) table(boardHeader!),
                    if (landscape)
                      board()
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          board(),
                          if (evalGauge != null)
                            SizedBox(
                              width: effectiveGaugeWidth,
                              height: size.height,
                              child: evalGauge,
                            ),
                        ],
                      ),
                    if (boardFooter != null) table(boardFooter!),
                  ],
                );
                return Padding(
                  padding: EdgeInsets.all(padding),
                  child: landscape
                      ? Row(
                          textDirection: prefs.landscapeBoardPosition == .left
                              ? TextDirection.ltr
                              : TextDirection.rtl,
                          children: [
                            boardColumn,
                            if (evalGauge != null) ...[
                              const SizedBox(width: 4),
                              SizedBox(
                                width: effectiveGaugeWidth,
                                height: size.height,
                                child: evalGauge,
                              ),
                            ],
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: [
                                  if (engineLines != null) lines(),
                                  Expanded(child: contentPanel()),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            if (engineLines != null) lines(),
                            boardColumn,
                            Expanded(child: contentPanel()),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
        ?bottomBar,
      ],
    );
  }
}
