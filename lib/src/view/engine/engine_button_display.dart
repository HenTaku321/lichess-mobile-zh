import 'dart:math' as math;

import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:material_ui/material_ui.dart';

/// Presentation only: no chess or xiangqi providers are read here.
enum EngineButtonStatus() {
  idle,
  loading,
  ready,
  error,
}

/// The shared engine chip, animation and depth display, independent of the engine's controller.
class const EngineButtonDisplay({
  required final bool enabled,
  required final bool computing,
  required final EngineButtonStatus status,
  required final String engineLabel,
  final int? depth,
  final bool cloud = false,
  final VoidCallback? onTap,
  final VoidCallback? onLongPress,
  super.key,
}) extends StatefulWidget {
  @override
  State<EngineButtonDisplay> createState() => _EngineButtonDisplayState();
}

class _EngineButtonDisplayState() extends State<EngineButtonDisplay> {
  Color? _chipColor;

  @override
  Widget build(BuildContext context) {
    final newChipColor = widget.enabled
        ? widget.computing
              ? ColorScheme.of(context).primary
              : ColorScheme.of(context).primary.withValues(alpha: 0.65)
        : IconTheme.of(context).color ?? TextTheme.of(context).bodyMedium!.color!;
    final fromChipColor = _chipColor ?? newChipColor;
    _chipColor = newChipColor;
    final textColor = widget.enabled
        ? ColorScheme.of(context).primary
        : IconTheme.of(context).color ?? TextTheme.of(context).bodyMedium!.color!;
    final loadingIndicator = SpinKitFadingFour(color: textColor.withValues(alpha: 0.7), size: 10);
    const microChipSize = 28.0;
    final iconTextStyle = TextStyle(
      color: textColor,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
      fontSize: 11,
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        SemanticIconButton(
          semanticsLabel: context.l10n.toggleLocalEvaluation,
          onPressed: widget.onTap,
          onLongPress: widget.onLongPress,
          icon: Badge(
            offset: const Offset(4, -7),
            backgroundColor: ColorScheme.of(context).tertiaryContainer,
            textColor: ColorScheme.of(context).onTertiaryContainer,
            label: widget.enabled && widget.cloud ? const Text('CLOUD') : null,
            textStyle: const TextStyle(fontSize: 8),
            isLabelVisible: widget.enabled && widget.cloud,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<Color?>(
                  curve: Curves.easeInOut,
                  tween: ColorTween(begin: fromChipColor, end: newChipColor),
                  duration: const Duration(milliseconds: 300),
                  builder: (BuildContext context, Color? color, Widget? _) => CustomPaint(
                    size: const Size(microChipSize, microChipSize),
                    painter: MicroChipPainter(color ?? newChipColor),
                  ),
                ),
                SizedBox(
                  width: microChipSize,
                  height: microChipSize,
                  child: RepaintBoundary(
                    child: Center(
                      child: !widget.enabled
                          ? const SizedBox.shrink()
                          : switch (widget.status) {
                              EngineButtonStatus.idle => Text('-', style: iconTextStyle),
                              EngineButtonStatus.error => Text('!', style: iconTextStyle),
                              EngineButtonStatus.loading => loadingIndicator,
                              EngineButtonStatus.ready =>
                                widget.depth != null
                                    ? Text('${math.min(99, widget.depth!)}', style: iconTextStyle)
                                    : loadingIndicator,
                            },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: -6,
          child: Text(
            widget.engineLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: textColor.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

class const MicroChipPainter(final Color color) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const pinLength = 3.5;
    const pinRadius = Radius.circular(1);
    const innerRimWidth = 1.0;
    const outerRimWidth = 1.5;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final outerStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerRimWidth;

    final innerStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = innerRimWidth;

    final innerSquareSize = size.width - pinLength - innerRimWidth - outerRimWidth;

    final innerSquarePath = Path()
      ..addRRect(
        RRect.fromLTRBR(
          pinLength + innerRimWidth + outerRimWidth,
          pinLength + innerRimWidth + outerRimWidth,
          innerSquareSize,
          innerSquareSize,
          const Radius.circular(2),
        ),
      );

    final outerRimPath = Path()
      ..addRRect(
        RRect.fromLTRBR(
          pinLength,
          pinLength,
          size.width - pinLength,
          size.height - pinLength,
          const Radius.circular(4),
        ),
      );

    final pinsPath = Path();
    final chipSide = size.width - pinLength * 2;
    final pinsMargin = (chipSide - chipSide * 0.6) / 2;
    final pinWidth = chipSide / 10;
    final pinSpacing = (chipSide - (pinsMargin * 2) - 3 * pinWidth) / 2;
    // draw left pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            0,
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            pinLength,
            pinWidth,
          ),
          topLeft: pinRadius,
          bottomLeft: pinRadius,
        ),
      );
    }
    // draw right pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            size.width - pinLength,
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            pinLength,
            pinWidth,
          ),
          topRight: pinRadius,
          bottomRight: pinRadius,
        ),
      );
    }
    // draw top pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            0,
            pinWidth,
            pinLength,
          ),
          topLeft: pinRadius,
          topRight: pinRadius,
        ),
      );
    }
    // draw bottom pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            size.height - pinLength,
            pinWidth,
            pinLength,
          ),
          bottomLeft: pinRadius,
          bottomRight: pinRadius,
        ),
      );
    }

    canvas.drawPath(outerRimPath, outerStrokePaint);
    canvas.drawPath(pinsPath, fillPaint);
    canvas.drawPath(innerSquarePath, innerStrokePaint);
  }

  @override
  bool shouldRepaint(covariant MicroChipPainter oldDelegate) => color != oldDelegate.color;
}
