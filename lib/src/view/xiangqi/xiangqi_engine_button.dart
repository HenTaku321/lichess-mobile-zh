import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart'
    show xiangqiEngineProvider;
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/engine/engine_button_display.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/popover.dart';
import 'package:material_ui/material_ui.dart';

/// Lichess's chip presentation, driven exclusively by the xiangqi analysis and Pikafish.
class const XiangqiEngineButton() extends ConsumerStatefulWidget {
  @override
  ConsumerState<XiangqiEngineButton> createState() => _XiangqiEngineButtonState();
}

class _XiangqiEngineButtonState() extends ConsumerState<XiangqiEngineButton> {
  bool _toggling = false;

  Future<void> _toggle() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await ref.read(engineEvaluationPreferencesProvider.notifier).toggle();
    } on Object catch (error) {
      if (mounted) showSnackBar(context, error.toString(), type: SnackBarType.error);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(xiangqiAnalysisControllerProvider);
    final enabled = ref.watch(engineEvaluationPreferencesProvider.select((p) => p.isEnabled));
    final engine = ref.watch(xiangqiEngineProvider);
    final error = ref.read(xiangqiAnalysisControllerProvider.notifier).engineError;
    return EngineButtonDisplay(
      enabled: enabled,
      computing: state.isEngineRunning,
      status: error != null || engine.hasError
          ? EngineButtonStatus.error
          : engine.isLoading
          ? EngineButtonStatus.loading
          : EngineButtonStatus.ready,
      depth: state.depth > 0 ? state.depth : null,
      engineLabel: 'Pikafish',
      onTap: _toggling ? null : _toggle,
      onLongPress: () => showPopover(
        context: context,
        bodyBuilder: (_) => const _EngineDetails(),
        direction: PopoverDirection.top,
        width: 250,
        backgroundColor:
            DialogTheme.of(context).backgroundColor ?? ColorScheme.of(context).surfaceContainerHigh,
        transitionDuration: Duration.zero,
        popoverTransitionBuilder: (_, child) => child,
      ),
    );
  }
}

/// Only real engine identity, depth and a retryable error; no invented cloud/throughput settings.
class const _EngineDetails() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(xiangqiAnalysisControllerProvider);
    final engine = ref.watch(xiangqiEngineProvider);
    final error = ref.read(xiangqiAnalysisControllerProvider.notifier).engineError;
    return ListTile(
      title: engine.value == null
          ? const Text('Pikafish')
          : ValueListenableBuilder<String?>(
              valueListenable: engine.requireValue.name,
              builder: (_, name, _) => Text(name ?? 'Pikafish'),
            ),
      subtitle: error != null || engine.hasError
          ? Text(error ?? 'The computer could not analyse the position.')
          : state.depth > 0
          ? Text(context.l10n.depthX('${state.depth}'))
          : null,
      trailing: error != null || engine.hasError
          ? IconButton(
              tooltip: context.l10n.retry,
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(xiangqiEngineProvider);
                ref.read(xiangqiAnalysisControllerProvider.notifier).startEngine();
              },
            )
          : null,
    );
  }
}
