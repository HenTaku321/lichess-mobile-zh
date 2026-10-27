import 'dart:math' as math;

import 'package:chessground/chessground.dart' show BrightnessHueFilter, PieceShiftMethod;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_board_editor_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/share.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_board_editor_filters.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// A board to put xiangqi pieces on, and the few things that can then be done with them.
///
/// The mirror of the chess board editor: a board with a row of pieces on each side to place from,
/// two modes — dragging pieces about, and putting them down and taking them away — a bar of exits,
/// and a filters sheet. Everything the chess editor offers that is a fact about the board is offered
/// here; the parts of it that are facts about *chess* are not, and there are more of those than the
/// common shape suggests: no variant selector, no castling rights, no en passant square, no promotion
/// picker, no pocket, no starting position or endgame list from the server, and no challenge, which
/// would need a xiangqi game to be created from a position and there is no such thing on the server
/// side. Red and black instead of white and black, nine files by ten ranks instead of eight by eight,
/// and seven kinds of piece instead of six.
///
/// What it is not is a game or a puzzle: the position is the player's to build, and nothing here
/// checks that a game could reach it. A board with two black generals, a general outside its palace,
/// or no general at all is a board this screen will hold, which is the whole point of an editor.
class const XiangqiBoardEditorScreen({super.key, final String? initialFen}) extends ConsumerWidget {
  static Route<void> buildRoute({String? initialFen}) =>
      buildScreenRoute(screen: XiangqiBoardEditorScreen(initialFen: initialFen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(xiangqiBoardEditorControllerProvider(initialFen));

    return Scaffold(
      // The game, then what the screen is: the same two names the analysis board's title is built
      // from, and the same shape the chess board editor's title takes.
      appBar: AppBar(
        title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.boardEditor}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'FEN',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _FenDialog(
                onFenLoaded: (fen) => ref
                    .read(xiangqiBoardEditorControllerProvider(initialFen).notifier)
                    .loadFen(fen),
              ),
            ),
          ),
          SemanticIconButton(
            semanticsLabel: context.l10n.mobileSharePositionAsFEN,
            onPressed: () => launchShareDialog(context, ShareParams(text: editorState.fen)),
            icon: const PlatformShareIcon(),
          ),
        ],
      ),
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardPrefs = ref.watch(boardPreferencesProvider);
            final direction = constraints.biggest.aspectRatio > 1 ? Axis.horizontal : Axis.vertical;
            final geometry = XiangqiBoardGeometry(
              _editorCell(constraints.biggest, direction, showCoordinates: boardPrefs.coordinates),
              showCoordinates: boardPrefs.coordinates,
            );

            return Flex(
              direction: direction,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Palette(
                  editorState.orientation.opposite,
                  cell: geometry.cell,
                  initialFen: initialFen,
                  direction: flipAxis(direction),
                ),
                _BoardArea(geometry: geometry, initialFen: initialFen),
                _Palette(
                  editorState.orientation,
                  cell: geometry.cell,
                  initialFen: initialFen,
                  direction: flipAxis(direction),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _BottomBar(initialFen),
    );
  }
}

/// The width of one intersection of the editor, in pixels.
///
/// The board takes [available], and one row or column of pieces has to fit beside it: the palettes
/// stand along the board's long sides and are one square thick, so the editor as a whole is the
/// board plus two squares on whichever axis the palettes run. These are the board's own measurements
/// in squares — the geometry is asked for one, and answers with its whole width and height — so the
/// square this returns is the largest one at which the board and everything beside it fits, and the
/// board drawn with it comes out at exactly the size the board would have chosen for itself.
double _editorCell(Size available, Axis direction, {required bool showCoordinates}) {
  final board = XiangqiBoardGeometry(1, showCoordinates: showCoordinates);
  return direction == .vertical
      ? math.min(available.width / board.width, available.height / (board.height + 2))
      : math.min(available.width / (board.width + 2), available.height / board.height);
}

class const _BoardArea({
  required final XiangqiBoardGeometry geometry,
  required final String? initialFen,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorController = xiangqiBoardEditorControllerProvider(initialFen);
    final editorState = ref.watch(editorController);
    final boardPrefs = ref.watch(boardPreferencesProvider);

    return SizedBox(
      width: geometry.width,
      height: geometry.height,
      // The two looks that are not the position: the filter over the board, and the frame around it.
      // Both are board settings every other board in the app reads — including the analysis board
      // this screen's own exit opens, which a board drawn another way would change colour on the way
      // into — and both are the chess editor's too, through the settings it hands its own board.
      child: BrightnessHueFilter(
        brightness: boardPrefs.brightness,
        hue: boardPrefs.hue,
        child: XiangqiBoard(
          position: editorState.position,
          orientation: editorState.orientation,
          // The two modes are the chess editor's two, and each turns the other's gesture off rather
          // than both being live: a touch in edit mode puts a piece down, a touch in drag mode picks
          // one up, and neither should be able to do the other's job by accident.
          onTapSquare: editorState.editorPointerMode == .edit
              ? ref.read(editorController.notifier).editSquare
              : null,
          onDragMove: editorState.editorPointerMode == .drag
              ? (from, to) => ref.read(editorController.notifier).movePiece(from, to)
              : null,
          onExternalPieceDrop: ref.read(editorController.notifier).placePiece,
          onPieceDiscarded: editorState.editorPointerMode == .drag
              ? ref.read(editorController.notifier).discardPiece
              : null,
          // A game lets a player pick up their own side's pieces only; the editor is one person
          // holding both sides, so either side's pieces are theirs to move.
          dragAnyPiece: true,
          showLastMove: false,
          showCoordinates: boardPrefs.coordinates,
          showBorder: boardPrefs.showBorder,
          magnifyDraggedPiece: boardPrefs.magnifyDraggedPiece,
          dragTargetKind: boardPrefs.dragTargetKind,
          pieceShiftMethod: editorState.editorPointerMode == .drag
              ? PieceShiftMethod.drag
              : PieceShiftMethod.tapTwoSquares,
          enableShapeDrawings: false,
          style: XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors),
        ),
      ),
    );
  }
}

/// One side's pieces to put on the board, and the two tools that are not pieces.
///
/// The pieces are buttons and not draggables, unlike the chess editor's, because the board has no
/// drop target: a chessground square accepts a piece let go over it, while [XiangqiBoard] paints its
/// pieces and has nothing in the tree to drop anything onto.
class const _Palette(
  final XiangqiSide side, {
  required final double cell,
  required final String? initialFen,
  required final Axis direction,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorController = xiangqiBoardEditorControllerProvider(initialFen);
    final editorState = ref.watch(editorController);
    final style = XiangqiBoardStyle.fromChessboardColorScheme(
      ref.watch(boardPreferencesProvider).boardTheme.colors,
    );

    return ColoredBox(
      // A strip a step above the surface, which is what the chess editor paints its own palettes
      // in: something to take pieces off rather than a part of the board.
      color: ColorScheme.of(context).surfaceContainerHighest,
      child: Flex(
        direction: direction,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolButton(
            key: Key('drag-button-${side.name}'),
            size: cell,
            icon: CupertinoIcons.hand_draw,
            active: editorState.editorPointerMode == .drag,
            color: context.lichessColors.good,
            onTap: () => ref.read(editorController.notifier).updateMode(.drag),
          ),
          for (final type in XiangqiPieceType.values)
            _PalettePiece(
              piece: XiangqiPiece(side, type),
              cell: cell,
              style: style,
              active: editorState.activePieceOnEdit == XiangqiPiece(side, type),
              onTap: () =>
                  ref.read(editorController.notifier).updateMode(.edit, XiangqiPiece(side, type)),
            ),
          _ToolButton(
            key: Key('delete-button-${side.name}'),
            size: cell,
            icon: CupertinoIcons.delete,
            active: editorState.deletePiecesActive,
            color: context.lichessColors.error,
            onTap: () => ref.read(editorController.notifier).updateMode(.edit),
          ),
        ],
      ),
    );
  }
}

/// One piece of the palette: a button that takes it in hand, drawn the way the board draws it.
class const _PalettePiece({
  required final XiangqiPiece piece,
  required final double cell,
  required final XiangqiBoardStyle style,
  required final bool active,
  required final VoidCallback onTap,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PalettePiece> createState() => _PalettePieceState();
}

class _PalettePieceState() extends ConsumerState<_PalettePiece> {
  bool _mouse = false;

  @override
  Widget build(BuildContext context) {
    // The piece in hand is marked rather than flooded: the scheme's primary as a wash and a ring,
    // with the button's own rounding, and a ripple so the touch is answered.
    final primary = ColorScheme.of(context).primary;
    final piece = widget.piece;
    final cell = widget.cell;
    final style = widget.style;
    final active = widget.active;
    final magnified = !_mouse && ref.watch(boardPreferencesProvider).magnifyDraggedPiece;
    final feedbackSize = cell * (magnified ? 2 : 1);
    const radius = BorderRadius.all(Radius.circular(8));

    return Semantics(
      label: '${piece.side.label(context.l10n)} ${piece.glyph}',
      button: true,
      selected: active,
      child: Listener(
        onPointerDown: (event) => setState(() => _mouse = event.kind == PointerDeviceKind.mouse),
        child: Draggable<XiangqiPiece>(
          data: piece,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Transform.translate(
            offset: Offset(-feedbackSize / 2, -feedbackSize / 2 - (magnified ? cell : 0)),
            child: SizedBox(
              key: const Key('xiangqi-palette-feedback'),
              width: feedbackSize,
              height: feedbackSize,
              child: CustomPaint(painter: _PalettePiecePainter(piece, feedbackSize, style)),
            ),
          ),
          child: SizedBox(
            key: Key('piece-button-${piece.side.name}-${piece.type.name}'),
            width: cell,
            height: cell,
            child: Material(
              type: MaterialType.transparency,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: active ? primary.withValues(alpha: 0.18) : null,
                  border: active ? Border.all(color: primary, width: 1.5) : null,
                ),
                child: InkWell(
                  borderRadius: radius,
                  onTap: widget.onTap,
                  child: CustomPaint(painter: _PalettePiecePainter(piece, cell, style)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the palette's two tools: the hand that drags pieces about, and the rubber that takes them
/// off the board.
///
/// A tool is lit while it is the one in hand, which is how the player sees what the next touch will
/// do — the same arrangement as the chess editor's two, and lit in the app's own good and bad rather
/// than in anything the board draws.
class const _ToolButton({
  required final double size,
  required final IconData icon,
  required final bool active,
  required final Color color,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Lit the same way a piece in hand is lit: the tool's own colour as a wash and a ring, with a
    // ripple so the touch is answered.
    const radius = BorderRadius.all(Radius.circular(8));

    return SizedBox(
      width: size,
      height: size,
      child: Tooltip(
        message: icon == CupertinoIcons.delete
            ? context.l10n.delete
            : context.l10n.preferencesHowDoYouMovePieces,
        child: Semantics(
          button: true,
          selected: active,
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: active ? color.withValues(alpha: 0.18) : null,
                border: active ? Border.all(color: color, width: 1.5) : null,
              ),
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: Icon(icon, size: 0.85 * size, color: active ? color : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws one piece for the palette, the way the board draws it.
///
/// It goes through [paintXiangqiPiece] rather than drawing a piece of its own, so that the palette
/// cannot offer a piece the board would not then show: a xiangqi piece is a disc with a character on
/// it and no art to ship, and the two sizes are the same drawing at two scales.
class _PalettePiecePainter(
  final XiangqiPiece piece,
  final double cell,
  final XiangqiBoardStyle style,
) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintXiangqiPiece(canvas, size.center(Offset.zero), piece, cell: cell, style: style);

  @override
  bool shouldRepaint(_PalettePiecePainter oldDelegate) =>
      oldDelegate.piece != piece || oldDelegate.cell != cell || oldDelegate.style != style;
}

class const _BottomBar(final String? initialFen) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorController = xiangqiBoardEditorControllerProvider(initialFen);
    final editorState = ref.watch(editorController);
    final pieceCount = editorState.pieceCount;

    return BottomBar(
      children: [
        BottomBarButton(
          icon: Icons.menu,
          label: context.l10n.menu,
          onTap: () => showAdaptiveActionSheet<void>(
            context: context,
            actions: [
              BottomSheetAction(
                makeLabel: (context) => Text(context.l10n.startPosition),
                onPressed: () => ref.read(editorController.notifier).loadFen(kXiangqiInitialFen),
              ),
              if (pieceCount > 0)
                BottomSheetAction(
                  makeLabel: (context) => Text(context.l10n.continueFromHere),
                  onPressed: () => _showContinueFromHereMenu(context, editorState.fen),
                ),
              BottomSheetAction(
                makeLabel: (context) => Text(context.l10n.clearBoard),
                onPressed: () => ref.read(editorController.notifier).clearBoard(),
              ),
            ],
          ),
        ),
        BottomBarButton(
          key: const Key('flip-button'),
          label: context.l10n.flipBoard,
          onTap: ref.read(editorController.notifier).flipBoard,
          icon: CupertinoIcons.arrow_2_squarepath,
        ),
        BottomBarButton(
          key: const Key('analysis-board-button'),
          label: context.l10n.analysis,
          // An empty board is the only thing that cannot be analysed, because a position is all the
          // analysis board is asked for and a FEN is written from any board at all. The chess editor
          // gates this on its variant being playable as well, which is a thing about chess: there is
          // no variant here to be unplayable, and no position the editor can hold that toFen cannot
          // write. So a board with a piece on it always opens, including boards — no generals, two
          // red advisors on the same square's colour, forty pieces — that no game could reach and
          // that the chess editor would refuse outright.
          onTap: pieceCount > 0
              ? () =>
                    Navigator.of(context)
                        .push(XiangqiAnalysisScreen.buildRoute(initialFen: editorState.fen))
              : null,
          icon: Icons.biotech,
        ),
        BottomBarButton(
          label: context.l10n.mobileFilters,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            builder: (BuildContext context) => XiangqiBoardEditorFilters(initialFen: initialFen),
            showDragHandle: true,
            constraints: BoxConstraints(minHeight: MediaQuery.heightOf(context) * 0.5),
          ),
          icon: Icons.tune,
        ),
      ],
    );
  }
}

/// Where the position on the board can be taken next: a game against the engine, or a game between
/// two people over the board.
///
/// Two, where the chess editor has three: the third is a challenge, and a xiangqi challenge has no
/// position to be created from — see [XiangqiBoardEditorScreen]. The board to play on is the analysis
/// board's, so the position is handed over as a FEN, which is the one thing the editor and the two
/// game screens both speak.
Future<void> _showContinueFromHereMenu(BuildContext context, String fen) {
  return showAdaptiveActionSheet(
    context: context,
    actions: [
      BottomSheetAction(
        makeLabel: (context) => Text(context.l10n.playAgainstComputer),
        onPressed: () => Navigator.of(context).push(XiangqiGameScreen.buildRoute(initialFen: fen)),
      ),
      BottomSheetAction(
        makeLabel: (context) => Text(context.l10n.mobileOverTheBoard),
        onPressed: () =>
            Navigator.of(context).push(XiangqiOverTheBoardScreen.buildRoute(initialFen: fen)),
      ),
    ],
  );
}

class const _FenDialog({required final void Function(String fen) onFenLoaded})
    extends StatefulWidget {
  @override
  State<_FenDialog> createState() => _FenDialogState();
}

class _FenDialogState() extends State<_FenDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reads a FEN off the clipboard into the dialog, and loads it.
  ///
  /// The board is read-only and there is nothing to type into it, which is what makes this the whole
  /// of the dialog: pasting is the only way in. What is pasted is what is loaded — there is no
  /// normalising pass through a position, since a [XiangqiPosition] has nothing in it that could be
  /// untrue — and a FEN that does not parse is reported over the screen rather than kept in the
  /// field, the dialog closing either way.
  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || !mounted) return;

    final text = data!.text!.trim();
    if (text.isEmpty) return;

    _controller.text = text;
    try {
      widget.onFenLoaded(text);
    } on FormatException {
      showSnackBar(context, context.l10n.invalidFen, type: SnackBarType.error);
    } finally {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: TextField(
        controller: _controller,
        readOnly: true,
        onTap: _pasteFromClipboard,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: context.l10n.pasteTheFenStringHere,
          suffixIcon: IconButton(
            icon: const Icon(Icons.paste),
            onPressed: _pasteFromClipboard,
            tooltip: context.l10n.mobilePasteFromClipboard,
          ),
        ),
      ),
    );
  }
}
