import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/engine/opponent_level.dart';

void main() {
  const level4 = StockfishOpponentSpec(StockfishLevel.level4);
  const maia1500 = MaiaOpponentSpec(MaiaRating.maia1500);

  group('StockfishOpponentSpec.engineSpecFor', () {
    test('is Fairy-Stockfish on every variant where the app ships its engines', () {
      for (final variant in Variant.values) {
        expect(
          level4.engineSpecFor(variant, engines: .phone),
          const StockfishSpec.fairy(),
          reason: variant.name,
        );
      }
    });

    test('is Fairy-Stockfish on the desktop as well, which ships it just as the phone does', () {
      // The whole point of the per-flavour table: the desktop build has two engines, not none, and
      // Fairy-Stockfish is one of them — so the eight variants it plays are the app's own engine
      // there too, rather than the system's stockfish and a greyed-out row.
      for (final variant in Variant.values) {
        expect(
          level4.engineSpecFor(variant, engines: .desktop),
          const StockfishSpec.fairy(),
          reason: variant.name,
        );
      }
    });

    test('is the stockfish on the machine for the standard game, where the app ships none', () {
      // The same games the app's own Stockfish would have played: the official engine plays all
      // three of these, which is the predicate the evaluator picks its engine by as well.
      for (final variant in [Variant.standard, Variant.chess960, Variant.fromPosition]) {
        expect(
          level4.engineSpecFor(variant, engines: .none),
          const SystemStockfishSpec(),
          reason: variant.name,
        );
      }
    });

    test('keeps asking for Fairy-Stockfish on the variants it is the only one that plays', () {
      // Fairy-Stockfish is neither shipped nor installed on such a machine, so these fail loudly
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
          level4.engineSpecFor(variant, engines: .none),
          const StockfishSpec.fairy(),
          reason: variant.name,
        );
      }
    });

    test('does not depend on the level', () {
      for (final level in StockfishLevel.values) {
        expect(
          StockfishOpponentSpec(level).engineSpecFor(Variant.standard, engines: .none),
          const SystemStockfishSpec(),
          reason: level.name,
        );
      }
    });
  });

  group('StockfishOpponentSpec.supports', () {
    test('is every variant on both platforms the app ships Fairy-Stockfish for', () {
      for (final engines in [EngineAvailability.phone, EngineAvailability.desktop]) {
        for (final variant in Variant.values) {
          expect(level4.supports(variant, engines: engines), isTrue, reason: '$variant, $engines');
        }
      }
    });

    test('is only the official three where the app ships no engine at all', () {
      for (final variant in Variant.values) {
        expect(
          level4.supports(variant, engines: .none),
          officialStockfishVariants.contains(variant),
          reason: variant.name,
        );
      }
    });
  });

  group('MaiaOpponentSpec.engineSpecFor', () {
    test("is LC0 wherever it runs, the network being the app's own", () {
      for (final variant in Variant.values) {
        for (final engines in [
          EngineAvailability.phone,
          EngineAvailability.desktop,
          EngineAvailability.none,
        ]) {
          expect(
            maia1500.engineSpecFor(variant, engines: engines),
            const Lc0Spec(),
            reason: '${variant.name}, $engines',
          );
        }
      }
    });
  });

  group('MaiaOpponentSpec.supports', () {
    test('is the standard game on the phone, where LC0 is built', () {
      expect(maia1500.supports(Variant.standard, engines: .phone), isTrue);
      expect(maia1500.supports(Variant.fromPosition, engines: .phone), isTrue);
    });

    test('is nothing on the desktop, where LC0 is not built', () {
      // What the boolean could not say: the desktop ships engines, but not this one, so Maia is
      // greyed out there even though `hasBundledEngines` would have been true.
      for (final variant in Variant.values) {
        expect(maia1500.supports(variant, engines: .desktop), isFalse, reason: variant.name);
      }
    });

    test('is nothing on a machine with no app engine either', () {
      for (final variant in Variant.values) {
        expect(maia1500.supports(variant, engines: .none), isFalse, reason: variant.name);
      }
    });
  });

  group('EngineAvailability', () {
    test('is the phone and the desktop, and only the second is short of flavours', () {
      expect(EngineAvailability.phone.any, isTrue);
      expect(EngineAvailability.desktop.any, isTrue);
      expect(EngineAvailability.none.any, isFalse);
      expect(EngineAvailability.desktop, isNot(EngineAvailability.phone));
      expect(EngineAvailability.desktop, isNot(EngineAvailability.none));
    });
  });
}
