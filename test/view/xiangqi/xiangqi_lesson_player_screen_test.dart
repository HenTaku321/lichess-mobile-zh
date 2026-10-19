// Tests for the screen a lesson chapter is played on.
//
// The screen is driven through the board itself: a chapter is a chapter because of where its moves
// are, so a test that called the controller directly would not be testing the screen at all. The
// chapters below are written the way the wire writes them — `r` for red, `#RRGGBB` for an arrow —
// and every value is this file's own.
//
// What is pinned here is the screen's own behaviour: that the board takes the reader's moves, that a
// finished chapter says so, and that the bar at the bottom walks the lesson.

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lesson_player_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

XiangqiSquare squareAt(String name) {
  final square = XiangqiSquare.parse(name);
  if (square == null) throw ArgumentError('Not a square: $name');
  return square;
}

/// One step of a script, written as the wire writes one.
XiangqiChapterStep step(String? iccs, {String? nextMove}) =>
    XiangqiChapterStep(move: iccs == null ? null : XiangqiMove.parseIccs(iccs), nextMove: nextMove);

/// A chapter whose script is one red chariot move.
XiangqiChapter chapter({
  String id = 'AbCdEf',
  int order = 1,
  String description = 'Move the chariot',
  String fen = '9/9/9/9/9/9/9/9/9/8R r - - 0 1',
  IList<XiangqiChapterStep>? steps,
  bool autoTransition = false,
}) => XiangqiChapter(
  id: id,
  order: order,
  description: description,
  position: xiangqiChapterPositionOf(fen),
  steps: steps ?? [step(null), step('i0i9', nextMove: 'b')].lock,
  autoTransition: autoTransition,
  isCompleted: false,
);

/// Touches the point [name] names, on the board the screen drew.
Future<void> tapSquare(WidgetTester tester, String name) async {
  final box = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(box.size, showCoordinates: true);
  final board = Rect.fromCenter(center: box.center, width: geometry.width, height: geometry.height);
  await tester.tapAt(board.topLeft + geometry.centerOf(squareAt(name), .red));
  await tester.pump();
}

/// The bar button under [icon], which is how the buttons are found.
BottomBarButton barButton(WidgetTester tester, IconData icon) => tester.widget<BottomBarButton>(
  find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton)),
);

/// Opens the player on [chapters], starting at [initialIndex].
Future<void> pumpPlayer(
  WidgetTester tester, {
  required IList<XiangqiChapter> chapters,
  int initialIndex = 0,
}) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: XiangqiLessonPlayerScreen(
        lessonId: 'GhIjKl',
        lessonTitle: 'A lesson',
        chapters: chapters,
        initialIndex: initialIndex,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiLessonPlayerScreen', () {
    testWidgets('draws the chapter and takes the move it asks for', (tester) async {
      await pumpPlayer(tester, chapters: IList([chapter()]));

      expect(find.text('Move the chariot'), findsOneWidget);
      expect(find.text('Chapter 1 of 1'), findsOneWidget);
      expect(find.byType(XiangqiBoard), findsOneWidget);

      await tapSquare(tester, 'i0');
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).selected, squareAt('i0'));
      await tapSquare(tester, 'i9');

      // The chapter is done, and it says so where the reader is looking.
      expect(find.text('Great job!'), findsOneWidget);
      expect(
        tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position.pieceAt(squareAt('i9')),
        isNotNull,
      );
    });

    testWidgets('says a move is wrong, and takes it back', (tester) async {
      await pumpPlayer(tester, chapters: IList([chapter()]));

      await tapSquare(tester, 'i0');
      await tapSquare(tester, 'i4');
      expect(find.text('Not that move.'), findsOneWidget);
      // The board marks the move the reader made, rather than only saying it in words.
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).wrongMove, isNotNull);

      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Not that move.'), findsNothing);
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).wrongMove, isNull);
    });

    testWidgets("shows the chapter's own arrow and rings its points", (tester) async {
      final arrow = XiangqiChapterArrow(from: squareAt('i0'), to: squareAt('i9'), color: '#327EE2');
      await pumpPlayer(
        tester,
        chapters: IList([
          chapter(
            steps: [
              XiangqiChapterStep(
                move: null,
                arrows: IList([arrow]),
                intersections: IList([squareAt('i9')]),
              ),
              step('i0i9', nextMove: 'b'),
            ].lock,
          ),
        ]),
      );

      final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
      expect(board.arrows.single.move.iccs, 'i0i9');
      expect(board.arrows.single.color, const Color(0xFF327EE2));
      expect(board.marked, [squareAt('i9')]);
    });

    testWidgets('walks the lesson with the bar at the bottom', (tester) async {
      await pumpPlayer(
        tester,
        chapters: IList([
          chapter(id: 'one', order: 1, description: 'The first one'),
          chapter(id: 'two', order: 2, description: 'The second one'),
        ]),
      );

      expect(find.text('The first one'), findsOneWidget);
      // The first chapter has nowhere behind it, and the second one is a tap away.
      expect(barButton(tester, CupertinoIcons.chevron_left).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.chevron_right).onTap, isNotNull);

      await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('The second one'), findsOneWidget);
      expect(find.text('Chapter 2 of 2'), findsOneWidget);
      expect(barButton(tester, CupertinoIcons.chevron_right).onTap, isNull);

      await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('The first one'), findsOneWidget);
    });

    testWidgets('moves on by itself when the chapter asks for it', (tester) async {
      await pumpPlayer(
        tester,
        chapters: IList([
          chapter(id: 'one', order: 1, description: 'The first one', autoTransition: true),
          chapter(id: 'two', order: 2, description: 'The second one'),
        ]),
      );

      await tapSquare(tester, 'i0');
      await tapSquare(tester, 'i9');
      expect(find.text('Great job!'), findsOneWidget);

      await tester.pump(kXiangqiLessonAutoTransitionDelay + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('The second one'), findsOneWidget);
    });

    testWidgets('offers a hint for the move it is waiting for', (tester) async {
      await pumpPlayer(tester, chapters: IList([chapter()]));

      expect(barButton(tester, CupertinoIcons.lightbulb).onTap, isNotNull);
      await tester.tap(find.byIcon(CupertinoIcons.lightbulb));
      await tester.pump();
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).hint?.iccs, 'i0i9');
    });

    testWidgets("plays the other side's move itself", (tester) async {
      await pumpPlayer(
        tester,
        chapters: IList([
          chapter(
            fen: kXiangqiInitialFen,
            steps: [
              step(null),
              step('b0c2', nextMove: 'b'),
              step('b9c7', nextMove: 'r'),
              step('h2e2', nextMove: 'b'),
            ].lock,
          ),
        ]),
      );

      await tapSquare(tester, 'b0');
      await tapSquare(tester, 'c2');
      // The reply has not landed yet: the chapter waits, so that the two moves do not read as one.
      expect(
        tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position.pieceAt(squareAt('b9')),
        isNotNull,
      );

      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position.pieceAt(squareAt('c7')),
        isNotNull,
      );
    });
  });
}
