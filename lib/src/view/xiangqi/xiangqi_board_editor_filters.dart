import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_board_editor_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// What can be set about a position that putting pieces on the board cannot.
///
/// One thing: whose move it is. The chess editor offers castling rights and an en passant square
/// beside it, and xiangqi has neither — no right that survives a piece being moved is written into
/// its FEN, which is why the two fields between the side to move and the counters are `-` on every
/// xiangqi position there has ever been. The FEN's half-move and move counters are not offered
/// either: they are not a fact about the arrangement, they are a count of moves played on it, and
/// the chess editor does not offer them either.
class const XiangqiBoardEditorFilters({required final String? initialFen, super.key})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorController = xiangqiBoardEditorControllerProvider(initialFen);
    final editorState = ref.watch(editorController);

    return BottomSheetScrollableContainer(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      children: [
        Padding(
          padding: Styles.horizontalBodyPadding,
          // Red and Black, which is what the sides are called and what the side pickers on the game
          // and analysis screens say: there is no "Red to play" among the translations, and the two
          // sentences that phrase it that way are the ones that end a game.
          child: Wrap(
            spacing: 8.0,
            children: XiangqiSide.values.map((side) {
              return ChoiceChip(
                label: Text(side.label(context.l10n)),
                selected: editorState.sideToPlay == side,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(editorController.notifier).setSideToPlay(side);
                  }
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
