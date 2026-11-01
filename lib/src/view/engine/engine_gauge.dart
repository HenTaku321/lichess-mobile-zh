import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/engine/position_evaluator.dart';
import 'package:lichess_mobile/src/widgets/evaluation_gauge.dart';
import 'package:material_ui/material_ui.dart';

double getEvalGaugeWidth(BuildContext context) => evaluationGaugeWidth(context);
double getEvalGaugeFontSize(BuildContext context) => evaluationGaugeFontSize(context);

class const EngineGauge({required final EngineGaugeParams params, super.key})
    extends ConsumerWidget {
  static Color backgroundColor(BuildContext context) => EvaluationGauge.backgroundColor(context);
  static Color valueColor(BuildContext context) => EvaluationGauge.valueColor(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localEval = params.isLocalEngineAvailable
        ? ref.watch(engineEvaluationProvider(params.filters)).eval
        : null;
    final eval = pickBestEval(
      localEval: localEval,
      savedEval: params.savedEval,
      serverEval: params.serverEval,
    );

    return Opacity(
      // if the local engine is not available and there is no server eval, show the gauge as disabled
      // this is typically a case where user is on a node not on main line and the game has the server
      // analysis
      opacity: !params.isLocalEngineAvailable && params.serverEval == null ? 0.5 : 1.0,
      child: _EvalGauge(position: params.position, orientation: params.orientation, eval: eval),
    );
  }
}

class const _EvalGauge({
  required final Position position,
  required final Side orientation,
  final Eval? eval,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final chances = eval?.winningChances(Side.white);
    final outcome = position.outcome;
    final value = outcome != null
        ? outcome.winner == null
              ? 0.5
              : outcome.winner == Side.white
              ? 1.0
              : 0.0
        : chances == null
        ? null
        : (((chances + 1) * 0.5).abs() * 100).roundToDouble() / 100;
    final score = outcome != null
        ? outcome.winner == null
              ? '0.0'
              : '#'
        : eval?.evalString;
    final integerPart = score == null || score.startsWith('#') ? null : score.split('.').first;
    return EvaluationGauge(
      value: value,
      referenceSideAtBottom: orientation == Side.white,
      label: integerPart != null && integerPart.length > 2 ? integerPart : score,
    );
  }
}
