import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/engine/position_evaluator.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/engine/engine_button_display.dart';
import 'package:lichess_mobile/src/widgets/popover.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lichess_mobile/src/view/engine/engine_button_display.dart' show MicroChipPainter;

/// A button to toggle engine evaluation and show engine depth.
class const EngineButton({
  required final EngineEvaluationFilters filters,
  final VoidCallback? onTap,
  final ClientEval? savedEval,
  final VoidCallback? goDeeper,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(engineEvaluationPreferencesProvider);
    final (:engine, :engineSpec, eval: localEval, :isComputing, currentWork: _) = ref.watch(
      engineEvaluationProvider(filters),
    );
    final eval = pickBestClientEval(localEval: localEval, savedEval: savedEval);
    final status = eval is CloudEval
        ? EngineButtonStatus.ready
        : switch (engine) {
            null => EngineButtonStatus.idle,
            AsyncError() => EngineButtonStatus.error,
            AsyncValue(isLoading: true) => EngineButtonStatus.loading,
            _ => EngineButtonStatus.ready,
          };
    return EngineButtonDisplay(
      enabled: prefs.isEnabled,
      computing: isComputing,
      status: status,
      depth: eval?.depth,
      cloud: eval is CloudEval,
      engineLabel: engineShortLabel(engine?.value, spec: engineSpec) ?? prefs.enginePref.shortLabel,
      onTap: onTap,
      onLongPress: () => showPopover(
        context: context,
        bodyBuilder: (_) =>
            _EnginePopup(goDeeper: goDeeper, filters: filters, savedEval: savedEval),
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

/// Toggle button for engine evaluation with a guard against concurrent toggles.
///
/// Encapsulates the [Builder]+[FutureBuilder] pattern that disables the button while a
/// toggle request is in flight. Callers differ only in how they compute [filters],
/// [savedEval], [isEnabled], [onToggle] and [onGoDeeper].
class const EngineToggleButton({
  required final EngineEvaluationFilters filters,
  final ClientEval? savedEval,
  final bool isEnabled = true,
  required final Future<void> Function() onToggle,
  required final VoidCallback onGoDeeper,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        Future<void>? toggleFuture;
        return FutureBuilder(
          future: toggleFuture,
          builder: (context, snapshot) {
            return EngineButton(
              filters: filters,
              savedEval: savedEval,
              onTap: isEnabled && snapshot.connectionState != ConnectionState.waiting
                  ? () async {
                      toggleFuture = onToggle();
                      try {
                        await toggleFuture;
                      } finally {
                        toggleFuture = null;
                      }
                    }
                  : null,
              goDeeper: onGoDeeper,
            );
          },
        );
      },
    );
  }
}

class const _EnginePopup({
  final VoidCallback? goDeeper,
  required final EngineEvaluationFilters filters,
  final ClientEval? savedEval,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:engine, :engineSpec, currentWork: work, eval: localEval, :isComputing) = ref.watch(
      engineEvaluationProvider(filters),
    );
    final bool canGoDeeper =
        goDeeper != null && !isComputing && (work == null || work.isDeeper != true);

    final currentEval = pickBestClientEval(localEval: localEval, savedEval: savedEval);

    if (currentEval is CloudEval) {
      return ListTile(
        contentPadding: const EdgeInsets.only(left: 16.0),
        title: Text(context.l10n.cloudAnalysis),
        subtitle: Text(context.l10n.depthX('${currentEval.depth}')),
        trailing: canGoDeeper
            ? IconButton(
                icon: const Icon(Icons.add_circle_outlined),
                onPressed: goDeeper,
                tooltip: context.l10n.goDeeper,
              )
            : null,
      );
    }

    final knps = isComputing ? ', ${localEval?.knps.round()}kn/s' : '';

    final displayName = engineDisplayName(engine?.value, spec: engineSpec);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16.0),
      leading: Image.asset('assets/images/stockfish/icon.webp', width: 44, height: 44),
      title: Text(displayName),
      subtitle: currentEval != null ? Text(context.l10n.depthX('${currentEval.depth}$knps')) : null,
      trailing: canGoDeeper
          ? IconButton(
              icon: const Icon(Icons.add_circle_outlined),
              onPressed: goDeeper,
              tooltip: context.l10n.goDeeper,
            )
          : null,
    );
  }
}
