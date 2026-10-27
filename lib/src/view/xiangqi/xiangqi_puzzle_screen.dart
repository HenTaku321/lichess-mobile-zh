import 'dart:async';

import 'package:chessground/chessground.dart' show BrightnessHueFilter;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/quota/xiangqi_quota.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_notation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/service/move_feedback.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/auth/xiangqi_login_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:material_ui/material_ui.dart';

/// Solves xiangqi.com's puzzles, on this app's own board.
///
/// A screen of its own rather than a mode of the chess puzzle screen, for the reason every xiangqi
/// screen here is: the board is nine files by ten ranks and the pieces are not chess pieces, so
/// nothing of the chess puzzle screen's own machinery survives the crossing. What is shared is the
/// arrangement — a board, a move list, a row of actions — and that is [XiangqiGameLayout]'s.
///
/// ## What a puzzle is, and who moves first
///
/// A xiangqi.com puzzle is a position with a blunder already in it and the solver on the other side
/// of it. The app plays the blunder itself, and from then on the solver plays their own moves and
/// the app answers for the opponent out of the puzzle's own answer — see [XiangqiPuzzle] and
/// [XiangqiPuzzleController]. What the solver is asked for is [XiangqiPuzzle.fullMoves] moves, and
/// the attempt is over when the whole line is on the board.
///
/// ## What this screen does not do
///
/// There is no theme or tag filter: the queue it draws from is every theme at every rating, which is
/// what [xiangqiDefaultPuzzleSearch] says. The filter is a screen of its own — the server has the
/// vocabulary for it (`GET /api/puzzle/get_themes_tags`) and the endpoint takes it
/// (`POST /api/puzzle/search`) — and this wave is the solving loop.
class const XiangqiPuzzleScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiPuzzleScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText(context.l10n.mobileXiangqiPuzzle),
        actions: [
          IconButton(
            tooltip: context.l10n.preferencesPreferences,
            icon: const Icon(Icons.settings),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (context) => Consumer(
                builder: (context, ref, _) => SafeArea(
                  child: SwitchSettingTile(
                    title: Text(context.l10n.puzzleJumpToNextPuzzleImmediately),
                    value: ref.watch(puzzlePreferencesProvider).autoNext,
                    onChanged: (value) =>
                        ref.read(puzzlePreferencesProvider.notifier).setAutoNext(value),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _Body(key: ValueKey(ref.watch(xiangqiAccountGenerationProvider))),
    );
  }
}

class const _Body({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState() extends ConsumerState<_Body> {
  XiangqiPuzzle? _replacement;
  int _replacementAttempt = 0;

  void _replace(XiangqiPuzzle puzzle) {
    setState(() {
      _replacement = puzzle;
      _replacementAttempt++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // **A real account, and the server is why.** Finding a puzzle and reading one are open to
    // anybody — measured on 2026-10-16, both answered `200` with no token at all — but *solving* one
    // is not: `POST /api/puzzle/<id>/complete` and `POST /api/quota/usage` both answer
    // `401 Missing Authorization Header` without a token and `401 …invalid user data for guest…`
    // with a guest's. A solver who could only fetch would be a solver who could not submit, so the
    // whole screen asks for an account rather than half of it asking and half of it failing.
    //
    // The way in is offered rather than taken: a guest account is a real account on somebody else's
    // service, and making one behind the user's back is not this screen's to do.
    if (!ref.watch(isXiangqiLoggedInProvider)) {
      return const _SignInPrompt();
    }

    if (_replacement case final puzzle?) {
      return _PuzzleBody(
        key: ValueKey((puzzle.id, _replacementAttempt)),
        puzzle: puzzle,
        attempt: _replacementAttempt,
        onNext: _replace,
      );
    }

    final search = ref.watch(xiangqiPuzzleSearchProvider(xiangqiDefaultPuzzleSearch));
    return search.when(
      // A refresh is a solver asking for the next puzzle, and the board they just finished is not
      // what they are waiting for. See [_PuzzleBody.nextPuzzle].
      skipLoadingOnRefresh: false,
      data: (id) => id == null ? const _NoPuzzle() : _Puzzle(id: id, onNext: _replace),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stackTrace) => _Failed(
        onRetry: () => ref.invalidate(xiangqiPuzzleSearchProvider(xiangqiDefaultPuzzleSearch)),
      ),
    );
  }
}

/// The puzzle [id] names, once it has arrived.
class const _Puzzle({required final String id, required final ValueChanged<XiangqiPuzzle> onNext})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzle = ref.watch(xiangqiPuzzleProvider(id));
    return puzzle.when(
      data: (puzzle) => _PuzzleBody(key: ValueKey(puzzle.id), puzzle: puzzle, onNext: onNext),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stackTrace) => _Failed(
        onRetry: () => ref.invalidate(xiangqiPuzzleProvider(id)),
        // The one refusal that is not a failure of the screen but of the day's allowance. The
        // server answers it with the position in the body, and that case never reaches here — see
        // `xiangqiPuzzleProvider` — so this is the shape that carries nothing to draw.
        quotaExceeded: error is XiangqiQuotaExceededException,
      ),
    );
  }
}

/// One puzzle, and the attempt at it.
class const _PuzzleBody({
  required final XiangqiPuzzle puzzle,
  final int attempt = 0,
  required final ValueChanged<XiangqiPuzzle> onNext,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PuzzleBody> createState() => _PuzzleBodyState();
}

class _PuzzleBodyState() extends ConsumerState<_PuzzleBody> {
  /// The square the solver has picked up, if any.
  XiangqiSquare? _selected;

  bool _autoAdvanced = false;
  bool _loadingNext = false;
  bool _active = true;
  int _requestGeneration = 0;
  final Set<Timer> _feedbackTimers = {};

  @override
  void dispose() {
    for (final timer in _feedbackTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  /// The attempt this screen is showing.
  XiangqiPuzzleAttemptKey get _key => (puzzle: widget.puzzle, attempt: widget.attempt);

  @override
  Widget build(BuildContext context) {
    final puzzle = widget.puzzle;
    final provider = xiangqiPuzzleControllerProvider(_key);
    ref.listen(provider, (previous, next) {
      if (!_active || previous == null || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (next.wrongMove != null && previous.wrongMove == null) {
        unawaited(ref.read(soundServiceProvider).play(Sound.error));
        return;
      }
      if (next.moves.length != previous.moves.length + 1) return;
      final move = next.moves.last;
      final before = previous.position;
      final isCapture = before.pieceAt(move.to) != null;
      final isCheck = rules.isCheck(next.position);
      void playFeedback() {
        if (!context.mounted || !_active || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        final feedback = ref.read(moveFeedbackServiceProvider);
        if (isCapture) {
          feedback.captureFeedback(null, check: isCheck);
        } else {
          feedback.moveFeedback(check: isCheck);
        }
      }

      final delay = ref.read(boardPreferencesProvider).pieceAnimationDuration ~/ 2;
      if (delay <= Duration.zero) {
        playFeedback();
      } else {
        late final Timer timer;
        timer = Timer(delay, () {
          _feedbackTimers.remove(timer);
          playFeedback();
        });
        _feedbackTimers.add(timer);
      }
    });
    ref.listen(provider, (previous, next) {
      if (_autoAdvanced ||
          !_active ||
          previous?.phase == next.phase ||
          next.phase != XiangqiPuzzlePhase.recorded ||
          next.recordedStatus != XiangqiPuzzleAttemptStatus.solved ||
          !(ModalRoute.of(context)?.isCurrent ?? true) ||
          !ref.read(puzzlePreferencesProvider).autoNext) {
        return;
      }
      _autoAdvanced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_autoAdvanced || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        unawaited(nextPuzzle());
      });
    });
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final style = XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors);

    // The solver's own side at the bottom of the screen, which is what a puzzle wants: the line is
    // theirs to find, and a board turned around would ask them to find it upside down.
    final orientation = puzzle.playerSide;

    final selected = _selected;
    final selectedMoves = selected == null
        ? const IListConst<XiangqiMove>([])
        : rules.legalMovesFrom(state.position, selected);

    return FocusDetector(
      onFocusGained: () => _active = true,
      onFocusLost: () {
        _active = false;
        _requestGeneration++;
        for (final timer in _feedbackTimers) {
          timer.cancel();
        }
        _feedbackTimers.clear();
      },
      child: SafeArea(
        child: XiangqiGameLayout(
          board: BrightnessHueFilter(
            brightness: boardPrefs.brightness,
            hue: boardPrefs.hue,
            child: XiangqiBoard(
              position: state.position,
              orientation: orientation,
              selected: selected,
              moves: boardPrefs.showLegalMoves ? selectedMoves : const IListConst([]),
              lastMove: state.lastMove,
              onTapSquare: _onTapSquare,
              onDragMove: (from, to) {
                final move = XiangqiMove(from, to);
                if (!state.isPlayable ||
                    !state.isSolverTurn ||
                    !rules.isLegal(state.position, move)) {
                  return;
                }
                setState(() => _selected = null);
                controller.onUserMove(move);
              },
              onCancelInteraction: () => setState(() => _selected = null),
              animationDuration: boardPrefs.pieceAnimationDuration,
              showCoordinates: boardPrefs.coordinates,
              showLastMove: boardPrefs.boardHighlights,
              showBorder: boardPrefs.showBorder,
              hint: state.hint,
              arrows: state.hint == null
                  ? const IListConst([])
                  : IList([XiangqiBoardArrow(move: state.hint!)]),
              magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
              dragTargetKind: boardPrefs.dragTargetKind,
              settings: XiangqiBoardSettings.fromPreferences(boardPrefs),
              canStartDrag: (piece) =>
                  state.isPlayable && state.isSolverTurn && piece.side == state.position.turn,
              style: style,
            ),
          ),
          topTable: _PuzzleFacts(puzzle: puzzle),
          bottomTable: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SolverRow(
                side: orientation,
                style: style,
                status: _statusText(context, state),
                mistakes: state.mistakes,
                hintsUsed: state.hintsUsed,
              ),
              if (_loadingNext || state.phase == XiangqiPuzzlePhase.submitting)
                const LinearProgressIndicator(),
            ],
          ),
          moves: xiangqiGameNotation(state.positions, state.moves),
          // There is no cursor: the attempt only ever goes forwards, so the move the list marks is
          // always the one just played.
          currentMoveIndex: state.moves.length,
          onSelectMove: null,
          userActionsBar: BottomBar(
            children: [
              BottomBarButton(
                label: context.l10n.getAHint,
                onTap: state.canHint ? _hint : null,
                icon: CupertinoIcons.lightbulb,
                highlighted: state.hint != null,
              ),
              if (state.phase == XiangqiPuzzlePhase.unrecorded)
                BottomBarButton(
                  label: context.l10n.retry,
                  onTap: () => unawaited(controller.retrySubmit()),
                  icon: CupertinoIcons.arrow_clockwise,
                ),
              BottomBarButton(
                label: context.l10n.puzzleNextPuzzle,
                onTap: state.isLineComplete && !_loadingNext ? () => unawaited(nextPuzzle()) : null,
                icon: CupertinoIcons.arrow_right,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Takes a tap on [square]: picks a piece up, or plays the move to it.
  ///
  /// The order the two cases are tried in is what makes a tap on one's own piece a selection rather
  /// than a refusal: a move to the square the piece is already on is not a move, so a piece of the
  /// solver's own is picked up, and a piece of the opponent's — or an empty square — is only ever
  /// the end of a move.
  void _onTapSquare(XiangqiSquare square) {
    final state = ref.read(xiangqiPuzzleControllerProvider(_key));
    if (!state.isPlayable) return;

    final selected = _selected;
    if (selected != null) {
      final move = XiangqiMove(selected, square);
      if (rules.isLegal(state.position, move)) {
        setState(() => _selected = null);
        ref.read(xiangqiPuzzleControllerProvider(_key).notifier).onUserMove(move);
        return;
      }
    }

    final piece = state.position.pieceAt(square);
    setState(() {
      _selected =
          selected != square &&
              piece != null &&
              piece.side == state.position.turn &&
              state.isSolverTurn
          ? square
          : null;
    });
  }

  /// Asks the server for a hint, and says so when it refuses.
  Future<void> _hint() async {
    final controller = ref.read(xiangqiPuzzleControllerProvider(_key).notifier);
    try {
      final usage = await controller.hint();
      if (!mounted || usage == null || usage.allowed) return;
      // The server's answer is the only gate there is — nothing here counts hints locally — so a
      // refusal is reported as what it is rather than as a failure.
      showSnackBar(
        context,
        usage.reason == 'exhausted'
            ? context.l10n.mobileXiangqiPuzzleHintsExhausted
            : context.l10n.mobileSomethingWentWrong,
        type: SnackBarType.error,
      );
    } catch (_) {
      if (!mounted) return;
      showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
    }
  }

  /// Moves on to another puzzle.
  ///
  /// Keep the completed board until both the search and the charged fetch succeed.
  Future<void> nextPuzzle() async {
    if (_loadingNext || !ref.read(xiangqiPuzzleControllerProvider(_key)).isLineComplete) return;
    final generation = ref.read(xiangqiAccountGenerationProvider);
    final request = ++_requestGeneration;
    final repository = ref.read(xiangqiPuzzleRepositoryProvider);
    final noPuzzleMessage = context.l10n.mobileXiangqiPuzzleNoPuzzle;
    final solutionWithheldMessage = context.l10n.mobileXiangqiPuzzleSolutionWithheld;
    final failedMessage = context.l10n.mobileSomethingWentWrong;
    bool current() =>
        mounted &&
        _active &&
        request == _requestGeneration &&
        generation == ref.read(xiangqiAccountGenerationProvider) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    setState(() => _loadingNext = true);
    try {
      final id = await repository.search(xiangqiDefaultPuzzleSearch);
      if (!current()) return;
      if (id == null) {
        if (!mounted) return;
        showSnackBar(context, noPuzzleMessage);
        return;
      }
      final puzzle = await repository.fetch(id);
      if (!current()) return;
      if (puzzle.solution == null) {
        if (!mounted) return;
        showSnackBar(context, solutionWithheldMessage, type: SnackBarType.error);
        return;
      }
      widget.onNext(puzzle);
    } catch (_) {
      if (current()) {
        if (!mounted) return;
        showSnackBar(context, failedMessage, type: SnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _loadingNext = false);
    }
  }
}

/// What the solver is being asked for, and what is left of the day's puzzles.
class const _PuzzleFacts({required final XiangqiPuzzle puzzle}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final passRate = puzzle.passRate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          puzzle.title ?? context.l10n.puzzlePuzzleId(puzzle.id),
          style: TextTheme.of(context).titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          [
            context.l10n.puzzleRatingX('${puzzle.rating}'),
            // The share of attempts that got it right, which is the one number that says how hard
            // the puzzle is without saying anything about this solver.
            if (passRate != null) '${passRate.round()}%',
          ].join(' · '),
          style: TextTheme.of(context).bodyMedium?.copyWith(color: textShade(context, 0.7)),
        ),
        const _QuotaLine(),
      ],
    );
  }
}

/// How much of the day's puzzle allowance is left, as the server reports it.
///
/// A report and not a gate: nothing here refuses a request, and the line is drawn from whatever the
/// server last said — see [XiangqiQuotaState]. It draws nothing at all until that answer arrives, or
/// when the server does not report the feature, because a number this app made up would be worse
/// than no number.
class const _QuotaLine() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feature = ref.watch(
      xiangqiQuotaStateProvider.select((state) => state.value?.feature(kXiangqiQuotaPuzzles)),
    );
    if (feature == null) return const SizedBox.shrink();
    return Text(
      // The two numbers as strings, which is what every translated string in this app takes: the
      // source of truth is `translation/source/mobile.xml`, whose placeholders are `%s`, and the
      // generator types them all as `String`.
      context.l10n.mobileXiangqiPuzzleQuotaLeft('${feature.remaining}', '${feature.limit}'),
      style: TextTheme.of(context).bodySmall?.copyWith(color: textShade(context, 0.6)),
    );
  }
}

/// The solver's own row: which side they are, and how the attempt is going.
class const _SolverRow({
  required final XiangqiSide side,
  required final XiangqiBoardStyle style,
  required final String status,
  required final int mistakes,
  required final int hintsUsed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counts = mistakes > 0 || hintsUsed > 0
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mistakes > 0) _Count(icon: CupertinoIcons.xmark, value: mistakes),
              if (hintsUsed > 0) _Count(icon: CupertinoIcons.lightbulb, value: hintsUsed),
            ],
          )
        : null;
    return XiangqiPlayerRow(
      side: side,
      style: style,
      name: side.label(context.l10n),
      status: status,
      clock: counts,
    );
  }
}

class const _Count({required final IconData icon, required final int value})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16.0, color: textShade(context, 0.6)),
          const SizedBox(width: 2.0),
          Text('$value', style: TextTheme.of(context).bodyMedium),
        ],
      ),
    );
  }
}

/// What the solver is being asked for, or how it went.
String _statusText(BuildContext context, XiangqiPuzzleAttemptState state) {
  switch (state.phase) {
    case XiangqiPuzzlePhase.solving:
      if (state.puzzle.solution == null) {
        return context.l10n.mobileXiangqiPuzzleSolutionWithheld;
      }
      if (state.wrongMove != null) {
        return context.l10n.mobileXiangqiPuzzleWrongMove;
      }
      if (!state.isSolverTurn) return '';
      return context.l10n.mobileXiangqiPuzzleFindBestMoveFor(
        state.puzzle.playerSide.label(context.l10n),
      );
    case XiangqiPuzzlePhase.submitting:
      return '${context.l10n.save} · ${context.l10n.waiting}';
    case XiangqiPuzzlePhase.recorded:
      return context.l10n.puzzleSolved;
    case XiangqiPuzzlePhase.unrecorded:
      return '${context.l10n.save} · ${context.l10n.mobileSomethingWentWrong}';
  }
}

/// The way in, for a device with no xiangqi.com session.
class const _SignInPrompt() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Styles.bodySectionPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const XiangqiPieceAvatar(side: XiangqiSide.red, size: 64),
            const SizedBox(height: 16.0),
            Text(
              context.l10n.mobileXiangqiSignIn,
              textAlign: TextAlign.center,
              style: TextTheme.of(context).bodyMedium?.copyWith(color: textShade(context, 0.7)),
            ),
            const SizedBox(height: 16.0),
            FilledButton(
              onPressed: () => Navigator.of(context).push(XiangqiLoginScreen.buildRoute()),
              child: Text(context.l10n.mobileXiangqiSignIn),
            ),
          ],
        ),
      ),
    );
  }
}

/// The queue is empty, which the server says with a message and not an error.
class const _NoPuzzle() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Styles.bodySectionPadding,
        child: Text(context.l10n.mobileXiangqiPuzzleNoPuzzle, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Something did not arrive, and there is a way to ask again.
class const _Failed({required final VoidCallback onRetry, final bool quotaExceeded = false})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Styles.bodySectionPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              quotaExceeded
                  ? context.l10n.mobileXiangqiPuzzleSolutionWithheld
                  : context.l10n.mobileSomethingWentWrong,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}
