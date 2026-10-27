import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:material_ui/material_ui.dart';

typedef XiangqiAnalysisBoardBuilder = Widget Function(
  BuildContext context,
  Size size,
  BorderRadius? radius,
);

/// AnalysisLayout's arrangement, with the board's actual rectangular geometry.
class const XiangqiAnalysisLayout({
  required final XiangqiAnalysisBoardBuilder boardBuilder,
  final Widget? boardHeader,
  final Widget? boardFooter,
  final Widget? engineLines,
  final double engineLinesHeight = 72,
  final Widget? evalGauge,
  final Widget? panelHeader,
  final List<Widget> panels = const [],
  final List<Tab>? tabs,
  final IList<String> moves = const IListConst([]),
  final int currentMoveIndex = 0,
  final void Function(int)? onSelectMove,
  final Widget? bottomBar,
  final bool smallBoard = false,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(boardPreferencesProvider);
    final tablet = isTabletOrLarger(context);
    final ratio = xiangqiBoardHeightRatio(prefs);
    final gaugeWidth = evalGauge == null ? 0.0 : xiangqiEvalGaugeWidth(context);
    final sections = panels.isNotEmpty
        ? panels
        : [
            MoveList(
              wrapInCard: false,
              type: MoveListType.stacked,
              slicedMoves: moves.asMap().entries.slices(2),
              currentMoveIndex: currentMoveIndex,
              pieceNotation: PieceNotation.letter,
              onSelectMove: onSelectMove,
            ),
          ];
    assert(tabs == null || tabs!.length == sections.length);

    Widget panel(bool landscape) {
      final content = Column(
        children: [
          ?panelHeader,
          if (sections.length > 1)
            TabBar(tabs: tabs ?? List.generate(sections.length, (i) => Tab(text: '${i + 1}'))),
          Expanded(child: sections.length == 1 ? sections.single : TabBarView(children: sections)),
        ],
      );
      return landscape
          ? Card(clipBehavior: Clip.hardEdge, semanticContainer: false, child: content)
          : ColoredBox(color: ColorScheme.of(context).surfaceContainerLowest, child: content);
    }

    return DefaultTabController(
      length: sections.length,
      child: Column(
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
                  final headerHeight = MediaQuery.textScalerOf(context).scale(26);
                  final tables =
                      (boardHeader == null ? 0.0 : headerHeight) +
                      (boardFooter == null ? 0.0 : headerHeight);
                  final lineHeight = engineLines == null
                      ? 0.0
                      : math.min(
                          height / 3,
                          MediaQuery.textScalerOf(context).scale(engineLinesHeight),
                        );
                  final gaugeSpace = gaugeWidth + (landscape && evalGauge != null ? 4 : 0);
                  final naturalWidth = math.max(0.0, (height - tables) / ratio);
                  final boardWidth = landscape
                      ? math.max(
                          0.0,
                          math.min(
                            naturalWidth,
                            math.min(
                              width - naturalWidth - gaugeSpace - 16 >= 250
                                  ? naturalWidth
                                  : width / kGoldenRatio,
                              width - gaugeSpace - 16,
                            ),
                          ),
                        )
                      : math.max(
                          0.0,
                          math.min(
                            (smallBoard ? 0.8 : 1.0) * (width - gaugeWidth),
                            (height -
                                    tables -
                                    lineHeight -
                                    math.min(
                                      height / 3,
                                      MediaQuery.textScalerOf(context).scale(88),
                                    )) /
                                ratio,
                          ),
                        );
                  final size = Size(boardWidth, boardWidth * ratio);
                  final radius = tablet ? Styles.boardBorderRadius : null;
                  Widget table(Widget child) => SizedBox(
                    width: size.width,
                    height: headerHeight,
                    child: ClipRect(child: child),
                  );
                  Widget board() {
                    final content = SizedBox.fromSize(
                      size: size,
                      child: boardBuilder(context, size, radius),
                    );
                    return radius == null
                        ? content
                        : ClipRRect(borderRadius: radius, child: content);
                  }

                  Widget lines() => SizedBox(
                    height: lineHeight,
                    child: SingleChildScrollView(child: engineLines),
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
                              SizedBox(width: gaugeWidth, height: size.height, child: evalGauge),
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
                                SizedBox(width: gaugeWidth, height: size.height, child: evalGauge),
                              ],
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  children: [
                                    if (engineLines != null) lines(),
                                    Expanded(child: panel(true)),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              if (engineLines != null) lines(),
                              boardColumn,
                              Expanded(child: panel(false)),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
          ?bottomBar,
        ],
      ),
    );
  }
}
