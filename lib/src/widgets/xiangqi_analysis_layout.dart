import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/widgets/board_analysis_layout.dart';
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
  final Widget? panelFooter,
  final List<Widget> panels = const [],
  final List<Tab>? tabs,
  final IList<String> moves = const IListConst([]),
  final int currentMoveIndex = 0,
  final void Function(int)? onSelectMove,
  final Widget? bottomBar,
  final bool smallBoard = false,
  final bool inlineNotation = false,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(boardPreferencesProvider);
    final ratio = xiangqiBoardHeightRatio(prefs);
    final gaugeWidth = evalGauge == null ? 0.0 : xiangqiEvalGaugeWidth(context);
    final sections = panels.isNotEmpty
        ? panels
        : [
            MoveList(
              wrapInCard: false,
              type: inlineNotation ? MoveListType.inline : MoveListType.stacked,
              slicedMoves: moves.asMap().entries.slices(2),
              currentMoveIndex: currentMoveIndex,
              pieceNotation: PieceNotation.letter,
              onSelectMove: onSelectMove,
            ),
          ];
    assert(tabs == null || tabs!.length == sections.length);

    final panel = Column(
      children: [
        ?panelHeader,
        if (sections.length > 1)
          TabBar(tabs: tabs ?? List.generate(sections.length, (i) => Tab(text: '${i + 1}'))),
        Expanded(child: sections.length == 1 ? sections.single : TabBarView(children: sections)),
        ?panelFooter,
      ],
    );
    return DefaultTabController(
      length: sections.length,
      child: BoardAnalysisLayout(
        boardBuilder: boardBuilder,
        boardHeightRatio: ratio,
        gaugeWidth: gaugeWidth,
        boardHeader: boardHeader,
        boardFooter: boardFooter,
        engineLines: engineLines,
        engineLinesHeight: engineLinesHeight,
        evalGauge: evalGauge,
        panel: panel,
        bottomBar: bottomBar,
        smallBoard: smallBoard,
      ),
    );
  }
}
