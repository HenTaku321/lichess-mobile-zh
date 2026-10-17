import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/opponent_level.dart';
import 'package:lichess_mobile/src/service/weights_service.dart';
import 'package:lichess_mobile/src/view/offline_computer/opponent_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../service/fake_weights_service.dart';
import '../../test_provider_scope.dart';

/// A screen whose only job is to open the picker and remember what it returned.
class const _PickerHost({
  required final OpponentSpec selected,
  required final Variant variant,
  final bool showPikafish = false,
}) extends StatefulWidget {
  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState() extends State<_PickerHost> {
  ComputerOpponentChoice? picked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final result = await showOpponentPicker(
              context,
              selected: widget.selected,
              variant: widget.variant,
              showPikafish: widget.showPikafish,
            );
            if (mounted) setState(() => picked = result);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  TestLichessBinding.ensureInitialized();

  Future<_PickerHostState> openPicker(
    WidgetTester tester, {
    OpponentSpec selected = const StockfishOpponentSpec(StockfishLevel.level4),
    Variant variant = Variant.standard,
    FakeMaiaWeightsService? weights,
    bool showPikafish = false,
  }) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: _PickerHost(selected: selected, variant: variant, showPikafish: showPikafish),
      overrides: {
        if (weights != null)
          maiaWeightsServiceProvider: maiaWeightsServiceProvider.overrideWithValue(weights),
      },
    );
    await tester.pumpWidget(app);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return tester.state<_PickerHostState>(find.byType(_PickerHost));
  }

  group('Opponent picker', () {
    testWidgets('shows what each engine is', (tester) async {
      await openPicker(tester);

      expect(find.textContaining('trusted by grandmasters'), findsOneWidget);

      await tester.tap(find.text('Maia'));
      await tester.pumpAndSettle();

      expect(find.textContaining('human-like neural network'), findsOneWidget);
      expect(find.textContaining('maiachess.com'), findsOneWidget);
    });

    testWidgets('offers Maia only for the variants it can play', (tester) async {
      await openPicker(tester, variant: Variant.atomic);

      // The networks were trained on standard human games, so there is nothing to choose between.
      expect(find.byType(SegmentedButton<OpponentEngine>), findsNothing);
      expect(find.textContaining('trusted by grandmasters'), findsOneWidget);
    });

    testWidgets('returns the Maia rating that was chosen', (tester) async {
      final weights = FakeMaiaWeightsService(available: MaiaRating.values.toSet());
      final host = await openPicker(tester, weights: weights);

      await tester.tap(find.text('Maia'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1500'), findsWidgets);

      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(host.picked?.chessSpec, const MaiaOpponentSpec(MaiaRating.maia1100));
    });

    testWidgets('downloads the network of a rating the device does not have', (tester) async {
      final weights = FakeMaiaWeightsService();
      final host = await openPicker(tester, weights: weights);

      await tester.tap(find.text('Maia'));
      await tester.pumpAndSettle();

      // Only the bundled network is there, so the rest have to say what they will cost.
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(weights.downloads, [MaiaRating.maia2200]);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(host.picked?.chessSpec, const MaiaOpponentSpec(MaiaRating.maia2200));
    });

    testWidgets('a download that fails leaves the bundled network selected', (tester) async {
      final weights = FakeMaiaWeightsService(downloadSucceeds: false);
      final host = await openPicker(tester, weights: weights);

      await tester.tap(find.text('Maia'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be downloaded'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Never a game that cannot start: the network that ships with the app plays instead.
      expect(host.picked?.chessSpec, const MaiaOpponentSpec(MaiaRating.defaultRating));
    });

    testWidgets('falls back to the bundled network when the selected one was deleted', (
      tester,
    ) async {
      final weights = FakeMaiaWeightsService();
      final host = await openPicker(
        tester,
        selected: const MaiaOpponentSpec(MaiaRating.maia2200),
        weights: weights,
      );

      expect(find.textContaining('${MaiaRating.defaultRating.rating}'), findsWidgets);
      expect(find.textContaining('2200'), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(weights.downloads, isEmpty);
      expect(host.picked?.chessSpec, const MaiaOpponentSpec(MaiaRating.defaultRating));
    });

    testWidgets('offers Pikafish and returns it as the xiangqi choice', (tester) async {
      final host = await openPicker(tester, showPikafish: true);

      expect(find.text('Pikafish'), findsOneWidget);
      await tester.tap(find.text('Pikafish'));
      await tester.pumpAndSettle();
      expect(find.textContaining('xiangqi engine'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(host.picked?.isPikafish, isTrue);
    });

    testWidgets('does not offer Pikafish in a build that does not ship it', (tester) async {
      await openPicker(tester, showPikafish: false);
      expect(find.text('Pikafish'), findsNothing);
    });

    testWidgets('returns the Stockfish level that was chosen', (tester) async {
      final host = await openPicker(tester);

      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(host.picked?.chessSpec, const StockfishOpponentSpec(StockfishLevel.level1));
    });
  });
}
