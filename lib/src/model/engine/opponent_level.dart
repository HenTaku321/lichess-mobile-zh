import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';

/// Stockfish strength levels. Level 1 is the easiest, level 12 is the hardest.
enum StockfishLevel({
  /// The internal Stockfish skill level (from -20 to 20).
  ///
  /// Since we are using negative skill levels for the easier levels, this should only be used with
  /// Fairy-Stockfish, which supports negative skill levels. For regular Stockfish, the minimum skill level is 0.
  required final int skill,

  /// Number of principal variations to compute for move selection.
  ///
  /// Stockfish's strength limiting works by applying a randomized bias to scores
  /// of slightly worse moves among at least 4 candidates. MultiPV increases
  /// this candidate pool, giving more suboptimal moves to choose from at lower Elos.
  required final int multiPv,

  /// Search time for this level.
  required final Duration searchTime,

  /// Number of threads to use for move computation.
  required final int threads,
}) {
  level1(skill: -12, multiPv: 10, searchTime: Duration(milliseconds: 500), threads: 1),
  level2(skill: -6, multiPv: 8, searchTime: Duration(milliseconds: 500), threads: 1),
  level3(skill: 0, multiPv: 6, searchTime: Duration(milliseconds: 610), threads: 1),
  level4(skill: 4, multiPv: 5, searchTime: Duration(milliseconds: 765), threads: 1),
  level5(skill: 7, multiPv: 5, searchTime: Duration(milliseconds: 920), threads: 1),
  level6(skill: 9, multiPv: 4, searchTime: Duration(milliseconds: 1075), threads: 2),
  level7(skill: 11, multiPv: 4, searchTime: Duration(milliseconds: 1225), threads: 2),
  level8(skill: 13, multiPv: 4, searchTime: Duration(milliseconds: 1380), threads: 2),
  level9(skill: 15, multiPv: 4, searchTime: Duration(milliseconds: 1535), threads: 2),
  level10(skill: 17, multiPv: 4, searchTime: Duration(milliseconds: 1690), threads: 2),
  level11(skill: 19, multiPv: 4, searchTime: Duration(milliseconds: 1845), threads: 2),
  level12(skill: 20, multiPv: 4, searchTime: Duration(milliseconds: 2000), threads: 2);

  /// The display level number (1-12).
  int get level => index + 1;

  /// The default level for new games.
  static const defaultLevel = StockfishLevel.level4;

  static StockfishLevel? fromLevel(int level) =>
      level >= 1 && level <= values.length ? values[level - 1] : null;
}

/// The Maia networks the app can play against.
///
/// Each one is a policy network trained on human games in a rating band, so the rating is not a
/// strength dial the way [StockfishLevel] is: it is *which* humans the network learned from, and
/// what it plays is the move players of that strength would most often play.
///
/// Only [bundledRatings] ship with the app; the others are downloaded on demand. See
/// `MaiaWeightsService`.
enum MaiaRating({
  /// The rating band the network was trained on.
  required final int rating,

  /// The first 12 digits of the network's SHA-256, checked after a download.
  required final String sha256Prefix,

  /// The size of the network in bytes, for progress reporting.
  required final int expectedSize,
}) {
  maia1100(rating: 1100, sha256Prefix: '1a9616e14c2c', expectedSize: 1314927),
  maia1200(rating: 1200, sha256Prefix: 'c37c4f6c0c05', expectedSize: 1251582),
  maia1300(rating: 1300, sha256Prefix: '153640826ca6', expectedSize: 1248733),
  maia1400(rating: 1400, sha256Prefix: '98b2d297cfd2', expectedSize: 1332237),
  maia1500(rating: 1500, sha256Prefix: '46eac500f16f', expectedSize: 1259887),
  maia1600(rating: 1600, sha256Prefix: '9f95c1b668fe', expectedSize: 1317232),
  maia1700(rating: 1700, sha256Prefix: 'fb80c0d9b4a8', expectedSize: 1315274),
  maia1800(rating: 1800, sha256Prefix: '5c24c3d8185f', expectedSize: 1292215),
  maia1900(rating: 1900, sha256Prefix: '80893d373885', expectedSize: 1265805),
  maia2200(rating: 2200, sha256Prefix: 'ef114b96bb0d', expectedSize: 1160069);

  /// The name the network is stored under, both in the asset bundle and on disk.
  String get fileName => 'maia-$rating.pb.gz';

  /// Whether this network ships with the app rather than being downloaded.
  bool get isBundled => bundledRatings.contains(this);

  /// The network(s) that ship with the app.
  static const bundledRatings = {MaiaRating.maia1500};

  /// The network a new game plays by default.
  static const defaultRating = MaiaRating.maia1500;

  static MaiaRating? fromRating(int rating) => values.where((r) => r.rating == rating).firstOrNull;
}

/// What the computer opponent should be.
///
/// A value type, because it is the identity of an [EngineOpponent]: two screens asking for the
/// same opponent get the same one, and with it the same engine.
sealed class const OpponentSpec() {
  /// Reads a spec back from its [toJson].
  ///
  /// Falls back to the default Stockfish opponent rather than throwing: this is read from a saved
  /// game and from the preferences, and neither is worth losing over an opponent the app no longer
  /// knows about.
  factory fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'stockfish':
        final level = StockfishLevel.values.asNameMap()[json['level']];
        if (level != null) return StockfishOpponentSpec(level);
      case 'maia':
        final rating = MaiaRating.values.asNameMap()[json['rating']];
        if (rating != null) return MaiaOpponentSpec(rating);
    }
    return const StockfishOpponentSpec(StockfishLevel.defaultLevel);
  }

  /// The opponent a new game plays by default. Stockfish, which can play every variant.
  static const defaultSpec = StockfishOpponentSpec(StockfishLevel.defaultLevel);

  /// The engine this opponent plays [variant] on.
  ///
  /// A method rather than a getter because the answer depends on the variant: the app's
  /// Fairy-Stockfish plays every variant, while the stockfish installed on a machine the app
  /// bundles no engine for plays the standard game and nothing else.
  ///
  /// [engines] is that platform fact, taken as an argument rather than asked of the binding so that
  /// this stays answerable without one — see [engineAvailabilityProvider], which is where it is
  /// read.
  EngineSpec engineSpecFor(Variant variant, {required EngineAvailability engines});

  /// A short label for the UI.
  String get displayName;

  /// Whether this opponent can play [variant] at all.
  bool supportsVariant(Variant variant);

  /// Whether this opponent can play [variant] here, on this machine.
  ///
  /// [supportsVariant] answers for the engine alone; [engines] says whether that engine is on this
  /// machine at all. The two differ only where the app bundles no engine, which is no platform it is
  /// built for: there the game is played by the stockfish installed on the system, which knows the
  /// variants in [officialStockfishVariants] and no others, and Maia's LC0 is not installed at all,
  /// so Maia can play nothing.
  ///
  /// This is what the UI greys a choice out by, so it answers for what can actually be played here
  /// rather than for what the engine could do on a machine that has it.
  bool supports(Variant variant, {required EngineAvailability engines});

  Map<String, dynamic> toJson();
}

/// Stockfish at one of its twelve levels.
final class const StockfishOpponentSpec(final StockfishLevel level) extends OpponentSpec {
  /// Always Fairy-Stockfish: the weakest levels need negative skill levels, which only Fairy
  /// supports, and it is the only engine that can play every variant.
  ///
  /// Where the app ships no Fairy-Stockfish, the stockfish installed on the machine takes the
  /// standard game — the same games, and the same options, the app's Stockfish would have played,
  /// and the only ones that engine knows. Every other variant keeps asking for Fairy-Stockfish,
  /// which is neither installed nor bundled: that fails, loudly, rather than being played as
  /// something the engine cannot play.
  ///
  /// No platform the app is built for reaches that: the desktop ships Fairy-Stockfish like the
  /// phone does. It is kept because it is what the app does on a machine with nothing of its own,
  /// which is what [EngineAvailability.none] means and what the tests of that behaviour use.
  @override
  EngineSpec engineSpecFor(Variant variant, {required EngineAvailability engines}) =>
      !engines.fairy && officialStockfishVariants.contains(variant)
      ? const SystemStockfishSpec()
      : const StockfishSpec.fairy();

  @override
  String get displayName => 'Stockfish level ${level.level}';

  @override
  bool supportsVariant(Variant variant) => true;

  /// Every variant where the app ships Fairy-Stockfish; only the three the official engine plays
  /// where it does not, because those are the ones the system's stockfish is asked for.
  @override
  bool supports(Variant variant, {required EngineAvailability engines}) =>
      engines.fairy || officialStockfishVariants.contains(variant);

  @override
  Map<String, dynamic> toJson() => {'type': 'stockfish', 'level': level.name};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StockfishOpponentSpec && other.level == level;

  @override
  int get hashCode => level.hashCode;

  @override
  String toString() => 'StockfishOpponentSpec(${level.name})';
}

/// Maia at one of its rating bands.
final class const MaiaOpponentSpec(final MaiaRating rating) extends OpponentSpec {
  /// Maia is LC0 with a Maia network, and the network is a per-search option — so every rating is
  /// the same spec, and they all share one engine.
  ///
  /// The variant and the platform change nothing: LC0 ships in neither the app nor a package, and
  /// the app asks for it wherever it runs, on the variants the network can play.
  @override
  EngineSpec engineSpecFor(Variant variant, {required EngineAvailability engines}) =>
      const Lc0Spec();

  @override
  String get displayName => 'Maia ${rating.rating}';

  @override
  bool supportsVariant(Variant variant) =>
      variant == Variant.standard || variant == Variant.fromPosition;

  /// Only where the app ships LC0 — which is the phone, not the desktop, where it is not built at
  /// all. Anywhere else the network has no engine to run on, however many variants it could play.
  @override
  bool supports(Variant variant, {required EngineAvailability engines}) =>
      engines.lc0 && supportsVariant(variant);

  @override
  Map<String, dynamic> toJson() => {'type': 'maia', 'rating': rating.name};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MaiaOpponentSpec && other.rating == rating;

  @override
  int get hashCode => rating.hashCode;

  @override
  String toString() => 'MaiaOpponentSpec(${rating.name})';
}
