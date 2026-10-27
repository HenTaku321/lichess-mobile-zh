import 'dart:async';
import 'dart:math' as math;

import 'package:lichess_mobile/src/constants.dart';
import 'package:material_ui/material_ui.dart';

/// The result shell shared by the three xiangqi game modes, without game-specific protocols.
class const XiangqiResultDialog({
  required final String title,
  required final String score,
  required final String explanation,
  required final List<Widget> Function(BuildContext context, bool enabled) actionsBuilder,
  final Duration activationDelay = Duration.zero,
  super.key,
}) extends StatefulWidget {
  @override
  State<XiangqiResultDialog> createState() => _XiangqiResultDialogState();
}

class _XiangqiResultDialogState() extends State<XiangqiResultDialog> {
  Timer? _activation;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.activationDelay == Duration.zero;
    if (!_enabled) {
      _activation = Timer(widget.activationDelay, () {
        if (mounted) setState(() => _enabled = true);
      });
    }
  }

  @override
  void dispose() {
    _activation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: math.min(MediaQuery.widthOf(context), kMaterialPopupMenuMaxWidth),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: TextTheme.of(context).titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(widget.score, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              widget.explanation,
              style: const TextStyle(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Wrap(
                key: ValueKey(_enabled),
                alignment: WrapAlignment.center,
                spacing: 8,
                children: widget.actionsBuilder(context, _enabled),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
