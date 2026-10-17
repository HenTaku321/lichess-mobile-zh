import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/board_editor/board_editor_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_board_editor_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

/// The two board editors, on one page.
class const BoardEditorHubScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const BoardEditorHubScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.boardEditor)),
      body: ListView(
        padding: Styles.bodySectionPadding,
        children: [
          _EditorCard(
            title: context.l10n.mobileChess,
            description: context.l10n.mobileBoardEditorChessDescription,
            preview: SizedBox.square(
              dimension: 96,
              child: StaticChessboard(
                size: 96,
                fen: Chess.initial.fen,
                orientation: Side.white,
                settings: StaticChessboardSettings(
                  pieceAssets: boardPrefs.pieceSet.assets,
                  colorScheme: boardPrefs.boardTheme.colors,
                  brightness: boardPrefs.brightness,
                  hue: boardPrefs.hue,
                  enableCoordinates: false,
                ),
              ),
            ),
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              BoardEditorScreen.buildRoute((
                initialVariant: Variant.standard,
                initialFen: null,
                initialOrientation: null,
              )),
            ),
          ),
          const SizedBox(height: 16.0),
          _EditorCard(
            title: context.l10n.mobileXiangqi,
            description: context.l10n.mobileBoardEditorXiangqiDescription,
            preview: SizedBox(
              width: 87,
              height: 96,
              child: XiangqiBoard(
                position: XiangqiPosition.initial(),
                showCoordinates: boardPrefs.coordinates,
                showBorder: boardPrefs.showBorder,
                style: XiangqiBoardStyle.fromChessboardColorScheme(boardPrefs.boardTheme.colors),
              ),
            ),
            onTap: () => Navigator.of(
              context,
              rootNavigator: true,
            ).push(XiangqiBoardEditorScreen.buildRoute()),
          ),
        ],
      ),
    );
  }
}

class const _EditorCard({
  required final String title,
  required final String description,
  required final Widget preview,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListSection(
      materialFilledCard: true,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.all(16.0),
          leading: preview,
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6.0), child: Text(description)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ],
    );
  }
}
