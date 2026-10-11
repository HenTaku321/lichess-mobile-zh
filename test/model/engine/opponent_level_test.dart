import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/opponent_level.dart';

void main() {
  const level4 = StockfishOpponentSpec(StockfishLevel.level4);
  const maia1500 = MaiaOpponentSpec(MaiaRating.maia1500);

  group('StockfishOpponentSpec.engineSpecFor', () {
    test('is Fairy-Stockfish on every variant where the app bundles its engines', () {
      for (final variant in Variant.values) {
        expect(
          level4.engineSpecFor(variant, hasBundledEngines: true),
          const StockfishSpec.fairy(),
          reason: variant.name,
        );
      }
    });

    test('is the stockfish on the machine for the standard game, where the app bundles none', () {
      // The same games the app's own Stockfish would have played: the official engine plays all
      // three of these, which is the predicate the evaluator picks its engine by as well.
      for (final variant in [Variant.standard, Variant.chess960, Variant.fromPosition]) {
        expect(
          level4.engineSpecFor(variant, hasBundledEngines: false),
          const SystemStockfishSpec(),
          reason: variant.name,
        );
      }
    });

    test('keeps asking for Fairy-Stockfish on the variants it is the only one that plays', () {
      // Fairy-Stockfish is neither bundled nor installed on such a machine, so these fail loudly
      // rather than being played as the standard game by an engine that cannot play them.
      for (final variant in [
        Variant.antichess,
        Variant.kingOfTheHill,
        Variant.threeCheck,
        Variant.atomic,
        Variant.horde,
        Variant.racingKings,
        Variant.crazyhouse,
      ]) {
        expect(
          level4.engineSpecFor(variant, hasBundledEngines: false),
          const StockfishSpec.fairy(),
          reason: variant.name,
        );
      }
    });

    test('does not depend on the level', () {
      for (final level in StockfishLevel.values) {
        expect(
          StockfishOpponentSpec(level).engineSpecFor(Variant.standard, hasBundledEngines: false),
          const SystemStockfishSpec(),
          reason: level.name,
        );
      }
    });
  });

  group('MaiaOpponentSpec.engineSpecFor', () {
    test("is LC0 wherever it runs, the network being the app's own", () {
      for (final variant in Variant.values) {
        for (final hasBundledEngines in [true, false]) {
          expect(
            maia1500.engineSpecFor(variant, hasBundledEngines: hasBundledEngines),
            const Lc0Spec(),
            reason: '${variant.name}, hasBundledEngines: $hasBundledEngines',
          );
        }
      }
    });
  });
}
