import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/view/puzzle/puzzle_feedback_widget.dart';

import '../../binding.dart';
import '../../model/xiangqi/puzzle/xiangqi_puzzle_fixture.dart';
import 'xiangqi_puzzle_screen_test.dart' as puzzle;

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('xiangqi starts with the same feedback tile as chess puzzles', (tester) async {
    await puzzle.pumpPuzzleScreen(tester, server: puzzle.PuzzleServer(), failOnOverflow: true);

    expect(find.byType(FeedbackTile), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Find the best move for Black.'), findsOneWidget);
  });

  testWidgets('correct feedback remains after the automatic opponent reply', (tester) async {
    final server = puzzle.PuzzleServer();
    await puzzle.pumpPuzzleScreen(tester, server: server, failOnOverflow: true);
    final move = xiangqiTestLine.solution.first;
    await puzzle.tapSquare(tester, move.from.name, orientation: XiangqiSide.black);
    await puzzle.tapSquare(tester, move.to.name, orientation: XiangqiSide.black);

    expect(puzzle.attemptState(tester).moves, hasLength(2));
    expect(find.text('Best move!'), findsOneWidget);
    expect(find.text('Keep going…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 501));
    expect(puzzle.attemptState(tester).moves, hasLength(3));
    expect(find.text('Best move!'), findsOneWidget);
    expect(find.text('Keep going…'), findsOneWidget);
    expect(find.byType(FeedbackTile), findsOneWidget);
    expect(server.lastBody('/api/puzzle/$xiangqiTestPuzzleId/complete'), isNull);
  });

  testWidgets('wrong feedback remains after reverting the wrong move', (tester) async {
    await puzzle.pumpPuzzleScreen(tester, server: puzzle.PuzzleServer(), failOnOverflow: true);
    final before = puzzle.board(tester).position;
    final wrong = rules
        .legalMoves(before)
        .firstWhere((move) => move != xiangqiTestLine.solution.first);
    await puzzle.tapSquare(tester, wrong.from.name, orientation: XiangqiSide.black);
    await puzzle.tapSquare(tester, wrong.to.name, orientation: XiangqiSide.black);

    expect(puzzle.board(tester).position, isNot(before));
    expect(find.text("That's not the move!"), findsOneWidget);
    expect(find.text('Try something else.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 501));
    expect(puzzle.board(tester).position, before);
    expect(puzzle.attemptState(tester).mistakes, 1);
    expect(find.text("That's not the move!"), findsOneWidget);
    expect(find.byType(FeedbackTile), findsOneWidget);
  });

  testWidgets('a recorded solution uses the shared completion feedback', (tester) async {
    final server = puzzle.PuzzleServer();
    await puzzle.pumpPuzzleScreen(tester, server: server, failOnOverflow: true);
    await puzzle.playTheLine(tester);

    expect(find.byType(FeedbackTile), findsOneWidget);
    expect(find.text('Success!'), findsOneWidget);
    expect(puzzle.attemptState(tester).moves, hasLength(xiangqiTestLine.answer.length));
    expect(
      server.requests.where((request) => request.url.path.endsWith('/complete')),
      hasLength(1),
    );
  });
}
