// Tests for the screen a xiangqi.com puzzle is solved on.
//
// The screen is driven end to end: the search, the fetch, the blunder the app plays for the
// opponent, the solver's own moves, the replies the app plays back, and the submission. Nothing here
// is a live host — the client is stubbed at the HTTP layer, over the fixture's payloads — so what is
// under test is the arrangement rather than the wire, which the reader's own tests cover.
//
// One thing about the timing is worth knowing before reading the pumps below. The xiangqi client
// spaces requests to the host by at least `kXiangqiMinRequestSpacing`, and the spacing is measured
// against the real clock rather than the test's, so every request after the first waits out the
// whole of it however fast the test itself is running. `settle` is where that is paid.

import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_puzzle_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';

import '../../binding.dart';
import '../../model/xiangqi/puzzle/xiangqi_puzzle_fixture.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// A little over the client's own spacing between two requests to the host.
const _spacing = Duration(milliseconds: 1600);

/// Pumps until nothing more is coming, advancing the clock over the client's spacing.
///
/// Not `pumpAndSettle`: the spacing is a bare timer, which schedules no frame, so settling would
/// return while the request it holds back is still waiting — and the test would then fail on a timer
/// that is still pending rather than on what it meant to assert.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var round = 0; round < rounds; round++) {
    await tester.pump(_spacing);
  }
}

/// A stub xiangqi.com, which also records what was asked of it.
///
/// The three endpoints the screen draws a puzzle from, and a 404 for anything else, so a screen that
/// starts asking for something new fails loudly instead of quietly drawing an empty board.
class PuzzleServer({
  /// What `quota/state` says is left of the day's puzzles.
  final int puzzlesLeft = 3,

  /// What `search` hands back, or null for the message that says there is nothing to hand back.
  final String? searchPuzzleId = xiangqiTestPuzzleId,

  /// Whether the fetch answers the way a spent allowance does: the position, and no answer.
  final bool withholdAnswer = false,
  final int completionStatus = 4,
}) {
  final List<http.Request> requests = [];
  bool failNextSearch = false;

  MockClient get client => MockClient(answer);

  /// A reusable HTTP handler; a MockClient hands it an already-finalized request.
  Future<http.Response> answer(http.Request request) {
    requests.add(request);
    switch (request.url.path) {
      case '/api/puzzle/search':
        if (failNextSearch) return xiangqiJsonResponse('{}', 503);
        return searchPuzzleId == null
            ? xiangqiJsonResponse(jsonEncode({'message': "There's no next puzzle available"}), 200)
            : xiangqiJsonResponse(jsonEncode({'title': null, 'puzzle_id': searchPuzzleId}), 200);
      case '/api/puzzle/P/$xiangqiTestPuzzleId':
        return withholdAnswer
            ? xiangqiJsonResponse(jsonEncode(xiangqiPuzzleQuotaExceededBody()), 429)
            : xiangqiJsonResponse(jsonEncode(xiangqiPuzzlePayload()), 200);
      case '/api/puzzle/$xiangqiTestPuzzleId/complete':
        return xiangqiJsonResponse(jsonEncode({'p_rating': 1833, 'status': completionStatus}), 200);
      case '/api/quota/state':
        return xiangqiJsonResponse(
          jsonEncode({
            'user_type': 'free',
            'reset_in_seconds': 68283,
            'features': {
              'puzzles': {'limit': 15, 'remaining': puzzlesLeft},
              'puzzle_hints': {'limit': 5, 'remaining': 3},
            },
          }),
          200,
        );
      case '/api/quota/usage':
        return xiangqiJsonResponse(
          '{"feature":"puzzle_hints","allowed":true,"remaining":3,"reason":"ok"}',
          200,
        );
      default:
        return xiangqiJsonResponse('', 404);
    }
  }

  /// The body of the last request sent to [path], or null when none was.
  Map<String, dynamic>? lastBody(String path) {
    for (final request in requests.reversed) {
      if (request.url.path == path) return jsonDecode(request.body) as Map<String, dynamic>;
    }
    return null;
  }
}

/// Opens the puzzle screen over [server], with a session already in hand.
///
/// The session is put in place through the storage provider rather than by overriding the
/// controller, which is the one thing the harness allows here: the store is a plain provider and the
/// controller is not.
/// [session] is what the storage hands out: the fixture's real account by default, null for a device
/// that has never signed in, and [xiangqiGuestSession] for one that has only a guest token.
Future<void> pumpPuzzleScreen(
  WidgetTester tester, {
  required PuzzleServer server,
  Object? session = _defaultSession,
}) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const XiangqiPuzzleScreen(),
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          FakeXiangqiAuthStorage(
            identical(session, _defaultSession) ? xiangqiTestSession : session as XiangqiSession?,
          ),
        ),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => server.client),
        ),
      },
    ),
  );
  await settle(tester);
}

/// A sentinel meaning "the fixture's own session", so that [pumpPuzzleScreen] can tell "not given"
/// apart from an explicit null.
const _defaultSession = Object();

/// A session with no account behind it, which is what the socket mints for a visitor.
const xiangqiGuestSession = XiangqiSession(
  userId: 'guest5rll3',
  name: 'guest5rll3',
  accessToken: 'guest-token',
  isGuest: true,
);

/// The board the screen has drawn.
XiangqiBoard board(WidgetTester tester) => tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));

/// Touches the point [name] names, in [orientation].
///
/// Aimed at the drawn board rather than at the box it is drawn in, which are not the same thing: the
/// board takes the largest board that fits its room and centres it, so a touch aimed at the box's
/// corner would land beside it. The geometry is measured with the coordinates on, which is the
/// preference's default and widens the board's margin by half a cell on every side.
Future<void> tapSquare(WidgetTester tester, String name, {required XiangqiSide orientation}) async {
  final box = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(box.size, showCoordinates: true);
  final board = Rect.fromCenter(center: box.center, width: geometry.width, height: geometry.height);
  final square = XiangqiSquare.parse(name);
  if (square == null) throw ArgumentError('Not a square: $name');
  await tester.tapAt(board.topLeft + geometry.centerOf(square, orientation));
  await tester.pump();
}

/// Plays the solver's half of the fixture line, letting the app answer each move.
///
/// Only the solver's own moves are tapped: the replies are the app's, and are on the board by the
/// time the next tap is aimed.
Future<void> playTheLine(WidgetTester tester) async {
  for (var i = 0; i < xiangqiTestLine.solution.length; i += 2) {
    final move = xiangqiTestLine.solution[i];
    await tapSquare(tester, move.from.name, orientation: XiangqiSide.black);
    await tapSquare(tester, move.to.name, orientation: XiangqiSide.black);
    await settle(tester);
  }
  await settle(tester);
}

/// The bar button under [icon], which is how the buttons are found: their labels are tooltips and
/// semantics rather than text on screen, and their `onTap` is what says whether they are live.
BottomBarButton barButton(WidgetTester tester, IconData icon) => tester.widget<BottomBarButton>(
  find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton)),
);

/// The state of the attempt the screen is showing for [puzzle].
///
/// The puzzle is named rather than read off the screen because the attempt is keyed by it, and a
/// test that named the wrong one would be handed a second, empty attempt instead of the failure it
/// was looking for.
XiangqiPuzzleAttemptState attemptState(WidgetTester tester, [XiangqiPuzzle? puzzle]) {
  final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiPuzzleScreen)));
  return container.read(
    xiangqiPuzzleControllerProvider((puzzle: puzzle ?? xiangqiTestPuzzle, attempt: 0)),
  );
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiPuzzleScreen', () {
    testWidgets('auto-next loads exactly once using the shared Lichess preference', (tester) async {
      final server = PuzzleServer();
      await pumpPuzzleScreen(tester, server: server);
      final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiPuzzleScreen)));
      await container.read(puzzlePreferencesProvider.notifier).setAutoNext(true);
      await playTheLine(tester);
      expect(
        server.requests.where((request) => request.url.path == '/api/puzzle/search'),
        hasLength(2),
      );
      expect(board(tester).position, rules.play(xiangqiTestLine.before, xiangqiTestLine.blunder));
    });

    testWidgets('auto-next failure retains the completed board for a manual retry', (tester) async {
      final server = PuzzleServer();
      await pumpPuzzleScreen(tester, server: server);
      final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiPuzzleScreen)));
      await container.read(puzzlePreferencesProvider.notifier).setAutoNext(true);
      server.failNextSearch = true;
      await playTheLine(tester);
      expect(attemptState(tester).phase, XiangqiPuzzlePhase.recorded);
      expect(board(tester).position, attemptState(tester).position);
      expect(barButton(tester, CupertinoIcons.arrow_right).onTap, isNotNull);
      server.failNextSearch = false;
      await tester.tap(find.byIcon(CupertinoIcons.arrow_right));
      await settle(tester);
      expect(board(tester).position, rules.play(xiangqiTestLine.before, xiangqiTestLine.blunder));
    });

    testWidgets('a hinted completion does not trigger auto-next', (tester) async {
      final server = PuzzleServer(completionStatus: 3);
      await pumpPuzzleScreen(tester, server: server);
      final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiPuzzleScreen)));
      await container.read(puzzlePreferencesProvider.notifier).setAutoNext(true);
      await playTheLine(tester);
      expect(
        server.requests.where((request) => request.url.path == '/api/puzzle/search'),
        hasLength(1),
      );
      expect(attemptState(tester).recordedStatus, XiangqiPuzzleAttemptStatus.solvedByHint);
    });
    testWidgets('a device with no session is offered the way in, and no board', (tester) async {
      await pumpPuzzleScreen(tester, server: PuzzleServer(), session: null);

      expect(find.byType(XiangqiBoard), findsNothing);
      expect(find.text('Sign in to xiangqi.com'), findsWidgets);
    });

    testWidgets('a guest session is offered the way in, and no board', (tester) async {
      // **A guest is not an account here.** The search and the fetch are open to anybody, but
      // `complete` and `quota/usage` are `401` to a guest — measured on 2026-10-16 — so a solver
      // who could only fetch would be a solver who could not submit.
      await pumpPuzzleScreen(tester, server: PuzzleServer(), session: xiangqiGuestSession);

      expect(find.byType(XiangqiBoard), findsNothing);
      expect(find.text('Sign in to xiangqi.com'), findsWidgets);
    });

    testWidgets('the blunder is already played, and the solver is asked for their own move', (
      tester,
    ) async {
      await pumpPuzzleScreen(tester, server: PuzzleServer());

      expect(find.byType(XiangqiBoard), findsOneWidget);
      // The board is the position *after* the blunder: the app plays the opponent's move itself,
      // and it is not one of the moves the solver is asked for.
      expect(
        board(tester).position.toFen(),
        rules.play(xiangqiTestLine.before, xiangqiTestLine.blunder).toFen(),
      );
      expect(board(tester).position.toFen(), isNot(xiangqiTestLine.before.toFen()));

      // Whose move is being asked for, and how much of the day is left.
      expect(find.text('Find the best move for Black.'), findsOneWidget);
      expect(find.text('3 of 15 puzzles left today'), findsOneWidget);
    });

    testWidgets('the whole line is played out, and the attempt is submitted', (tester) async {
      final server = PuzzleServer();
      await pumpPuzzleScreen(tester, server: server);

      await playTheLine(tester);

      expect(find.text('solved'), findsOneWidget);
      // The whole line, the blunder first, is what the attempt holds.
      expect(attemptState(tester).moves.length, xiangqiTestLine.answer.length);

      final body = server.lastBody('/api/puzzle/$xiangqiTestPuzzleId/complete');
      expect(body, isNotNull);
      expect(body!['mistakes'], 0);
      expect(body['hints_used'], 0);
      expect(body['attempt_mode'], 'P');
    });

    testWidgets("a move that is not the puzzle's own is played, then taken back", (tester) async {
      await pumpPuzzleScreen(tester, server: PuzzleServer());

      final before = board(tester).position;
      final expected = xiangqiTestLine.solution.first;
      // The first legal move in the position that is not the puzzle's next one: a move the solver
      // could really make, and the wrong one.
      final wrong = rules.legalMoves(board(tester).position).firstWhere((move) => move != expected);

      await tapSquare(tester, wrong.from.name, orientation: XiangqiSide.black);
      await tapSquare(tester, wrong.to.name, orientation: XiangqiSide.black);

      expect(board(tester).position, rules.play(before, wrong));
      expect(attemptState(tester).mistakes, 1);
      expect(attemptState(tester).wrongMove, wrong);
      expect(find.text('That is not the move.'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));

      expect(board(tester).position, before, reason: 'the wrong move is taken back');
      expect(attemptState(tester).wrongMove, wrong);
      expect(find.text('That is not the move.'), findsOneWidget);
    });

    testWidgets('a queue with nothing in it says so rather than showing an empty board', (
      tester,
    ) async {
      await pumpPuzzleScreen(tester, server: PuzzleServer(searchPuzzleId: null));

      expect(find.byType(XiangqiBoard), findsNothing);
      expect(find.text('There is no puzzle available for these settings.'), findsOneWidget);
    });

    testWidgets('the position is drawn even when the answer was withheld', (tester) async {
      await pumpPuzzleScreen(tester, server: PuzzleServer(withholdAnswer: true));

      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(
        find.text("You have used all of today's puzzles. The position is here; the answer is not."),
        findsOneWidget,
      );
      // And the board takes nothing: there is no answer to check a move against.
      expect(attemptState(tester, xiangqiTestPuzzleWithoutAnswer).isPlayable, isFalse);
    });

    testWidgets('the hint button asks the server before it shows anything', (tester) async {
      final server = PuzzleServer();
      await pumpPuzzleScreen(tester, server: server);

      expect(barButton(tester, CupertinoIcons.lightbulb).onTap, isNotNull);
      await tester.tap(find.byIcon(CupertinoIcons.lightbulb));
      await settle(tester);

      expect(server.lastBody('/api/quota/usage'), {'feature': 'puzzle_hints'});
      expect(attemptState(tester).hintsUsed, 1);
      expect(attemptState(tester).hint, xiangqiTestLine.solution.first);
      expect(board(tester).arrows.single.move, xiangqiTestLine.solution.first);
    });
  });
}
