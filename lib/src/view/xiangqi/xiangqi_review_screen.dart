import 'package:chessground/chessground.dart' show BrightnessHueFilter;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/common/chess.dart' show Variant;
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/review/xiangqi_review.dart';
import 'package:lichess_mobile/src/model/xiangqi/review/xiangqi_review_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_analysis_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:material_ui/material_ui.dart';

/// A finished game on xiangqi.com, with every move of it marked up.
///
/// ## What the review is
///
/// One request, one answer, the whole game: `g_v2.review` is asked once and `game.review.success`
/// comes back carrying the engine's verdict on **every position** of the game at once — see
/// [xiangqiReviewProvider] and `xiangqi-com-re/docs/review.md`. There is no progress bar and no
/// second call, which is why this screen has no "analysing" state to draw: a review that exists is
/// a review that is complete.
///
/// ## What a move is called
///
/// The seven names are xiangqi.com's own, and so are the thresholds between them. The one this app
/// does **not** print is *brilliant*: the shipped client only reaches it after a second, cloud-side
/// verification this app does not make, and a name that cannot be justified is a name not worth
/// printing. See [xiangqiMoveClassificationOf].
///
/// ## Where the board is
///
/// The board is always drawn from red's side and never flips. A review is not a game: there is
/// nobody to face, nothing is being played, and a board that turned itself around between two moves
/// of the same game would be a board that made the reader lose their place.
class const XiangqiReviewScreen({required final String gameId, super.key}) extends ConsumerWidget {
  static Route<void> buildRoute(String gameId) =>
      buildScreenRoute(screen: XiangqiReviewScreen(gameId: gameId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText(
          '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiReview}',
        ),
      ),
      body: _Body(gameId: gameId),
    );
  }
}

class const _Body({required final String gameId}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(xiangqiReviewProvider(gameId));

    return review.when(
      data: (review) => _Review(review: review),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stackTrace) => switch (error) {
        // No session branch: a review needs none. The socket opens a guest one of its own when the
        // device has never signed in, and a guest was measured being handed a whole archived game's
        // analysis — see [xiangqiReviewProvider].
        XiangqiReviewException(reason: .offline) => _Failed(
          message: context.l10n.mobileXiangqiReviewOffline,
          onRetry: () => ref.invalidate(xiangqiReviewProvider(gameId)),
        ),
        _ => _Failed(
          message: context.l10n.mobileXiangqiReviewFailed,
          onRetry: () => ref.invalidate(xiangqiReviewProvider(gameId)),
        ),
      },
    );
  }
}

/// One game, with a cursor on it.
class const _Review({required final XiangqiReview review}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Review> createState() => _ReviewState();
}

class _ReviewState() extends ConsumerState<_Review> {
  /// Which position is on the board: an index into the game's positions, so 0 is before the first
  /// move and `moves.length` is after the last one.
  int _cursor = 0;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    // The review opens on the **last** position, which is the one a player who just finished the
    // game is looking at. The move list and the arrows are how they walk back through it.
    _cursor = widget.review.moves.length;
  }

  void _goTo(int target) {
    final clamped = target.clamp(0, widget.review.moves.length);
    if (clamped == _cursor) return;
    _animate = (clamped - _cursor).abs() == 1;
    if (_animate && widget.review.moves.isNotEmpty) {
      final index = (clamped > _cursor ? clamped - 1 : _cursor - 1).clamp(
        0,
        widget.review.moves.length - 1,
      );
      final before = widget.review.positions[index];
      final move = widget.review.moves[index];
      final sound = ref.read(soundServiceProvider);
      if (before.pieceAt(move.to) != null) {
        sound.playCaptureSound(Variant.standard);
      } else {
        sound.play(Sound.move);
      }
    }
    setState(() => _cursor = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final style = XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors);
    final cursor = _cursor.clamp(0, review.moves.length);

    // The verdict on the move that led to the position on the board, which is the move at
    // `cursor - 1`: the entry at `cursor` is the reading of the position *before* that move.
    final current = cursor == 0 ? null : review.reviews[cursor - 1];
    final evaluation = cursor == 0
        ? review.reviews.first.evaluation
        : review.reviews[cursor - 1].evaluation;

    return SafeArea(
      child: XiangqiAnalysisLayout(
        smallBoard: ref.watch(analysisPreferencesProvider).smallBoard,
        boardBuilder: (context, size, radius) => BrightnessHueFilter(
          brightness: boardPrefs.brightness,
          hue: boardPrefs.hue,
          child: XiangqiBoard(
            settings: XiangqiBoardSettings.fromPreferences(boardPrefs),
            position: review.positions[cursor],
            orientation: XiangqiSide.red,
            selected: null,
            moves: const IListConst([]),
            // A review is read, not played: no tap, no drag, and no legal-move dots, because there
            // is no move to make.
            onTapSquare: null,
            onDragMove: null,
            lastMove: cursor > 0 ? review.moves[cursor - 1] : null,
            animationDuration: _animate ? boardPrefs.pieceAnimationDuration : Duration.zero,
            showCoordinates: boardPrefs.coordinates,
            showLastMove: boardPrefs.boardHighlights,
            showBorder: boardPrefs.showBorder,
            magnifyDraggedPiece: false,
            dragTargetKind: boardPrefs.dragTargetKind,
            style: style,
          ),
        ),
        evalGauge: XiangqiEvalGauge(
          redWinProbability: evaluation.redWinProbability,
          orientation: XiangqiSide.red,
          evaluation: evaluation,
        ),
        boardHeader: _PlayerRow(
          side: XiangqiSide.black,
          player: review.black,
          accuracy: review.accuracyOf(XiangqiSide.black),
          style: style,
        ),
        boardFooter: _PlayerRow(
          side: XiangqiSide.red,
          player: review.red,
          accuracy: review.accuracyOf(XiangqiSide.red),
          style: style,
        ),
        panelHeader: _Verdict(review: review, cursor: cursor, current: current),
        moves: xiangqiGameNotation(review.positions, review.moves),
        currentMoveIndex: cursor,
        onSelectMove: _goTo,
        bottomBar: BottomBar(
          children: [
            BottomBarButton(
              label: context.l10n.mobileXiangqiReviewPrevious,
              onTap: cursor > 0 ? () => _goTo(cursor - 1) : null,
              icon: CupertinoIcons.chevron_back,
            ),
            BottomBarButton(
              label: context.l10n.mobileXiangqiReviewNext,
              onTap: cursor < review.moves.length ? () => _goTo(cursor + 1) : null,
              icon: CupertinoIcons.chevron_forward,
            ),
          ],
        ),
      ),
    );
  }
}

/// One seat of the game, with how well it played.
///
/// The accuracy is the app's own mean of the per-move numbers the review was built from, and is
/// labelled as such by being the app's own word for it — see [XiangqiReview.accuracyOf]. A side
/// that played no moves has no mean and the line is left out rather than shown as zero.
class const _PlayerRow({
  required final XiangqiSide side,
  required final XiangqiLivePlayer? player,
  required final int? accuracy,
  required final XiangqiBoardStyle style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return XiangqiPlayerRow(
      avatarSize: 24,
      compact: true,
      clockPosition: .right,
      side: side,
      style: style,
      name: player?.name,
      rating: player?.rating?.toString(),
      clock: accuracy == null
          ? null
          : Text(
              '${context.l10n.mobileXiangqiReviewAccuracy} $accuracy',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: textShade(context, 0.7)),
            ),
    );
  }
}

/// What the engine made of the move that led to the position on the board.
///
/// Nothing is drawn before the first move — there is no move to have a verdict on — and the best
/// move is only named when it is not the move that was played, because "the best move was the move
/// you played" is not a sentence worth printing on every other row.
class const _Verdict({
  required final XiangqiReview review,
  required final int cursor,
  required final XiangqiMoveReview? current,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final current = this.current;
    if (current == null) return const SizedBox.shrink();

    final best = current.bestMove;
    final bestWasDifferent = best != null && best != current.move;
    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Row(
        children: [
          Text(
            _classificationLabel(context, current.classification),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _classificationColor(context, current.classification),
            ),
          ),
          const SizedBox(width: 6.0),
          Text(
            '${current.accuracy}',
            style: TextStyle(fontSize: 14, color: textShade(context, 0.7)),
          ),
          if (bestWasDifferent) ...[
            const SizedBox(width: 8.0),
            Flexible(
              child: Text(
                context.l10n.mobileXiangqiReviewBestMoveWas(
                  xiangqiMoveNotation(review.positions[cursor - 1], best),
                ),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: textShade(context, 0.7)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The name of [classification], in the reader's own language.
String _classificationLabel(BuildContext context, XiangqiMoveClassification classification) =>
    switch (classification) {
      .brilliant => context.l10n.mobileXiangqiReviewBrilliant,
      .best => context.l10n.mobileXiangqiReviewBest,
      .excellent => context.l10n.mobileXiangqiReviewExcellent,
      .good => context.l10n.mobileXiangqiReviewGood,
      .inaccuracy => context.l10n.mobileXiangqiReviewInaccuracy,
      .mistake => context.l10n.mobileXiangqiReviewMistake,
      .blunder => context.l10n.mobileXiangqiReviewBlunder,
    };

/// The colour [classification] is drawn in.
///
/// The theme's own colours, in the order the app uses them everywhere else: the two good names take
/// the scheme's primary, the two middling ones the colour a success takes, an inaccuracy the one a
/// link takes, a mistake the brag colour and a blunder the error. A brilliant is drawn as a best
/// move, because this app never awards the name — see [XiangqiReviewScreen].
Color _classificationColor(BuildContext context, XiangqiMoveClassification classification) {
  final colors = context.lichessColors;
  return switch (classification) {
    .brilliant || .best => ColorScheme.of(context).primary,
    .excellent || .good => colors.good,
    .inaccuracy => colors.primary,
    .mistake => colors.brag,
    .blunder => colors.error,
  };
}

/// Something did not arrive, and there is a way to ask again.
class const _Failed({required final String message, required final VoidCallback onRetry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Styles.bodySectionPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16.0),
            FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}
