import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/non_linear_slider.dart';
import 'package:material_ui/material_ui.dart';

/// How hard Pikafish plays, picked with the same slider as the chess opponent controls.
class const XiangqiDifficultyTile({
  required final XiangqiDifficulty difficulty,
  required final ValueChanged<XiangqiDifficulty> onChanged,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.smart_toy),
      title: Text.rich(
        TextSpan(
          text: '${context.l10n.level}: ',
          children: [
            TextSpan(
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              text: '${difficulty.level}',
            ),
          ],
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.mobileXiangqiDifficultyExplanation),
          NonLinearSlider(
            value: difficulty.level,
            values: XiangqiDifficulty.values.map((d) => d.level).toList(),
            onChange: (value) => onChanged(XiangqiDifficulty.values[value.toInt() - 1]),
            onChangeEnd: (value) => onChanged(XiangqiDifficulty.values[value.toInt() - 1]),
          ),
        ],
      ),
    );
  }
}
