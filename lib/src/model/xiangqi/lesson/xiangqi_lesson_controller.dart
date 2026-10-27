import 'dart:async';

import 'package:dartchess/dartchess.dart' show Chess;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart'
    show xiangqiEngineProvider;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:logging/logging.dart';

part 'xiangqi_lesson_controller.freezed.dart';

final _logger = Logger('XiangqiLesson');

enum XiangqiLessonSaveState() {
  idle,
  saving,
  saved,
  failed,
}

final xiangqiLessonSaveStateProvider = NotifierProvider.autoDispose
    .family<XiangqiLessonSaveController, XiangqiLessonSaveState, String>(
      XiangqiLessonSaveController.new,
      name: 'XiangqiLessonSaveStateProvider',
    );

class XiangqiLessonSaveController(final String chapterId) extends Notifier<XiangqiLessonSaveState> {
  @override
  XiangqiLessonSaveState build() {
    ref.watch(xiangqiAccountGenerationProvider);
    return XiangqiLessonSaveState.idle;
  }

  void saving() => state = XiangqiLessonSaveState.saving;
  void saved() => state = XiangqiLessonSaveState.saved;
  void failed() => state = XiangqiLessonSaveState.failed;
  void reset() => state = XiangqiLessonSaveState.idle;
}

/// How long the chapter waits before playing the other side's move itself.
///
/// The site's own player waits 400 ms, measured off its bundle, and the number is for the reader:
/// a move that lands in the same frame as the one before it reads as one move.
const Duration kXiangqiLessonReplyDelay = Duration(milliseconds: 400);

/// How long a wrong move stays on the board before it is taken back.
const Duration kXiangqiLessonWrongMoveDelay = Duration(milliseconds: 900);

/// How hard the engine thinks about a `multi` chapter's move.
///
/// The site's own player asks for `movetime 1000 depth 12` with `MultiPV 3`; the numbers are the
/// same here, and the depth is what makes the answer stable rather than the time.
const int kXiangqiLessonEngineDepth = 12;
const Duration kXiangqiLessonEngineTime = Duration(seconds: 1);

/// How many lines the engine is asked for.
///
/// Three, because that is what the chapter's own judgement reads: it compares the top three lines'
/// scores against each other and against the move played. See [_isGoodMove].
const int kXiangqiLessonMultiPv = 3;

/// The engine's own margin, in centipawns, for "this line is clearly better than that one".
///
/// The site's own player uses 500, and it is not a strength threshold — it is a *separation*
/// threshold, asked of two lines of the same search.
const int kXiangqiLessonLineGap = 500;

/// The win rate, in per cent, above which the site's own player calls a position won.
const int kXiangqiLessonWinningRate = 95;

/// One attempt at one chapter.
@freezed
sealed class const XiangqiChapterState._() with _$XiangqiChapterState {
  const factory({
    required XiangqiChapter chapter,

    /// The board at each point of the chapter, oldest first: `positions[0]` is the chapter's own
    /// position and `positions[i]` is the board after step `i`.
    ///
    /// That is [cursor] plus one entries, or one more while a wrong move is being shown — the wrong
    /// move is on the board and has not been counted as a step.
    required IList<XiangqiPosition> positions,

    /// Which step the chapter is on: 0 is the opening placeholder, and `cursor` is the step whose
    /// move has just been played.
    @Default(0) int cursor,

    /// The piece the reader has picked up, if any.
    XiangqiSquare? selected,

    /// The move the reader just got wrong, if any. It stays on the board until it is taken back.
    XiangqiMove? wrongMove,

    /// Whether the engine is being asked about a `multi` chapter's move.
    @Default(false) bool isVerifying,

    /// Whether the whole script has been played.
    @Default(false) bool isSolved,

    /// The move the reader asked to be shown, or null.
    XiangqiMove? hint,
  }) = _XiangqiChapterState;

  /// The board as it stands, which is the last one: the wrong move included, while it is being
  /// shown.
  XiangqiPosition get position => positions.last;

  /// The step the reader is being asked for, or null when the script is done.
  XiangqiChapterStep? get nextStep =>
      cursor + 1 < chapter.steps.length ? chapter.steps[cursor + 1] : null;

  /// Whether the board takes the reader's moves at all.
  bool get isPlayable => !isSolved && !isVerifying && wrongMove == null && chapter.position != null;

  /// The move the chapter wants next, or null when there is none.
  XiangqiMove? get expectedMove => nextStep?.move;

  /// Where the piece the reader has picked up may go.
  ///
  /// The piece's own moves and not the side to move's legal ones: a lesson's script is not a game,
  /// and the site's own lesson board lets the reader pick up either side's piece and play the move
  /// the chapter asks for. See [rules.pieceMoves], which is where that is written down.
  IList<XiangqiMove> get selectedMoves =>
      selected == null ? const IListConst([]) : rules.pieceMoves(position, selected!);

  /// The hints to draw for the step being asked for.
  ///
  /// **The step's own hints, not the next one's**: the arrows and points on step `i` are about the
  /// move step `i + 1` wants, which is why the placeholder carries the opening hints.
  IList<XiangqiChapterArrow> get arrows =>
      nextStep == null ? const IListConst([]) : chapter.steps[cursor].arrows;

  /// The points the chapter highlights for the step being asked for.
  IList<XiangqiSquare> get intersections =>
      nextStep == null ? const IListConst([]) : chapter.steps[cursor].intersections;
}

/// The chapter being played, one at a time.
///
/// ## The two ways a move is judged
///
/// A chapter says which it wants in `answer_type`, and the two are not variations on one rule:
///
/// * **`single`** is an equality. The move played is the move the script names, or it is wrong —
///   measured on 2026-10-16, every chapter the one account could read was this kind, and the site's
///   own player does exactly this comparison (`e.uci === Pn[curMoveIndex + 1].uci`).
/// * **`multi`** is a judgement. The site's player asks its engine for three lines and accepts the
///   move when it is the best one, or when the top lines are close enough together that the move
///   played is as good as any of them — see [_isGoodMove], which is that rule written out.
///
/// ## Who plays the other side
///
/// The chapter does. A script is a line being demonstrated and not a game, so it can have two moves
/// for the same side in a row: the player plays whatever step comes next when it is not the
/// reader's, after [kXiangqiLessonReplyDelay].
final xiangqiChapterControllerProvider = NotifierProvider.autoDispose
    .family<XiangqiChapterController, XiangqiChapterState, XiangqiChapter>(
      XiangqiChapterController.new,
      name: 'XiangqiChapterControllerProvider',
    );

class XiangqiChapterController(final XiangqiChapter chapter) extends Notifier<XiangqiChapterState> {
  Timer? _reply;
  Timer? _revert;

  /// Which run of the chapter this is, so that an answer from a superseded one is dropped.
  int _generation = 0;

  @override
  XiangqiChapterState build() {
    ref.watch(xiangqiAccountGenerationProvider);
    ref.watch(xiangqiLessonSaveStateProvider(chapter.id).notifier);
    _generation++;
    ref.onDispose(() {
      _reply?.cancel();
      _revert?.cancel();
      _generation++;
    });

    final start = chapter.position ?? XiangqiPosition.initial();
    return XiangqiChapterState(chapter: chapter, positions: IList([start]));
  }

  /// Picks up the piece on [square], or plays the picked-up piece onto it.
  void clearSelection() => state = state.copyWith(selected: null);

  void movePiece(XiangqiSquare from, XiangqiSquare to) {
    if (!state.isPlayable) return;
    final move = XiangqiMove(from, to);
    if (!rules.pieceMoves(state.position, from).contains(move)) return;
    state = state.copyWith(selected: null);
    _play(move);
  }

  void tapSquare(XiangqiSquare square) {
    if (!state.isPlayable) return;

    final selected = state.selected;
    if (selected != null && state.selectedMoves.any((move) => move.to == square)) {
      _play(XiangqiMove(selected, square));
      return;
    }
    // Either side's piece, for the reason [selectedMoves] gives: the chapter's script decides what
    // is playable here, not the position's turn.
    final piece = state.position.pieceAt(square);
    state = state.copyWith(selected: piece != null && selected != square ? square : null);
  }

  /// Shows the move the chapter wants next.
  void showHint() {
    final move = state.expectedMove;
    if (move == null || !state.isPlayable) return;
    state = state.copyWith(hint: move);
  }

  /// Retries saving a chapter that was solved locally but not acknowledged by the server.
  Future<void> retryComplete() async {
    if (!state.isSolved ||
        ref.read(xiangqiLessonSaveStateProvider(chapter.id)) != XiangqiLessonSaveState.failed) {
      return;
    }
    await _markComplete();
  }

  /// Takes a wrong move back, so the reader can try again.
  void undoWrongMove() {
    final wrong = state.wrongMove;
    if (wrong == null) return;
    _revert?.cancel();
    _revert = null;
    state = state.copyWith(
      positions: state.positions.sublist(0, state.positions.length - 1),
      wrongMove: null,
      selected: null,
    );
  }

  /// Takes the reader's last correct move back, which is the whole of what "undo" means here.
  void undo() {
    if (state.cursor == 0 || state.isVerifying) {
      return;
    }
    _reply?.cancel();
    _reply = null;
    _generation++;
    ref.read(xiangqiLessonSaveStateProvider(chapter.id).notifier).reset();
    state = state.copyWith(
      positions: state.positions.sublist(0, state.cursor),
      cursor: state.cursor - 1,
      selected: null,
      wrongMove: null,
      hint: null,
      isSolved: false,
    );
  }

  void _play(XiangqiMove move) {
    final expected = state.expectedMove;
    if (expected == null) return;

    // The script's own move is never judged: the site's player accepts it whatever the chapter's
    // `answer_type` says, and a chapter that asked for the engine to judge its own line would be
    // asking a question it already knows the answer to.
    if (move == expected) {
      _accept(move);
      return;
    }

    if (chapter.answerType == XiangqiChapterAnswerType.single) {
      // The move goes on the board before it is called wrong, so that the reader sees what they
      // played rather than a piece that springs back with nothing said. [undoWrongMove] is what
      // takes it off again, and it is the same call the `multi` branch below ends in.
      state = state.copyWith(
        positions: state.positions.add(rules.playForced(state.position, move)),
      );
      _reject(move);
      return;
    }

    // A `multi` chapter is judged by the engine, and the judgement is asynchronous: the move is put
    // on the board while it runs so that the reader sees what they played, and taken back if the
    // answer is no.
    state = state.copyWith(selected: null, hint: null, isVerifying: true);
    unawaited(_verify(move));
  }

  Future<void> _verify(XiangqiMove move) async {
    final generation = ++_generation;
    final before = state.position;
    final after = rules.playForced(before, move);
    // The board shows the move while the engine thinks, exactly as the site's own player does.
    state = state.copyWith(positions: state.positions.add(after));

    bool good;
    try {
      good = await _isGoodMove(before, move);
    } on Object catch (error, stackTrace) {
      _logger.warning('The lesson engine could not judge a move', error, stackTrace);
      // An engine that cannot answer is not a wrong move: the reader is let through rather than
      // told they were wrong by a search that never ran.
      good = true;
    }
    if (generation != _generation || !ref.mounted) return;

    if (good) {
      state = state.copyWith(cursor: state.cursor + 1, isVerifying: false, selected: null);
      _afterAccepted();
    } else {
      state = state.copyWith(isVerifying: false);
      _reject(move);
    }
  }

  /// Asks the engine whether [move] is good enough for the chapter.
  ///
  /// The rule is the site's own player's, thresholds and all — see `xiangqi-com-re/docs/lesson.md`,
  /// which is where the bundle it was read out of is written down:
  ///
  /// 1. Ask for [kXiangqiLessonMultiPv] lines of the position **before** the move.
  /// 2. Fewer than three lines means the search did not get far enough to judge anything, and the
  ///    move is accepted.
  /// 3. When the best line is more than [kXiangqiLessonLineGap] centipawns better than the second,
  ///    the move has to be the best one.
  /// 4. When the second is that much better than the third, the move has to be one of the top two.
  /// 5. Otherwise the lines are close together, and the move is accepted.
  Future<bool> _isGoodMove(XiangqiPosition before, XiangqiMove move) async {
    final engine = await ref.read(xiangqiEngineProvider.future);
    final search = engine.search(
      SearchRequest(
        initialPosition: Chess.initial,
        moves: const IListConst([]),
        variant: Variant.standard,
        limit: const SearchLimit.movetimeAndDepth(
          duration: kXiangqiLessonEngineTime,
          depth: kXiangqiLessonEngineDepth,
        ),
        fenOverride: before.toFen(),
        multiPv: kXiangqiLessonMultiPv,
        game: this,
      ),
    );

    final scores = <int?>[];
    final bestMoves = <String?>[];
    final subscription = search.infos.listen((info) {
      final index = info.multiPv - 1;
      if (index < 0 || index >= kXiangqiLessonMultiPv) return;
      while (scores.length <= index) {
        scores.add(null);
        bestMoves.add(null);
      }
      scores[index] = info.cp;
      bestMoves[index] = info.pv.firstOrNull;
    });
    await search.bestMove;
    await subscription.cancel();

    if (scores.length < 3 || scores[0] == null || scores[1] == null || scores[2] == null) {
      return true;
    }
    final first = scores[0]!;
    final second = scores[1]!;
    final third = scores[2]!;
    final played = move.iccs;

    if ((first - second).abs() > kXiangqiLessonLineGap) {
      return played == bestMoves[0];
    }
    if ((second - third).abs() > kXiangqiLessonLineGap) {
      return played == bestMoves[0] || played == bestMoves[1];
    }
    return true;
  }

  /// Plays [move] on the board and moves the chapter on.
  ///
  /// [scripted] is a move the chapter plays itself rather than one the reader played: the two are
  /// applied the same way, because a lesson's script is not a game and neither is judged by the
  /// rules — see [rules.playForced].
  void _accept(XiangqiMove move, {bool scripted = false}) {
    state = state.copyWith(
      positions: state.positions.add(rules.playForced(state.position, move)),
      cursor: state.cursor + 1,
      selected: null,
      hint: null,
      wrongMove: null,
    );
    _afterAccepted();
  }

  /// What happens once a move is on the board: the other side moves, or the chapter is done.
  void _afterAccepted() {
    if (state.nextStep == null) {
      state = state.copyWith(isSolved: true);
      unawaited(_markComplete());
      return;
    }
    // Whether the chapter plays the next step itself.
    //
    // The rule is the site's own, read off its player: it plays step `n + 1` when the step just
    // played says what comes next (`next_move` is not null) **and** the step about to be played
    // says that the side to move after it is the reader's. The second half is the whole of the
    // judgement: a step after which it is the reader's turn again is a step the reader did not
    // make, so it is the other side's and the chapter makes it.
    final next = state.nextStep;
    final played = state.chapter.steps[state.cursor];
    final nextIsReader = played.nextSide == null || next?.nextSide != state.chapter.startSide;
    if (nextIsReader) return;

    _reply?.cancel();
    _reply = Timer(kXiangqiLessonReplyDelay, () {
      if (!ref.mounted) return;
      final move = state.expectedMove;
      if (move == null) return;
      _accept(move, scripted: true);
    });
  }

  /// Marks [move] as wrong. It is already on the board: the caller put it there, and [undoWrongMove]
  /// is what takes it off.
  void _reject(XiangqiMove move) {
    state = state.copyWith(selected: null, hint: null, wrongMove: move);
    _revert?.cancel();
    _revert = Timer(kXiangqiLessonWrongMoveDelay, () {
      if (!ref.mounted) return;
      if (state.wrongMove == move) undoWrongMove();
    });
  }

  /// Tells the server the chapter is done.
  ///
  /// Saving is separate from solving: failed writes leave the solved board available for retry.
  Future<void> _markComplete() async {
    if (ref.read(xiangqiLessonSaveStateProvider(chapter.id)) == XiangqiLessonSaveState.saving) {
      return;
    }
    final generation = _generation;
    final account = ref.read(xiangqiAccountGenerationProvider);
    final alive = ref.keepAlive();
    final save = ref.read(xiangqiLessonSaveStateProvider(chapter.id).notifier);
    save.saving();
    try {
      await ref.read(xiangqiLessonRepositoryProvider).completeChapter(chapter.id);
      if (ref.mounted &&
          generation == _generation &&
          account == ref.read(xiangqiAccountGenerationProvider)) {
        save.saved();
        ref.invalidate(xiangqiChaptersProvider);
        ref.invalidate(xiangqiTopicsProvider);
        ref.invalidate(xiangqiTopicProvider);
      }
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not mark a lesson chapter complete', error, stackTrace);
      if (ref.mounted &&
          generation == _generation &&
          account == ref.read(xiangqiAccountGenerationProvider)) {
        save.failed();
      }
    } finally {
      alive.close();
    }
  }
}
