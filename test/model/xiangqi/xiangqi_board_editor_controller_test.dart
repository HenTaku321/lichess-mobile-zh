import 'package:chessground/chessground.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_board_editor_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// The square named [name], which the tests below write the way a player would.
XiangqiSquare squareAt(String name) {
  final square = XiangqiSquare.parse(name);
  if (square == null) throw ArgumentError('Not a square: $name');
  return square;
}

const _redKing = XiangqiPiece(XiangqiSide.red, XiangqiPieceType.king);
const _blackRook = XiangqiPiece(XiangqiSide.black, XiangqiPieceType.rook);

/// A board with nothing on it but the two generals, one file apart.
const _twoKingsFen = '3k5/9/9/9/9/9/9/9/9/4K4 w - - 0 1';

void main() {
  ProviderContainer makeContainer(String? initialFen) {
    final container = ProviderContainer();
    final subscription = container.listen(
      xiangqiBoardEditorControllerProvider(initialFen),
      (_, _) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    return container;
  }

  group('XiangqiBoardEditorController', () {
    test('palette drops are idempotent and replace without changing the turn', () {
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);
      controller.placePiece(squareAt('a0'), _blackRook);
      final first = container.read(provider);
      controller.placePiece(squareAt('a0'), _blackRook);
      expect(container.read(provider), first);
      expect(first.position.pieceAt(squareAt('a0')), _blackRook);
      expect(first.pieceCount, 32);
      expect(first.sideToPlay, XiangqiSide.red);
    });

    test('opens on the position every game starts from, in drag mode', () {
      final container = makeContainer(null);
      final state = container.read(xiangqiBoardEditorControllerProvider(null));

      expect(state.fen, kXiangqiInitialFen);
      expect(state.sideToPlay, XiangqiSide.red);
      expect(state.orientation, XiangqiSide.red);
      expect(state.editorPointerMode, EditorPointerMode.drag);
      expect(state.pieceToAddOnEdit, isNull);
      expect(state.pieceCount, 32);
      // Nothing is in hand in drag mode and nothing is being erased, whatever is in the field.
      expect(state.activePieceOnEdit, isNull);
      expect(state.deletePiecesActive, isFalse);
    });

    test('opens on the FEN it was given, and turns nothing else over', () {
      final container = makeContainer(_twoKingsFen);
      final state = container.read(xiangqiBoardEditorControllerProvider(_twoKingsFen));

      expect(state.fen, _twoKingsFen);
      expect(state.sideToPlay, XiangqiSide.red);
      expect(state.pieceCount, 2);
      expect(state.editorPointerMode, EditorPointerMode.drag);
    });

    test('puts a piece down, and a second touch with the same piece takes it off', () {
      final container = makeContainer(null);
      final controller = container.read(xiangqiBoardEditorControllerProvider(null).notifier);

      controller.updateMode(EditorPointerMode.edit, _redKing);
      controller.editSquare(squareAt('e4'));

      expect(
        container.read(xiangqiBoardEditorControllerProvider(null)).position.pieceAt(squareAt('e4')),
        _redKing,
      );

      // Touching the same square with the same piece in hand takes it back off, which is how the
      // chess editor's own square editing behaves: the touch that put it there is the touch that
      // undoes it.
      controller.editSquare(squareAt('e4'));

      expect(
        container.read(xiangqiBoardEditorControllerProvider(null)).position.pieceAt(squareAt('e4')),
        isNull,
      );
      // And only that square: the rest of the position is where it was.
      expect(container.read(xiangqiBoardEditorControllerProvider(null)).pieceCount, 32);
    });

    test('puts a piece down over another one, replacing it', () {
      final container = makeContainer(null);
      final controller = container.read(xiangqiBoardEditorControllerProvider(null).notifier);

      // a0 is a red chariot in the opening position.
      controller.updateMode(EditorPointerMode.edit, _blackRook);
      controller.editSquare(squareAt('a0'));

      final state = container.read(xiangqiBoardEditorControllerProvider(null));
      expect(state.position.pieceAt(squareAt('a0')), _blackRook);
      expect(state.pieceCount, 32, reason: 'a replacement is not an addition');
    });

    test('the eraser takes a piece off, and leaves an empty square alone', () {
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);

      controller.updateMode(EditorPointerMode.edit);
      final state = container.read(provider);
      expect(state.deletePiecesActive, isTrue);
      expect(state.activePieceOnEdit, isNull);

      controller.discardPiece(squareAt('a0'));
      expect(container.read(provider).pieceCount, 31);

      // Erasing nothing is not an error and is not a change: the board comes back equal, and a
      // state equal to the one before it is one the screen is never rebuilt for.
      final before = container.read(provider);
      controller.discardPiece(squareAt('a0'));
      expect(container.read(provider), before);
    });

    test('a piece in hand is only in hand in edit mode', () {
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);

      controller.updateMode(EditorPointerMode.edit, _redKing);
      expect(container.read(provider).activePieceOnEdit, _redKing);
      expect(container.read(provider).deletePiecesActive, isFalse);

      // Picking the hand back up puts the piece down: a mode is what the next touch does, and it
      // cannot both drag a piece and be holding one to put down.
      controller.updateMode(EditorPointerMode.drag);
      expect(container.read(provider).pieceToAddOnEdit, isNull);
      expect(container.read(provider).activePieceOnEdit, isNull);
    });

    test('moves a piece, over whatever was on the square it is moved to', () {
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);

      controller.movePiece(squareAt('a0'), squareAt('a4'));

      final state = container.read(provider);
      expect(state.position.pieceAt(squareAt('a0')), isNull);
      expect(
        state.position.pieceAt(squareAt('a4')),
        const XiangqiPiece(XiangqiSide.red, XiangqiPieceType.rook),
      );
      expect(state.pieceCount, 32, reason: 'the piece that was there is gone and this one is here');
      expect(
        state.sideToPlay,
        XiangqiSide.red,
        reason: 'an editor is not a game and plays no move',
      );
    });

    test('a drag from an empty square, and a drag that goes nowhere, are both no-ops', () {
      final container = makeContainer(_twoKingsFen);
      final provider = xiangqiBoardEditorControllerProvider(_twoKingsFen);
      final controller = container.read(provider.notifier);

      final before = container.read(provider);
      controller.movePiece(squareAt('a0'), squareAt('a1'));
      controller.movePiece(squareAt('e0'), squareAt('e0'));
      expect(container.read(provider), before);
    });

    test('turning the board round turns the drawing and nothing else', () {
      final container = makeContainer(_twoKingsFen);
      final provider = xiangqiBoardEditorControllerProvider(_twoKingsFen);
      final controller = container.read(provider.notifier);

      controller.flipBoard();

      final state = container.read(provider);
      expect(state.orientation, XiangqiSide.black);
      expect(state.sideToPlay, XiangqiSide.red, reason: 'the move did not go anywhere');
      expect(state.fen, _twoKingsFen);
    });

    test('hands the move to the other side, and rewrites nothing else about the position', () {
      final container = makeContainer('3k5/9/9/9/9/9/9/9/9/4K4 w - - 7 12');
      final provider = xiangqiBoardEditorControllerProvider('3k5/9/9/9/9/9/9/9/9/4K4 w - - 7 12');
      final controller = container.read(provider.notifier);

      controller.setSideToPlay(XiangqiSide.black);

      final state = container.read(provider);
      expect(state.sideToPlay, XiangqiSide.black);
      expect(state.fen, '3k5/9/9/9/9/9/9/9/9/4K4 b - - 7 12');
      // Setting the side it is already on is not a change.
      final before = container.read(provider);
      controller.setSideToPlay(XiangqiSide.black);
      expect(container.read(provider), before);
    });

    test('clears the board, and leaves the side, the counters and the drawing alone', () {
      final container = makeContainer('3k5/9/9/9/9/9/9/9/9/4K4 b - - 7 12');
      final provider = xiangqiBoardEditorControllerProvider('3k5/9/9/9/9/9/9/9/9/4K4 b - - 7 12');
      final controller = container.read(provider.notifier);

      controller.flipBoard();
      controller.clearBoard();

      final state = container.read(provider);
      expect(state.pieceCount, 0);
      expect(state.fen, '9/9/9/9/9/9/9/9/9/9 b - - 7 12');
      expect(state.sideToPlay, XiangqiSide.black);
      expect(state.orientation, XiangqiSide.black, reason: 'a cleared board is the same board');
    });

    test('loads a FEN, counters and all', () {
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);

      controller.loadFen('3k5/9/9/9/9/9/9/9/9/4K4 b - - 7 12');

      final state = container.read(provider);
      expect(state.fen, '3k5/9/9/9/9/9/9/9/9/4K4 b - - 7 12');
      expect(state.sideToPlay, XiangqiSide.black);
      expect(state.pieceCount, 2);
      // The board is not turned round by a position being loaded: which way up it is drawn is the
      // player's business.
      expect(state.orientation, XiangqiSide.red);
    });

    test('loads a board on its own, keeping the side and the counters the editor had', () {
      final container = makeContainer('3k5/9/9/9/9/9/9/9/9/4K4 b - - 7 12');
      final provider = xiangqiBoardEditorControllerProvider('3k5/9/9/9/9/9/9/9/9/4K4 b - - 7 12');
      final controller = container.read(provider.notifier);

      controller.loadFen('9/9/9/9/9/9/9/9/9/4K4');

      final state = container.read(provider);
      expect(state.fen, '9/9/9/9/9/9/9/9/9/4K4 b - - 7 12');
      expect(state.pieceCount, 1);
    });

    test('an unreadable FEN throws and leaves the board as it was', () {
      final container = makeContainer(_twoKingsFen);
      final provider = xiangqiBoardEditorControllerProvider(_twoKingsFen);
      final controller = container.read(provider.notifier);

      final before = container.read(provider);
      expect(() => controller.loadFen('not a position at all'), throwsFormatException);
      expect(() => controller.loadFen('9/9/9/9/9/9/9/9/9/9 x - - 0 1'), throwsFormatException);
      expect(container.read(provider), before);
    });

    test('a position no game could reach is held, and written back out unchanged', () {
      // Two red generals, and one of them outside the palace: no game can reach this board and the
      // engine would refuse to look at it, which is exactly what an editor is for.
      const illegal = '4k4/9/9/9/9/9/9/9/4K4/4K4 w - - 0 1';
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);

      controller.loadFen(illegal);

      final state = container.read(provider);
      expect(state.fen, illegal);
      expect(state.pieceCount, 3);
      // And it can be taken apart like any other, with the counters surviving the edit. e0 is the
      // lower of the two red generals, and FEN writes red's back rank last, so taking that one off
      // empties the last field and leaves the field above it as it was.
      controller.discardPiece(squareAt('e0'));
      expect(container.read(provider).fen, '4k4/9/9/9/9/9/9/9/4K4/9 w - - 0 1');
    });

    test('what a piece button puts down is what a touch writes, and the FEN says so', () {
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);

      controller.updateMode(
        EditorPointerMode.edit,
        const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.cannon),
      );
      controller.editSquare(squareAt('e4'));

      expect(container.read(provider).fen.contains('4c4'), isTrue);
      expect(
        container.read(provider).position.pieceAt(squareAt('e4')),
        const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.cannon),
      );
    });

    test('a position written out and read back in is the same position', () {
      final container = makeContainer(null);
      final provider = xiangqiBoardEditorControllerProvider(null);
      final controller = container.read(provider.notifier);

      controller.updateMode(
        EditorPointerMode.edit,
        const XiangqiPiece(XiangqiSide.red, XiangqiPieceType.advisor),
      );
      controller.editSquare(squareAt('d4'));
      controller.movePiece(squareAt('e0'), squareAt('e1'));
      final written = container.read(provider).fen;

      final other = makeContainer(written);
      expect(other.read(xiangqiBoardEditorControllerProvider(written)).fen, written);
    });

    test('two editors on two positions are two boards', () {
      final container = makeContainer(null);
      addTearDown(
        container.listen(xiangqiBoardEditorControllerProvider(_twoKingsFen), (_, _) {}).close,
      );

      container
          .read(xiangqiBoardEditorControllerProvider(null).notifier)
          .discardPiece(squareAt('a0'));

      expect(container.read(xiangqiBoardEditorControllerProvider(null)).pieceCount, 31);
      expect(container.read(xiangqiBoardEditorControllerProvider(_twoKingsFen)).pieceCount, 2);
    });
  });
}
