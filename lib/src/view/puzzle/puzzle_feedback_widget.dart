import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_controller.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/string.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/widgets/training_feedback.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lichess_mobile/src/widgets/training_feedback.dart' show FeedbackTile;

class const PuzzleFeedbackWidget({
  required final Puzzle puzzle,
  required final PuzzleState state,
  required final bool onStreak,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (state.mode) {
      case PuzzleMode.view:
        final puzzleRating = context.l10n.puzzleRatingX(puzzle.puzzle.rating.toString());
        final playedXTimes = context.l10n.puzzlePlayedXTimes(puzzle.puzzle.plays).localizeNumbers();
        return FeedbackTile(
          leading: state.result == PuzzleResult.win
              ? Icon(Icons.check, size: 36, color: context.lichessColors.good)
              : null,
          title: onStreak && state.result == PuzzleResult.lose
              ? Text(
                  context.l10n.gameOver,
                  style: const TextStyle(fontSize: 24, letterSpacing: 2.0),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  state.result == PuzzleResult.win
                      ? context.l10n.puzzlePuzzleSuccess
                      : context.l10n.puzzlePuzzleComplete,
                  overflow: TextOverflow.ellipsis,
                ),
          subtitle: onStreak && state.result == PuzzleResult.lose
              ? null
              : RatingPrefAware(
                  orElse: Text('$playedXTimes.', overflow: TextOverflow.ellipsis, maxLines: 2),
                  child: Text(
                    '$puzzleRating. $playedXTimes.',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
        );
      case PuzzleMode.load:
      case PuzzleMode.play:
        if (state.feedback == PuzzleFeedback.bad) {
          return const TrainingMoveFeedbackTile(phase: TrainingFeedbackPhase.incorrect);
        } else if (state.feedback == PuzzleFeedback.good) {
          return const TrainingMoveFeedbackTile(phase: TrainingFeedbackPhase.correct);
        } else {
          return TrainingMoveFeedbackTile(
            phase: TrainingFeedbackPhase.prompt,
            promptLeading: SideToPlayPiece(side: state.pov),
            promptSubtitle: state.pov == Side.white
                ? context.l10n.puzzleFindTheBestMoveForWhite
                : context.l10n.puzzleFindTheBestMoveForBlack,
          );
        }
    }
  }
}

/// Displays the side to move's king pience on a square matching the board's theme.
class const SideToPlayPiece({required final Side side}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pieceSet = ref.watch(boardPreferencesProvider.select((value) => value.pieceSet));
    final boardPrefs = ref.watch(boardPreferencesProvider);

    final brightness = Theme.of(context).brightness;
    final piece = side == Side.white ? PieceKind.whiteKing : PieceKind.blackKing;
    final asset = pieceSet.assets[piece]!;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        BrightnessHueFilter(
          brightness: boardPrefs.brightness,
          hue: boardPrefs.hue,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4.0),
              color: brightness == Brightness.light
                  ? boardPrefs.boardTheme.colors.lightSquare
                  : boardPrefs.boardTheme.colors.darkSquare,
            ),
          ),
        ),
        Image.asset(
          asset.assetName,
          width: 48,
          height: 48,
          bundle: asset.bundle,
          package: asset.package,
        ),
      ],
    );
  }
}
