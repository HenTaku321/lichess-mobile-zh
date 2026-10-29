import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:material_ui/material_ui.dart';

/// Local retries can use the same gate while requesting only the failed section.
typedef XiangqiRefresh = Future<void> Function({Future<void> Function()? request});

/// One in-flight refresh shared by mouse actions, pull-to-refresh and local retry buttons.
///
/// Set [identity] when the query/account can change. Superseded or disposed scopes cannot announce
/// errors in the next account or screen. Existing data stays with its providers.
class const XiangqiRefreshScope({
  final Object? identity,
  required final Future<void> Function() onRefresh,
  required final Widget Function(BuildContext context, XiangqiRefresh refresh, bool busy) builder,
  super.key,
}) extends StatefulWidget {
  @override
  State<XiangqiRefreshScope> createState() => _XiangqiRefreshScopeState();
}

class _XiangqiRefreshScopeState() extends State<XiangqiRefreshScope> {
  Future<void>? _inFlight;
  int _revision = 0;

  @override
  void didUpdateWidget(XiangqiRefreshScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _revision++;
      _inFlight = null;
    }
  }

  Future<void> _refresh({Future<void> Function()? request}) {
    if (_inFlight case final active?) return active;
    final revision = _revision;
    // Future.sync also handles a synchronously throwing callback without leaving the gate busy.
    final future = Future<void>.sync(request ?? widget.onRefresh)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            if (mounted && revision == _revision) {
              showSnackBar(
                context,
                context.l10n.mobileSomethingWentWrong,
                type: SnackBarType.error,
              );
            }
          },
        )
        .whenComplete(() {
          if (mounted && revision == _revision) {
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

/// Keeps only settled data observed for this identity, never an error's implicit previous value.
///
/// Riverpod may carry the old account's data into a reload error. Changing identity clears our copy,
/// so retaining a manual refresh cannot resurrect another user's content.
class const XiangqiRetainedData<T>({
  required final Object identity,
  required final AsyncValue<T> value,
  required final Widget Function(BuildContext context, AsyncValue<T> value) builder,
  super.key,
}) extends StatefulWidget {
  @override
  State<XiangqiRetainedData<T>> createState() => _XiangqiRetainedDataState<T>();
}

class _XiangqiRetainedDataState<T>() extends State<XiangqiRetainedData<T>> {
  AsyncData<T>? _settled;
  Object? _identity;

  @override
  Widget build(BuildContext context) {
    final current = widget.value;
    if (_identity != widget.identity) {
      _identity = widget.identity;
      _settled = null;
    }
    if (current is AsyncData<T> && !current.isLoading && !current.hasError) {
      _settled = current;
    }
    final AsyncValue<T> displayed;
    if (_settled != null) {
      displayed = _settled!;
    } else if (current.isLoading) {
      displayed = const AsyncLoading();
    } else if (current.hasError) {
      // Drop implicit previous data even if a caller uses AsyncValue.when(skipError: true).
      displayed = AsyncError(current.error!, current.stackTrace!);
    } else {
      displayed = current;
    }
    return widget.builder(context, displayed);
  }
}

/// Linux's explicit mouse refresh affordance. Mobile retains its existing pull gesture.
class const DesktopRefreshButton({
  required final Future<void> Function() onRefresh,
  final bool busy = false,
  final bool enabled = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => defaultTargetPlatform != TargetPlatform.linux
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: context.l10n.mobileTapToRefresh,
          onPressed: busy || !enabled ? null : () => unawaited(onRefresh()),
          icon: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        );
}

/// A consistent section-level error with a mouse-visible, individually retryable action.
class const XiangqiRetryTile({required final VoidCallback? onRetry}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(context.l10n.mobileSomethingWentWrong),
    trailing: IconButton(
      tooltip: context.l10n.retry,
      icon: const Icon(Icons.refresh),
      onPressed: onRetry,
    ),
  );
}
