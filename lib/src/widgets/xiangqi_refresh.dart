import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:material_ui/material_ui.dart';

/// One in-flight refresh shared by mouse actions, pull-to-refresh and local retry buttons.
///
/// Key this scope by query/account identity when it can change. A disposed scope cannot announce an
/// error in the next account or screen. Existing data is owned by the providers, not cleared here.
class const XiangqiRefreshScope({
  required final Future<void> Function() onRefresh,
  required final Widget Function(BuildContext context, Future<void> Function() refresh, bool busy)
  builder,
  super.key,
}) extends StatefulWidget {
  @override
  State<XiangqiRefreshScope> createState() => _XiangqiRefreshScopeState();
}

class _XiangqiRefreshScopeState() extends State<XiangqiRefreshScope> {
  Future<void>? _inFlight;

  Future<void> _refresh() {
    if (_inFlight case final active?) return active;
    // Future.sync also handles a synchronously throwing callback without leaving the gate busy.
    final future = Future<void>.sync(widget.onRefresh)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            if (mounted) {
              showSnackBar(
                context,
                context.l10n.mobileSomethingWentWrong,
                type: SnackBarType.error,
              );
            }
          },
        )
        .whenComplete(() {
          if (mounted) {
            setState(() {
              _inFlight = null;
            });
          }
        });
    setState(() {
      _inFlight = future;
    });
    return future;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _refresh, _inFlight != null);
}

/// Linux's explicit mouse refresh affordance. Mobile retains its existing pull gesture.
class const DesktopRefreshButton({
  required final Future<void> Function() onRefresh,
  final bool busy = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => defaultTargetPlatform != TargetPlatform.linux
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: context.l10n.mobileTapToRefresh,
          onPressed: busy ? null : () => unawaited(onRefresh()),
          icon: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        );
}
