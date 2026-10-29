import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';

/// History navigation using the same hold gesture and semantics as Lichess game controls.
class const HistoryNavigationButton({
  required final bool forward,
  required final VoidCallback? onTap,
  final bool blink = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => RepeatButton(
    onLongPress: onTap,
    child: BottomBarButton(
      icon: forward ? CupertinoIcons.chevron_forward : CupertinoIcons.chevron_back,
      label: forward ? context.l10n.next : context.l10n.mobilePreviousMove,
      onTap: onTap,
      // Tooltip owns a competing long-press recognizer. Keep the accessible label without it.
      showTooltip: false,
      blink: blink,
    ),
  );
}
