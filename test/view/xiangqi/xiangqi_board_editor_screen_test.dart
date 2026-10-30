import 'package:chessground/chessground.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_board_editor_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_board_editor_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/engine/fake_transport.dart';
import '../../test_helpers.dart' show kTestSurfaceSize, mockClipboard;
import '../../test_provider_scope.dart';

/// The square named [name], which the tests below write the way a player would.
XiangqiSquare squareAt(String name) {
  final square = XiangqiSquare.parse(name);
  if (square == null) throw ArgumentError('Not a square: $name');
  return square;
}

/// A board with nothing on it but the two generals, one file apart.
const twoKingsFen = '3k5/9/9/9/9/9/9/9/9/4K4 w - - 0 1';

/// Pumps the editor, and hands back the container its own provider lives in.
///
/// The engine is overridden even though the editor itself never asks it anything: two of the
/// screen's exits open a screen that does — the analysis board and the game against the computer —
/// and the engine those really start is a 48 MB network written out of the bundle first, which a
/// test surface has nowhere to put. A [FakeTransport] is enough for them to be built and torn down.
///
/// [initialFen] is the position to open on, and only the tests about opening on one pass it.
Future<ProviderContainer> pumpEditor(
  WidgetTester tester, {
  Size surfaceSize = kTestSurfaceSize,
  String? initialFen,
}) async {
  final transport = FakeTransport(
    spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
    startupLines: kPikafishHandshake,
  );
  final engine = Engine(transport);
  addTearDown(engine.dispose);

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: XiangqiBoardEditorScreen(initialFen: initialFen),
      overrides: {xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine)},
      surfaceSize: surfaceSize,
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(XiangqiBoardEditorScreen)));
}

/// The editor's own state, read out of the container rather than off the screen.
XiangqiBoardEditorState editorState(ProviderContainer container, [String? initialFen]) =>
    container.read(xiangqiBoardEditorControllerProvider(initialFen));

/// The board the editor is drawing.
///
/// Read rather than found by key, because a xiangqi board paints its pieces: the widget is the only
/// door onto what is on the board and onto which gestures it was given.
XiangqiBoard board(WidgetTester tester) => tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));

/// Where the board is drawn, and where on it a square is.
///
/// The board takes the largest board that fits its room and centres it, so the box it is drawn in
/// and the board itself are not the same rectangle: a touch aimed at the box's corner would land
/// beside the board.
({Rect box, XiangqiBoardGeometry geometry, Rect board}) boardGeometry(WidgetTester tester) {
  final box = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(
    box.size,
    showCoordinates: board(tester).showCoordinates,
  );
  return (
    box: box,
    geometry: geometry,
    board: Rect.fromCenter(center: box.center, width: geometry.width, height: geometry.height),
  );
}

/// Touches the point [name] names, in the orientation these tests look at the board from: red at
/// the bottom.
Future<void> tapSquare(WidgetTester tester, String name) async {
  final (:board, :geometry, box: _) = boardGeometry(tester);
  await tester.tapAt(board.topLeft + geometry.centerOf(squareAt(name), .red));
  await tester.pump();
}

/// Drags the piece on [from] onto [to], in steps.
///
/// The steps matter: a pan is only recognised once the finger has travelled further than the touch
/// slop, so a drag has to be walked rather than jumped, exactly as a finger would walk it. The board
/// is asked for its own geometry so that the two points are intersections and not the cells between
/// them.
Future<void> dragSquare(WidgetTester tester, String from, String to) async {
  final (:board, :geometry, box: _) = boardGeometry(tester);
  final start = board.topLeft + geometry.centerOf(squareAt(from), .red);
  final end = board.topLeft + geometry.centerOf(squareAt(to), .red);
  final gesture = await tester.startGesture(start);
  await gesture.moveBy((end - start) / 4);
  await gesture.moveBy((end - start) / 4);
  await gesture.moveBy((end - start) / 4);
  await gesture.moveBy((end - start) / 4);
  await gesture.up();
  await tester.pump();
}

/// The bar button with [key], which is how the bar's buttons are found: their labels are tooltips
/// and semantics rather than text on screen, and their `onTap` is what says whether they are live.
BottomBarButton barButton(WidgetTester tester, String key) =>
    tester.widget<BottomBarButton>(find.byKey(Key(key)));

/// Opens the menu in the bar and presses [label] in it.
Future<void> tapMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a palette drop places the piece and a repeated identical drop never erases it', (
    tester,
  ) async {
    final container = await pumpEditor(tester);
    final palette = find.byKey(const Key('piece-button-red-rook'));
    final (:board, :geometry, box: _) = boardGeometry(tester);
    final target = board.topLeft + geometry.centerOf(squareAt('e4'), .red);
    for (var i = 0; i < 2; i++) {
      final drag = await tester.startGesture(tester.getCenter(palette));
      await tester.pump();
      await drag.moveBy(const Offset(0, -12));
      await tester.pump();
      await drag.moveTo(target);
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(
        editorState(container).position.pieceAt(squareAt('e4')),
        const XiangqiPiece(.red, .rook),
      );
    }
  });

  testWidgets('mouse palette feedback is not magnified', (tester) async {
    await pumpEditor(tester);
    final palette = find.byKey(const Key('piece-button-red-rook'));
    final drag = await tester.startGesture(
      tester.getCenter(palette),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await drag.moveBy(const Offset(20, 0));
    await tester.pump();
    final feedback = find.byKey(const Key('xiangqi-palette-feedback'));
    expect(tester.getSize(feedback), tester.getSize(palette));
    await drag.cancel();
    await tester.pump();
  });
  group('XiangqiBoardEditorScreen', () {
    testWidgets('opens on the starting position, in drag mode, with a palette for each side', (
      tester,
    ) async {
      final container = await pumpEditor(tester);

      final state = editorState(container);
      expect(state.fen, kXiangqiInitialFen);
      expect(state.orientation, XiangqiSide.red);
      expect(state.sideToPlay, XiangqiSide.red);
      expect(state.pieceCount, 32);

      // A board that is both drawn and read the same way the game screens draw theirs.
      final drawn = board(tester);
      expect(drawn.orientation, XiangqiSide.red);
      expect(drawn.dragAnyPiece, isTrue, reason: 'the editor holds both sides');
      expect(drawn.onTapSquare, isNull, reason: 'drag mode is the mode it opens in');
      expect(drawn.onDragMove, isNotNull);

      // Both palettes, and every piece of both in them: seven kinds a side, and the two tools.
      for (final side in XiangqiSide.values) {
        expect(find.byKey(Key('drag-button-${side.name}')), findsOneWidget);
        expect(find.byKey(Key('delete-button-${side.name}')), findsOneWidget);
        for (final type in XiangqiPieceType.values) {
          expect(find.byKey(Key('piece-button-${side.name}-${type.name}')), findsOneWidget);
        }
      }
    });

    testWidgets('opens on the FEN it was given', (tester) async {
      final container = await pumpEditor(tester, initialFen: twoKingsFen);

      expect(editorState(container, twoKingsFen).fen, twoKingsFen);
      expect(editorState(container, twoKingsFen).pieceCount, 2);
    });

    testWidgets('a piece button takes a piece in hand, and a touch puts it down', (tester) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('piece-button-black-cannon')));
      await tester.pump();

      final state = editorState(container);
      expect(state.editorPointerMode, EditorPointerMode.edit);
      expect(
        state.activePieceOnEdit,
        const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.cannon),
      );
      expect(board(tester).onTapSquare, isNotNull, reason: 'edit mode is what a touch does now');

      await tapSquare(tester, 'e4');

      expect(
        editorState(container).position.pieceAt(squareAt('e4')),
        const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.cannon),
      );
      expect(editorState(container).fen.contains('4c4'), isTrue);
      expect(editorState(container).pieceCount, 33);
    });

    testWidgets('a second touch with the same piece in hand takes it back off', (tester) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('piece-button-red-pawn')));
      await tester.pump();
      await tapSquare(tester, 'e4');
      expect(editorState(container).pieceCount, 33);

      await tapSquare(tester, 'e4');

      expect(editorState(container).position.pieceAt(squareAt('e4')), isNull);
      expect(editorState(container).pieceCount, 32);
    });

    testWidgets('the eraser takes a piece off, and turns the hand back into a drag', (
      tester,
    ) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('piece-button-red-pawn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('delete-button-red')));
      await tester.pump();

      expect(editorState(container).deletePiecesActive, isTrue);
      expect(editorState(container).activePieceOnEdit, isNull);

      // a0 is a red chariot in the opening position.
      await tapSquare(tester, 'a0');
      expect(editorState(container).pieceCount, 31);

      await tester.tap(find.byKey(const Key('drag-button-red')));
      await tester.pump();
      expect(editorState(container).editorPointerMode, EditorPointerMode.drag);
      expect(board(tester).onTapSquare, isNull);
      expect(board(tester).onDragMove, isNotNull);
    });

    testWidgets('a drag moves a piece, and moves one of either side', (tester) async {
      final container = await pumpEditor(tester);

      // Red's own chariot, from the bottom of the board.
      await dragSquare(tester, 'a0', 'a4');

      expect(editorState(container).position.pieceAt(squareAt('a0')), isNull);
      expect(
        editorState(container).position.pieceAt(squareAt('a4')),
        const XiangqiPiece(XiangqiSide.red, XiangqiPieceType.rook),
      );

      // And black's, which a game would refuse to let go of: the editor is one person holding both
      // sides, which is the whole of what dragAnyPiece is for.
      await dragSquare(tester, 'a9', 'a5');

      expect(editorState(container).position.pieceAt(squareAt('a9')), isNull);
      expect(
        editorState(container).position.pieceAt(squareAt('a5')),
        const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.rook),
      );
    });

    testWidgets('the flip button turns the drawing and nothing else', (tester) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('flip-button')));
      await tester.pump();

      expect(editorState(container).orientation, XiangqiSide.black);
      expect(board(tester).orientation, XiangqiSide.black);
      expect(editorState(container).fen, kXiangqiInitialFen);
    });

    testWidgets('the menu clears the board, and starts it again', (tester) async {
      final container = await pumpEditor(tester);

      await tapMenuItem(tester, 'Clear board');
      expect(editorState(container).pieceCount, 0);
      expect(editorState(container).fen, '9/9/9/9/9/9/9/9/9/9 w - - 0 1');

      await tapMenuItem(tester, 'Starting position');
      expect(editorState(container).fen, kXiangqiInitialFen);
    });

    testWidgets('an empty board offers nothing to continue from', (tester) async {
      await pumpEditor(tester);

      await tapMenuItem(tester, 'Clear board');
      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();

      // Nothing to continue from: a game needs a position, and an empty board is not one.
      expect(find.text('Continue from here'), findsNothing);
      expect(find.text('Starting position'), findsOneWidget);
      expect(find.text('Clear board'), findsOneWidget);
    });

    testWidgets('the analysis exit is dead while the board is empty, and live as soon as it is '
        'not', (tester) async {
      final container = await pumpEditor(tester);

      await tapMenuItem(tester, 'Clear board');
      expect(barButton(tester, 'analysis-board-button').onTap, isNull);

      await tester.tap(find.byKey(const Key('piece-button-red-king')));
      await tester.pump();
      await tapSquare(tester, 'e0');

      expect(barButton(tester, 'analysis-board-button').onTap, isNotNull);

      await tester.tap(find.byKey(const Key('analysis-board-button')));
      // Navigation can finish while the real engine-loading chip keeps spinning.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // The position the editor built is the position the analysis board opened on, which is the
      // whole of what the two screens have to say to each other.
      expect(find.byType(XiangqiAnalysisScreen), findsOneWidget);
      final analysisContainer = ProviderScope.containerOf(
        tester.element(find.byType(XiangqiBoard).last),
      );
      expect(
        analysisContainer.read(xiangqiAnalysisControllerProvider).position.toFen(),
        editorState(container).fen,
      );
      expect(board(tester).position.toFen(), editorState(container).fen);
    });

    testWidgets('continue from here offers a game against the computer and one over the board', (
      tester,
    ) async {
      await pumpEditor(tester);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue from here'));
      await tester.pumpAndSettle();

      expect(find.text('Play against computer'), findsOneWidget);
      expect(find.text('Over the board'), findsOneWidget);
      // Two, where the chess editor has three: a challenge has no position to be created from, and
      // there is no such thing on the server side for xiangqi.
      expect(find.text('Challenge from position'), findsNothing);
    });

    testWidgets('continue from here hands the position to the game against the computer', (
      tester,
    ) async {
      final container = await pumpEditor(tester, initialFen: twoKingsFen);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue from here'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play against computer'));
      await tester.pumpAndSettle();

      expect(find.byType(XiangqiGameScreen), findsOneWidget);
      expect(editorState(container, twoKingsFen).fen, twoKingsFen);
    });

    testWidgets('continue from here hands the position to the over-the-board screen', (
      tester,
    ) async {
      await pumpEditor(tester, initialFen: twoKingsFen);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue from here'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Over the board'));
      await tester.pumpAndSettle();

      expect(find.byType(XiangqiOverTheBoardScreen), findsOneWidget);
    });

    testWidgets('the filters sheet hands the move to the other side', (tester) async {
      final container = await pumpEditor(tester);
      expect(editorState(container).sideToPlay, XiangqiSide.red);

      await tester.tap(find.bySemanticsLabel('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Black'));
      await tester.pumpAndSettle();

      expect(editorState(container).sideToPlay, XiangqiSide.black);
      expect(editorState(container).fen, kXiangqiInitialFen.replaceFirst(' w ', ' b '));
      // Only the side to move is a filter here: which way up the board is drawn and how many pieces
      // are on it are not facts about the position, and there are no castling rights to give.
      expect(editorState(container).pieceCount, 32);
    });

    group('FEN dialog', () {
      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      testWidgets('pasting a position loads it and closes the dialog', (tester) async {
        mockClipboard(twoKingsFen);
        final container = await pumpEditor(tester);

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.tap(find.byIcon(Icons.paste));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(editorState(container).fen, twoKingsFen);
        expect(editorState(container).pieceCount, 2);
      });

      testWidgets('pasting a board on its own keeps the side and the counters', (tester) async {
        mockClipboard('9/9/9/9/9/9/9/9/9/4K4');
        final container = await pumpEditor(tester);

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.paste));
        await tester.pumpAndSettle();

        expect(editorState(container).fen, '9/9/9/9/9/9/9/9/9/4K4 w - - 0 1');
      });

      testWidgets('a FEN that does not parse is refused, and the board is left alone', (
        tester,
      ) async {
        mockClipboard('not a position at all');
        final container = await pumpEditor(tester);

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.paste));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Invalid FEN'), findsOneWidget);
        expect(editorState(container).fen, kXiangqiInitialFen);
      });
    });
  });
}
