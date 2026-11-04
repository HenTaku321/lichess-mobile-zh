import 'dart:async';

import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

/// An operation may finish immediately or remain active until its real request/dialog completes.
typedef GameActionCallback = FutureOr<void> Function();
typedef GameActionLabel = String Function(BuildContext context);

/// Read-only presentation and availability supplied by the owning game, never inferred from rules.
class const GameActionSpec({
  required final String id,
  required final GameActionLabel label,
  required final IconData icon,
  final GameActionCallback? onInvoke,
  final bool busy = false,
  final bool highlighted = false,
  final GameActionLabel? unavailableReason,
}) {
  bool get enabled => onInvoke != null && !busy;
}

/// Guards activation before the next frame and preserves that guard across controller rebuilds.
/// This owns presentation only: cancellation and stale result checks belong to the controller.
class const GameActionButton({required final GameActionSpec action, super.key})
    extends StatefulWidget {
  @override
  State<GameActionButton> createState() => _GameActionButtonState();
}

class _GameActionButtonState() extends State<GameActionButton> {
  static final _logger = Logger('GameActionButton');
  bool _pending = false;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant GameActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action.id != widget.action.id) {
      _generation++;
      _pending = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _invoke() async {
    if (_pending || !widget.action.enabled) return;
    final action = widget.action;
    final operation = action.onInvoke!;
    final generation = ++_generation;
    setState(() => _pending = true);
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      if (mounted && generation == _generation) {
        _logger.warning('Game action ${action.id} failed.', error, stackTrace);
        if (ModalRoute.of(context)?.isCurrent ?? true) {
          showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
        }
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final enabled = action.enabled && !_pending;
    return Semantics(
      hint: enabled ? null : action.unavailableReason?.call(context),
      child: BottomBarButton(
        label: action.label(context),
        icon: action.icon,
        onTap: enabled ? () => unawaited(_invoke()) : null,
        busy: action.busy || _pending,
        highlighted: action.highlighted,
      ),
    );
  }
}
