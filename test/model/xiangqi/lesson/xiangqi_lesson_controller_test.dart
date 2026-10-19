// Tests for playing a lesson chapter.
//
// **The rules pinned here were read off the site's own player**, and not guessed: its bundle's
// lesson chunk decides who plays each step of a script, and the shapes below are the ones its own
// 418 chapters are written in — see `xiangqi-com-re/docs/lesson.md`, which is where the reading is
// written down. Every position is this file's own, and no id, move or position is a capture's.
//
// The engine is not involved: every chapter here is a `single` one, which is the kind the site's
// whole first topic is made of, and the `multi` half of the controller is the engine's business —
// its thresholds are pinned in the doc rather than here.

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

import '../../../test_container.dart';

/// The move written [iccs], which is also how Pikafish writes one.
XiangqiMove move(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// One step of a script: a move, and what the wire would say about the side to move after it.
XiangqiChapterStep step(String? iccs, {String? nextMove}) =>
    XiangqiChapterStep(move: iccs == null ? null : move(iccs), nextMove: nextMove);

/// A chapter of a lesson, with the fields the controller reads.
///
/// [fen] is written the way the wire writes one — `r` for red, which is not the letter this app's
/// own positions use — and goes through the same translation a real chapter's does, so that the
/// tests below are about a chapter and not about a position.
XiangqiChapter chapter({
  String id = 'AbCdEf',
  String fen = '9/9/9/9/9/9/9/9/9/8R r - - 0 1',
  required List<XiangqiChapterStep> steps,
  XiangqiChapterAnswerType answerType = XiangqiChapterAnswerType.single,
  bool autoTransition = false,
}) => XiangqiChapter(
  id: id,
  order: 1,
  description: 'What it teaches',
  position: xiangqiChapterPositionOf(fen),
  steps: steps.lock,
  answerType: answerType,
  autoTransition: autoTransition,
  flipBoard: false,
  isCompleted: false,
);

/// The chapter being played, and the container it lives in.
class LessonHarness(final ProviderContainer container, final XiangqiChapter chapter) {
  XiangqiChapterController get controller =>
      container.read(xiangqiChapterControllerProvider(chapter).notifier);

  XiangqiChapterState get state => container.read(xiangqiChapterControllerProvider(chapter));
}

Future<LessonHarness> makeHarness(XiangqiChapter chapter) async {
  final container = await makeContainer();
  // The controller is `autoDispose`, so a container that only *reads* it lets it go the moment the
  // test awaits anything, and the next read hands back a chapter that has not been played. A
  // listener is what a screen is, and what keeps one chapter's state for the length of a test.
  final subscription = container.listen(xiangqiChapterControllerProvider(chapter), (_, _) {});
  addTearDown(subscription.close);
  return LessonHarness(container, chapter);
}

/// A chapter whose script is one red chariot move, and whose step says black is next.
///
/// This is the shape of the site's very first chapter, and the one the whole first topic is made
/// of: the reader plays the move and the chapter ends.
XiangqiChapter chariotChapter() => chapter(
  steps: [
    step(null),
    step('i0i9', nextMove: 'b'),
  ],
);

void main() {
  group('a single chapter', () {
    test('is solved by playing the move its script names', () async {
      final harness = await makeHarness(chariotChapter());
      expect(harness.state.isSolved, isFalse);
      expect(harness.state.expectedMove, move('i0i9'));

      harness.controller.tapSquare(XiangqiSquare.parse('i0')!);
      expect(harness.state.selected, XiangqiSquare.parse('i0'));
      // The piece's own moves, which for a chariot is the whole file it stands on.
      expect(harness.state.selectedMoves, contains(move('i0i9')));

      harness.controller.tapSquare(XiangqiSquare.parse('i9')!);
      expect(harness.state.isSolved, isTrue);
      expect(harness.state.cursor, 1);
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('i9')!), isNotNull);
    });

    test('refuses a move that is not the one it names, and takes it back', () async {
      final harness = await makeHarness(chariotChapter());
      harness.controller.tapSquare(XiangqiSquare.parse('i0')!);
      harness.controller.tapSquare(XiangqiSquare.parse('i4')!);

      // The move is on the board and marked wrong, so that the reader sees what they played.
      expect(harness.state.wrongMove, move('i0i4'));
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('i4')!), isNotNull);
      expect(harness.state.isSolved, isFalse);

      // And it comes off again by itself, which is what makes the chapter playable at all.
      await Future<void>.delayed(kXiangqiLessonWrongMoveDelay + const Duration(milliseconds: 200));
      expect(harness.state.wrongMove, isNull);
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('i4')!), isNull);
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('i0')!), isNotNull);
      expect(harness.state.expectedMove, move('i0i9'));
    });

    test('shows the move it wants when it is asked for a hint', () async {
      final harness = await makeHarness(chariotChapter());
      expect(harness.state.hint, isNull);
      harness.controller.showHint();
      expect(harness.state.hint, move('i0i9'));
      // Asking for a hint is not playing the move: the board is where it was.
      expect(harness.state.cursor, 0);
    });

    test('takes the last move back when it is undone', () async {
      final harness = await makeHarness(chariotChapter());
      harness.controller.tapSquare(XiangqiSquare.parse('i0')!);
      harness.controller.tapSquare(XiangqiSquare.parse('i9')!);
      expect(harness.state.isSolved, isTrue);

      harness.controller.undo();
      expect(harness.state.cursor, 0);
      expect(harness.state.isSolved, isFalse);
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('i0')!), isNotNull);
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('i9')!), isNull);
    });
  });

  group('who plays the other side', () {
    test("the chapter plays the move its script says is the other side's", () async {
      // Red horse, black horse, red cannon: the shape 29 of the site's chapters are written in.
      final harness = await makeHarness(
        chapter(
          fen: kXiangqiInitialFen,
          steps: [
            step(null),
            step('b0c2', nextMove: 'b'),
            step('b9c7', nextMove: 'r'),
            step('h2e2', nextMove: 'b'),
          ],
        ),
      );

      harness.controller.tapSquare(XiangqiSquare.parse('b0')!);
      harness.controller.tapSquare(XiangqiSquare.parse('c2')!);
      expect(harness.state.cursor, 1);
      // The reply is not on the board yet: the chapter waits, so that a move that lands in the same
      // frame as the one before it does not read as one move.
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('b9')!), isNotNull);

      await Future<void>.delayed(kXiangqiLessonReplyDelay + const Duration(milliseconds: 200));
      expect(harness.state.cursor, 2);
      expect(harness.state.position.pieceAt(XiangqiSquare.parse('c7')!), isNotNull);
      expect(harness.state.expectedMove, move('h2e2'));
    });

    test('the reader plays the whole line when the steps do not say whose move is next', () async {
      // Two red chariot moves in a row with no `next_move` anywhere: measured on 2026-10-19, this
      // is how the site writes a line it wants the reader to walk by hand.
      final harness = await makeHarness(chapter(steps: [step(null), step('i0i5'), step('i5i9')]));

      harness.controller.tapSquare(XiangqiSquare.parse('i0')!);
      harness.controller.tapSquare(XiangqiSquare.parse('i5')!);
      expect(harness.state.cursor, 1);

      await Future<void>.delayed(kXiangqiLessonReplyDelay + const Duration(milliseconds: 200));
      // Nothing moved by itself, and the reader is asked for the second move.
      expect(harness.state.cursor, 1);
      expect(harness.state.expectedMove, move('i5i9'));

      // Which is a red move while it is black's turn by the rules — the site's own lesson board
      // takes it, and so does this one.
      harness.controller.tapSquare(XiangqiSquare.parse('i5')!);
      harness.controller.tapSquare(XiangqiSquare.parse('i9')!);
      expect(harness.state.isSolved, isTrue);
    });

    test("the reader may pick up the other side's piece", () async {
      final harness = await makeHarness(
        chapter(
          fen: kXiangqiInitialFen,
          steps: [
            step(null),
            step('b0c2', nextMove: 'b'),
            step('b9c7', nextMove: 'r'),
            step('h2e2', nextMove: 'b'),
          ],
        ),
      );
      harness.controller.tapSquare(XiangqiSquare.parse('b0')!);
      harness.controller.tapSquare(XiangqiSquare.parse('c2')!);
      await Future<void>.delayed(kXiangqiLessonReplyDelay + const Duration(milliseconds: 200));
      expect(harness.state.cursor, 2);

      // The chapter played black's reply, and it is red's turn again by the rules; the reader may
      // still pick black's other horse up, because a lesson is not a game.
      harness.controller.tapSquare(XiangqiSquare.parse('h9')!);
      expect(harness.state.selected, XiangqiSquare.parse('h9'));
      expect(harness.state.selectedMoves, contains(move('h9g7')));
    });
  });

  group('the hints a step carries', () {
    test("are the ones for the step being asked for, not the next one's", () async {
      // The placeholder carries the opening hints, which is the whole reason it is kept: the arrows
      // on step `i` are about the move step `i + 1` wants, so the board draws the placeholder's
      // while the first move is being asked for, and the first step's after it.
      final opening = XiangqiChapterArrow(
        from: XiangqiSquare.parse('i0')!,
        to: XiangqiSquare.parse('i9')!,
        color: '#327EE2',
      );
      final harness = await makeHarness(
        chapter(
          steps: [
            XiangqiChapterStep(move: null, arrows: IList([opening])),
            XiangqiChapterStep(
              move: move('i0i9'),
              nextMove: 'b',
              intersections: IList([XiangqiSquare.parse('i9')!]),
            ),
          ],
        ),
      );

      expect(harness.state.arrows, [opening]);
      expect(harness.state.intersections, isEmpty);

      harness.controller.tapSquare(XiangqiSquare.parse('i0')!);
      harness.controller.tapSquare(XiangqiSquare.parse('i9')!);
      // Solved, so nothing is being asked for and nothing is drawn.
      expect(harness.state.arrows, isEmpty);
      expect(harness.state.intersections, isEmpty);
    });
  });
}
