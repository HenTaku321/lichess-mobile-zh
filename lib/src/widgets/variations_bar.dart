import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/widgets/move_variations_bar.dart';
import 'package:lichess_mobile/src/widgets/pgn.dart';
import 'package:material_ui/material_ui.dart';

/// A bar showing the variations branching out of the current position, if there is more than one variation.
///
/// Each variation is shown as a button with the move SAN, and if annotations are enabled, the move
/// annotation is also shown (e.g. "!" or "?")
class const VariationsBar({
  super.key,
  required final ViewNode currentNode,
  required final UciPath currentPath,
  required final bool showAnnotations,
  required final void Function(UciPath) onJump,
}) extends StatelessWidget {
  static const maxVarSize = kMoveVariationCellWidth;

  @override
  Widget build(BuildContext context) {
    return MoveVariationsBar<UciPath>(
      choices: [
        for (var i = 0; i < currentNode.children.length; i++)
          MoveVariationChoice(
            value: currentPath + currentNode.children[i].id,
            label:
                '${currentNode.children[i].sanMove.san}${showAnnotations && currentNode.children[i].nags != null ? moveAnnotationChar(currentNode.children[i].nags!) : ''}',
            mainline: i == 0,
          ),
      ],
      onSelect: onJump,
    );
  }
}
