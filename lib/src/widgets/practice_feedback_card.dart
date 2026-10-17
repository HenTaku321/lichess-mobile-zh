import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:lichess_mobile/src/styles/lichess_colors.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:material_ui/material_ui.dart';

extension PracticeFeedbackVerdictDisplay on MoveVerdict {
  IconData get icon => switch (this) {
    .goodMove => Icons.check_circle,
    .notBest => Icons.info,
    .inaccuracy => Icons.help,
    .mistake => Icons.error,
    .blunder => Icons.cancel,
  };

  Color get color => switch (this) {
    .goodMove || .notBest => Colors.lightGreen,
    .inaccuracy => LichessColors.inaccuracy,
    .mistake => LichessColors.mistake,
    .blunder => LichessColors.blunder,
  };
}

/// The game-specific parts of one practice-mode verdict, shaped for the shared card.
@immutable
final class const PracticeFeedbackData({
  required final MoveVerdict verdict,
  final String? suggestion,
  final String? evalAfter,
  final bool isBookMove = false,
});

/// The practice-mode move feedback card shared by chess and xiangqi.
///
/// The card owns only presentation and the preferences both games share. The caller supplies the
/// verdict, the suggestion in its own notation, and whether that suggestion is currently drawn on
/// the board. This keeps the layout, iconography, colours, evaluation placement and reevaluation
/// behaviour identical without pretending the two games use the same move type.
class const PracticeFeedbackCard({
  required final PracticeFeedbackData? feedback,
  required final bool isEvaluatingMove,
  required final bool isPlayerTurn,
  final bool isFinished = false,
  final String? currentEval,
  final bool showSuggestion = false,
  final VoidCallback? onToggleSuggestion,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<PracticeFeedbackCard> createState() => _PracticeFeedbackCardState();
}

class _PracticeFeedbackCardState() extends ConsumerState<PracticeFeedbackCard> {
  // Last non-null comment, kept so it can be shown faded while the next evaluation runs.
  PracticeFeedbackData? _previousFeedback;

  @override
  void didUpdateWidget(PracticeFeedbackCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feedback != null && widget.feedback == null) {
      _previousFeedback = oldWidget.feedback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(offlineComputerGamePreferencesProvider);
    final feedback = widget.feedback ?? (widget.isEvaluatingMove ? _previousFeedback : null);
    final isShortScreen = isShortVerticalScreen(context);
    final evalTextStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: isShortScreen ? 12 : 14,
      color: textShade(context, 0.6),
    );
    final cardHeight = isShortScreen ? 40.0 : 54.0;

    Widget content;
    Color? backgroundColor;
    Color? iconColor;

    if (widget.isFinished) {
      content = Text(context.l10n.gameOver, style: const TextStyle(fontStyle: .italic));
    } else if (feedback != null) {
      final verdict = feedback.verdict;
      final icon = feedback.isBookMove ? Icons.menu_book : verdict.icon;
      iconColor = verdict.color;
      backgroundColor = verdict.color.withValues(alpha: 0.1);

      final verdictText = switch (verdict) {
        MoveVerdict.goodMove => context.l10n.studyGoodMove,
        MoveVerdict.notBest => context.l10n.mobileGoodMoveButThereIsBetter,
        MoveVerdict.inaccuracy => context.l10n.inaccuracy,
        MoveVerdict.mistake => context.l10n.mistake,
        MoveVerdict.blunder => context.l10n.blunder,
      };

      Widget? suggestionWidget;
      if (feedback.suggestion case final suggestion? when !prefs.hideBestMove) {
        final labelText = verdict == MoveVerdict.goodMove
            ? context.l10n.anotherWasX('')
            : context.l10n.bestWasX('');
        final label = labelText.replaceAll(' ', '').isEmpty
            ? ''
            : labelText.substring(0, labelText.length - 1);
        suggestionWidget = GestureDetector(
          onTap: widget.onToggleSuggestion,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                const TextSpan(text: ' '),
                TextSpan(
                  text: suggestion,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: widget.showSuggestion ? iconColor : null,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ],
            ),
            style: TextStyle(fontSize: 12, color: textShade(context, 0.6)),
          ),
        );
      }

      content = Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  verdictText,
                  style: TextStyle(fontWeight: FontWeight.w600, color: iconColor),
                ),
                ?suggestionWidget,
              ],
            ),
          ),
          if (widget.currentEval ?? feedback.evalAfter case final eval? when !prefs.hideEvaluation)
            Text(eval, style: evalTextStyle),
        ],
      );
    } else if (widget.isPlayerTurn) {
      content = Row(
        children: [
          const Spacer(),
          if (!prefs.hideEvaluation && widget.currentEval != null)
            Text(widget.currentEval!, style: evalTextStyle),
        ],
      );
    } else {
      content = const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: widget.isEvaluatingMove && widget.feedback == null ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        height: cardHeight,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Align(alignment: Alignment.centerLeft, child: content),
      ),
    );
  }
}
