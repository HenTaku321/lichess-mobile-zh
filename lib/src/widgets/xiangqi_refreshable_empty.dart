import 'package:material_ui/material_ui.dart';

/// Keeps pull-to-refresh available when a remote list has no rows (or fewer rows than the viewport).
class const XiangqiRefreshableEmpty({
  required final Future<void> Function() onRefresh,
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => RefreshIndicator.adaptive(
    onRefresh: onRefresh,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [SliverFillRemaining(hasScrollBody: false, child: Center(child: child))],
    ),
  );
}
