import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_ui/material_ui.dart';

/// Shared analysis preferences without opening a chess analysis controller or Stockfish.
class const XiangqiAnalysisSettingsScreen() extends ConsumerWidget {
  static Route<void> buildRoute() =>
      buildScreenRoute(screen: const XiangqiAnalysisSettingsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(analysisPreferencesProvider);
    final controller = ref.read(analysisPreferencesProvider.notifier);
    final eval = ref.watch(engineEvaluationPreferencesProvider);
    final sound = ref.watch(generalPreferencesProvider.select((p) => p.isSoundEnabled));
    return Scaffold(
      appBar: AppBar(title: AppBarTitleText(context.l10n.settingsSettings)),
      body: ListView(
        children: [
          ListSection(
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.sound),
                value: sound,
                onChanged: (_) =>
                    ref.read(generalPreferencesProvider.notifier).toggleSoundEnabled(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.inlineNotation),
                value: prefs.inlineNotation,
                onChanged: (_) => controller.toggleInlineNotation(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.mobileSmallBoard),
                value: prefs.smallBoard,
                onChanged: (_) => controller.toggleSmallBoard(),
              ),
            ],
          ),
          ListSection(
            header: SettingsSectionTitle(context.l10n.computerAnalysis),
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.toggleLocalEvaluation),
                value: eval.isEnabled,
                onChanged: (_) => ref.read(engineEvaluationPreferencesProvider.notifier).toggle(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.mobileShowEngineLines),
                value: prefs.showEngineLines,
                onChanged: (_) => controller.toggleShowEngineLines(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.mobileShowEvaluationGauge),
                value: prefs.showEvaluationGauge,
                onChanged: (_) => controller.toggleShowEvaluationGauge(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.bestMoveArrow),
                value: prefs.showBestMoveArrow,
                onChanged: (_) => controller.toggleShowBestMoveArrow(),
              ),
              SliderSettingsTile(
                title: Text(context.l10n.multipleLines),
                value: eval.numEvalLines.toDouble(),
                values: const [0, 1, 2, 3],
                labelBuilder: (value) => value.toInt().toString(),
                onChangeEnd: (value) => ref
                    .read(engineEvaluationPreferencesProvider.notifier)
                    .setNumEvalLines(value.toInt()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
