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
  final PracticeFeedbackData? previousFeedback,
  required final bool isEvaluatingMove,
  required final bool isPlayerTurn,
  final bool isFinished = false,
  final String? currentEval,
  final bool showSuggestion = false,
  final VoidCallback? onToggleSuggestion,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(offlineComputerGamePreferencesProvider);
    final visibleFeedback = feedback ?? (isEvaluatingMove ? previousFeedback : null);
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

    if (isFinished) {
      content = Text(context.l10n.gameOver, style: const TextStyle(fontStyle: .italic));
    } else if (visibleFeedback != null) {
      final verdict = visibleFeedback.verdict;
      final icon = visibleFeedback.isBookMove ? Icons.menu_book : verdict.icon;
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
      if (visibleFeedback.suggestion case final suggestion? when !prefs.hideBestMove) {
        final labelText = verdict == MoveVerdict.goodMove
            ? context.l10n.anotherWasX('')
            : context.l10n.bestWasX('');
        final label = labelText.trimRight();
        suggestionWidget = InkWell(
          onTap: onToggleSuggestion,
          canRequestFocus: onToggleSuggestion != null,
          borderRadius: BorderRadius.circular(4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                const TextSpan(text: ' '),
                TextSpan(
                  text: suggestion,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: showSuggestion ? iconColor : null,
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

      final eval = prefs.hideEvaluation ? null : currentEval ?? visibleFeedback.evalAfter;
      content = LayoutBuilder(
        builder: (context, constraints) {
          final stackEvaluation =
              constraints.maxWidth < 320 || MediaQuery.textScalerOf(context).scale(14) > 18;
          return Row(
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
                    if (stackEvaluation && eval != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(eval, style: evalTextStyle),
                      ),
                    ],
                  ],
                ),
              ),
              if (!stackEvaluation && eval != null) Text(eval, style: evalTextStyle),
            ],
          );
        },
      );
    } else if (isPlayerTurn) {
      content = Row(
        children: [
          const Spacer(),
          if (!prefs.hideEvaluation && currentEval != null)
            Text(currentEval!, style: evalTextStyle),
        ],
      );
    } else {
      content = const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: isEvaluatingMove && feedback == null ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        constraints: BoxConstraints(minHeight: cardHeight),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Align(alignment: Alignment.centerLeft, heightFactor: 1, child: content),
        ),
      ),
    );
  }
}

/// The practice status and feedback belong to the human seat, regardless of board orientation.
class const PracticeFeedbackPanel({
  required final Widget playerRow,
  required final PracticeFeedbackData? feedback,
  final PracticeFeedbackData? previousFeedback,
  required final bool isEvaluatingMove,
  required final bool isPlayerTurn,
  final bool isEngineThinking = false,
  final bool isFinished = false,
  final String? currentEval,
  final bool showSuggestion = false,
  final VoidCallback? onToggleSuggestion,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final short = isShortVerticalScreen(context);
    final status = isFinished
        ? ''
        : isEvaluatingMove
        ? context.l10n.evaluatingYourMove
        : isEngineThinking
        ? context.l10n.computerThinking
        : isPlayerTurn
        ? context.l10n.yourTurn
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: short ? 4 : 8),
          child: Text(
            status,
            style: TextStyle(
              fontSize: short ? 11 : null,
              fontStyle: FontStyle.italic,
              color: textShade(context, 0.8),
              height: short ? 1 : null,
            ),
          ),
        ),
        PracticeFeedbackCard(
          feedback: feedback,
          previousFeedback: previousFeedback,
          isEvaluatingMove: isEvaluatingMove,
          isPlayerTurn: isPlayerTurn,
          isFinished: isFinished,
          currentEval: currentEval,
          showSuggestion: showSuggestion,
          onToggleSuggestion: onToggleSuggestion,
        ),
        SizedBox(height: short ? 4 : 8),
        playerRow,
      ],
    );
  }
}
