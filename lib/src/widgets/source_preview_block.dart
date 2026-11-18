import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

/// One source's block on a page that shows Lichess and xiangqi.com together.
///
/// The block is controlled by its parent rather than holding expansion state itself: a hub page
/// usually has two of them, and both should survive a rebuild without one closing the other. The
/// preview and the expanded body are supplied separately so a block can keep its compact summary
/// cheap while the full list is only built once the reader asks for it.
class const SourcePreviewBlock({
  required final Widget title,
  required final Widget preview,
  required final Widget expanded,
  required final bool expandedState,
  required final VoidCallback onToggle,
  final Widget? leading,
  final Widget? summary,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 20.0, 8.0, 4.0),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12.0)],
              Expanded(
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  child: title,
                ),
              ),
              if (summary != null) ...[
                const SizedBox(width: 8.0),
                DefaultTextStyle.merge(
                  style: TextStyle(color: textShade(context, 0.6)),
                  child: summary!,
                ),
              ],
              const SizedBox(width: 4.0),
              TextButton(
                onPressed: onToggle,
                child: Text(expandedState ? context.l10n.less : context.l10n.more),
              ),
            ],
          ),
        ),
        if (expandedState) expanded else preview,
      ],
    );
  }
}

/// Keeps loading and retry feedback next to the data that a single request owns.
class const SourceResult<T>({
  required final AsyncValue<T> state,
  required final VoidCallback onRetry,
  required final Widget Function(T) data,
  final Widget? header,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => state.when(
    skipLoadingOnRefresh: state.hasValue,
    data: data,
    loading: () => ListSection(
      header: header,
      children: const [
        Center(
          child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator.adaptive()),
        ),
      ],
    ),
    error: (_, _) => ListSection(
      header: header,
      children: [XiangqiRetryTile(onRetry: onRetry)],
    ),
  );
}
