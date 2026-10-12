/// An engine the app can run. At most one engine per slot can be live in the process.
///
/// This is the only place in the app that names the single-instance constraint;
/// everything above works with [EngineSpec] and never has to think about it. Two [EngineSpec]s
/// that resolve to the same slot are the same spec, so a slot can never be asked for two engines
/// through the ordinary engine plumbing.
///
/// Every slot but [system] is a native library the plugin creates in-process, where one instance
/// is all the platform allows. [system] is a child process, and there the rule is a choice —
/// one process for the evaluator and the opponent to share — rather than a constraint.
enum EngineSlot() {
  /// Stockfish with its small NNUE network embedded in the binary.
  sfLight,

  /// The latest Stockfish, whose network is loaded from disk.
  sfLatest,

  /// Fairy-Stockfish: chess variants, and negative skill levels.
  fairy,

  /// Pikafish: xiangqi, and nothing else.
  ///
  /// A fourth native library rather than a fourth setting on the third, so it
  /// wants a slot of its own — the plugin keeps one engine per flavour, and the
  /// app's xiangqi games would otherwise fight a chess analysis over the same
  /// library.
  pikafish,

  /// Leela Chess Zero, which is also how Maia is played: Maia is LC0 with a
  /// Maia network.
  lc0,

  /// The stockfish installed on this machine, run as a child process.
  system,
}
