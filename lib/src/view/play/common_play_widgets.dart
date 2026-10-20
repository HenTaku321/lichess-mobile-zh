import 'package:lichess_mobile/src/model/lobby/game_setup_preferences.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/non_linear_slider.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_ui/material_ui.dart';

class const PlayRatingRange({
  required final UserPerf perf,
  required final (int, int) ratingDelta,
  required final void Function(int, int) onRatingDeltaChange,
  super.key,
}) extends StatefulWidget {
  @override
  State<PlayRatingRange> createState() => _PlayRatingRangeState();
}

class _PlayRatingRangeState() extends State<PlayRatingRange> {
  late int _subtract;
  late int _add;

  @override
  void initState() {
    super.initState();
    final (subtract, add) = widget.ratingDelta;
    _subtract = subtract;
    _add = add;
  }

  @override
  void didUpdateWidget(PlayRatingRange oldWidget) {
    super.didUpdateWidget(oldWidget);
    final (subtract, add) = widget.ratingDelta;
    _subtract = subtract;
    _add = add;
  }

  @override
  Widget build(BuildContext context) {
    final isRatingRangeAvailable = widget.perf.provisional != true;
    return isRatingRangeAvailable
        ? ListTile(
            title: Text(context.l10n.ratingFilter),
            subtitle: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: NonLinearSlider(
                    value: _subtract,
                    values: kSubtractingRatingRange,
                    onChange: (num value) {
                      setState(() {
                        _subtract = value.toInt();
                      });
                    },
                    onChangeEnd: isRatingRangeAvailable
                        ? (num value) {
                            widget.onRatingDeltaChange(
                              value.toInt(),
                              value == 0 && _add == 0 ? kAddingRatingRange[1] : _add,
                            );
                          }
                        : null,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44.0,
                      child: Center(child: Text('${_subtract == 0 ? '-' : ''}$_subtract')),
                    ),
                    const SizedBox(width: 8.0),
                    const Text('/'),
                    const SizedBox(width: 8.0),
                    SizedBox(width: 44.0, child: Center(child: Text('+$_add'))),
                  ],
                ),
                Flexible(
                  child: NonLinearSlider(
                    value: _add,
                    values: kAddingRatingRange,
                    onChange: (num value) {
                      setState(() {
                        _add = value.toInt();
                      });
                    },
                    onChangeEnd: isRatingRangeAvailable
                        ? (num value) {
                            widget.onRatingDeltaChange(
                              value == 0 && _subtract == 0
                                  ? kSubtractingRatingRange[kSubtractingRatingRange.length - 2]
                                  : _subtract,
                              value.toInt(),
                            );
                          }
                        : null,
                  ),
                ),
              ],
            ),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showAdaptiveDialog<void>(
              context: context,
              builder: (context) => AlertDialog.adaptive(
                content: Text(context.l10n.cannotFilterByUnstableRating),
                actions: [
                  PlatformDialogAction(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.mobileOkButton),
                  ),
                ],
              ),
            ),
            child: ListTile(
              enabled: false,
              title: Text(context.l10n.ratingFilter),
              subtitle: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Flexible(child: NonLinearSlider(value: -500, values: kSubtractingRatingRange)),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 44.0, child: Center(child: Text('-500'))),
                      SizedBox(width: 8.0),
                      Text('/'),
                      SizedBox(width: 8.0),
                      SizedBox(width: 44.0, child: Center(child: Text('+500'))),
                    ],
                  ),
                  Flexible(child: NonLinearSlider(value: 500, values: kAddingRatingRange)),
                ],
              ),
            ),
          );
  }
}

/// One control of a game's setup panel: a small label over a full-width outlined button.
///
/// The chess lobby's panel and the xiangqi one are the same arrangement of the same parts, and this
/// is the part they share — a row of these over a full-width action button is what "set up a game"
/// looks like in this app, on either board. Sharing the widget rather than the look is deliberate:
/// two copies of a button style are two button styles the moment one of them is touched.
///
/// The label is above and outside the button because it is what the button *is* rather than what it
/// is set to: the button carries the value, and it changes as the value does.
class const PlaySetupButton({
  /// What the control is, printed above it.
  required final String label,

  /// What it is set to, printed on the button.
  required final String value,

  /// The mark before the value, for a setting whose value has one — the speed's own icon, the
  /// variant's.
  final IconData? icon,

  /// What a screen reader reads, when the label and the value are not the whole of it. Defaults to
  /// `label: value`, which is what a button that carries its own value should read as.
  final String? semanticsLabel,

  final VoidCallback? onPressed,

  /// Drawn beside the label, for a control with something to say about itself before it is pressed.
  final Widget? labelTrailing,

  /// Called when the *label* is tapped, for a control whose explanation is worth reaching without
  /// pressing the button.
  final GestureTapCallback? onLabelTap,

  /// Whether the button is drawn as one that cannot be pressed while still taking a press.
  ///
  /// A setting a reader cannot change yet — a rating range on a provisional account — is one they
  /// are owed an explanation for, and a button that is genuinely disabled cannot be pressed to hear
  /// it. So it is drawn disabled and answers anyway.
  final bool dimmed = false,

  /// The style of the value on the button, for the one setting whose value is a number to be read
  /// digit by digit.
  final TextStyle? valueStyle,

  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: textShade(context, 0.5), height: 1.0);
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(label, style: labelStyle, overflow: TextOverflow.ellipsis),
        ),
        ?labelTrailing,
      ],
    );

    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel ?? '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onLabelTap != null) GestureDetector(onTap: onLabelTap, child: labelRow) else labelRow,
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).dividerColor),
              foregroundColor: dimmed ? Theme.of(context).disabledColor : null,
            ),
            icon: icon == null ? null : Icon(icon),
            label: Text(value, style: valueStyle),
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
