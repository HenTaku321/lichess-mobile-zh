import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:material_ui/material_ui.dart';

/// The solver's latest decision, independent of the opponent's automatic reply.
enum TrainingFeedbackPhase { prompt, correct, incorrect }

/// Shared move feedback for chess and xiangqi, with only the starting piece and prompt supplied
/// by the caller. Copy, icons and typography must not drift between the two training screens.
class const TrainingMoveFeedbackTile({
  required final TrainingFeedbackPhase phase,
  final Widget? promptLeading,
  final String? promptSubtitle,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final (leading, title, subtitle) = switch (phase) {
      TrainingFeedbackPhase.prompt => (promptLeading, context.l10n.yourTurn, promptSubtitle),
      TrainingFeedbackPhase.correct => (
        Icon(Icons.check, size: 36, color: context.lichessColors.good),
        context.l10n.puzzleBestMove,
        context.l10n.puzzleKeepGoing,
      ),
      TrainingFeedbackPhase.incorrect => (
        Icon(Icons.close, size: 36, color: context.lichessColors.error),
        context.l10n.puzzleNotTheMove,
        context.l10n.puzzleTrySomethingElse,
      ),
    };
    return FeedbackTile(
      leading: leading,
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, overflow: TextOverflow.ellipsis, maxLines: 2),
    );
  }
}

/// Presentation shared by prompt, move verdict and completion feedback on either board.
class const FeedbackTile({
  final Widget? leading,
  required final Widget title,
  final Widget? subtitle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final defaultFontSize = DefaultTextStyle.of(context).style.fontSize;

    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 16.0)],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: defaultFontSize != null ? defaultFontSize * 1.2 : null,
                  fontWeight: FontWeight.bold,
                ),
                child: title,
              ),
              ?subtitle,
            ],
          ),
        ),
      ],
    );
  }
}
