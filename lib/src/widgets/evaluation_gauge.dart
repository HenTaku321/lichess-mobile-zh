import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:material_ui/material_ui.dart';

double evaluationGaugeWidth(BuildContext context) => isTabletOrLarger(context) ? 24.0 : 22.0;
double evaluationGaugeFontSize(BuildContext context) => isTabletOrLarger(context) ? 11.0 : 9.0;

/// Render-only evaluation gauge. The adapter supplies the reference side's probability, its
/// label and which end of the board that side occupies. Pending evaluations retain the last
/// displayed value, matching the chess gauge, without inventing a zero score.
class const EvaluationGauge({
  required final double? value,
  required final bool referenceSideAtBottom,
  final String? label,
  final bool disabled = false,
  final bool isTerminal = false,
  super.key,
}) extends StatefulWidget {
  static Color backgroundColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? lighten(ColorScheme.of(context).surface, .07)
      : lighten(ColorScheme.of(context).onSurface, .17);

  static Color valueColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? darken(ColorScheme.of(context).onSurface, .1)
      : darken(ColorScheme.of(context).surface, .01);

  @override
  State<EvaluationGauge> createState() => _EvaluationGaugeState();
}

class _EvaluationGaugeState() extends State<EvaluationGauge> {
  double _fromValue = 0.5;
  String? _previousLabel;

  double get _toValue =>
      widget.value?.isFinite == true ? widget.value!.clamp(0.0, 1.0) : _fromValue;

  @override
  void didUpdateWidget(covariant EvaluationGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A game result is not a cached engine score for a historical board position.
    if (!oldWidget.isTerminal) {
      if (oldWidget.value?.isFinite == true) _fromValue = oldWidget.value!.clamp(0.0, 1.0);
      if (oldWidget.label != null) _previousLabel = oldWidget.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label ?? _previousLabel;
    final ahead = _toValue >= 0.5;
    final style = TextStyle(
      color: ahead ? Colors.black54 : Colors.white70,
      fontSize: evaluationGaugeFontSize(context),
      letterSpacing: -0.8,
      fontWeight: FontWeight.bold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Opacity(
      opacity: widget.disabled ? 0.5 : 1.0,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: _fromValue, end: _toValue),
        duration: const Duration(milliseconds: 800),
        curve: Curves.ease,
        builder: (context, value, _) => Semantics(
          // Expose one labelled indicator. The painted score must not also become a child label
          // and make screen readers announce the same number twice.
          container: true,
          excludeSemantics: true,
          label: context.l10n.mobileEngineEvaluation,
          value: label ?? context.l10n.loadingEngine,
          child: RepaintBoundary(
            child: SizedBox(
              width: evaluationGaugeWidth(context),
              child: CustomPaint(
                painter: _EvaluationGaugePainter(
                  backgroundColor: EvaluationGauge.backgroundColor(context),
                  valueColor: EvaluationGauge.valueColor(context),
                  value: value,
                  referenceSideAtBottom: widget.referenceSideAtBottom,
                ),
                child: label == null || label.isEmpty
                    ? null
                    : Align(
                        alignment: ahead == widget.referenceSideAtBottom
                            ? Alignment.bottomCenter
                            : Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label, style: style),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _EvaluationGaugePainter({
  required final Color backgroundColor,
  required final Color valueColor,
  required final double value,
  required final bool referenceSideAtBottom,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, paint);
    final height = value.clamp(0.0, 1.0) * size.height;
    if (height == 0) return;
    paint.color = valueColor;
    canvas.drawRect(
      (referenceSideAtBottom ? Offset(0, size.height - height) : Offset.zero) &
          Size(size.width, height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _EvaluationGaugePainter old) =>
      old.backgroundColor != backgroundColor ||
      old.valueColor != valueColor ||
      old.value != value ||
      old.referenceSideAtBottom != referenceSideAtBottom;
}
