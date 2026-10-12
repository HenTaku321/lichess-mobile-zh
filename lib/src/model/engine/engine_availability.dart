import 'package:lichess_mobile/src/model/engine/engine_slot.dart';
import 'package:meta/meta.dart';

/// Which of the engines the app can run are on the machine it is running on.
///
/// The app's engines are native libraries in the bundle, one per [EngineSlot] but [EngineSlot.system],
/// and which of them a build carries is a platform fact: a flavour is compiled in or it is not, and
/// nothing at runtime changes that. One fact, so one value — and a value because it is passed to the
/// code that decides what to offer, which is not the code that knows the platform.
///
/// **Why this is not a boolean.** It used to be one — `hasBundledEngines` — and the boolean could
/// only say "the app's engines" or "none of them". The Linux desktop build ships the light Stockfish
/// and Fairy-Stockfish and nothing else, and neither answer describes it: with `true` the settings
/// screen offered a 73 MB download for an engine that cannot run there, and Maia lit up on a machine
/// with no LC0; with `false` the eight variants the desktop can now play were greyed out as if the
/// system's stockfish were the only engine in reach. The two platforms the app shipped for happened
/// to have all of them or none, so one bit was enough; Linux is the case that is neither, and it is
/// why this type exists.
///
/// The [phone] and [desktop] values are the two platforms; see each for what it has and why.
@immutable
class const EngineAvailability({
  /// Stockfish with a small NNUE network built into the library, and no file to load.
  required final bool sfLight,

  /// Stockfish with the full network, which is loaded from a file on disk.
  required final bool sfLatest,

  /// Fairy-Stockfish: the chess variants, and the negative skill levels the weakest opponents need.
  required final bool fairy,

  /// Leela Chess Zero, which is also how Maia is played: LC0 with a Maia network.
  required final bool lc0,

  /// Pikafish, the xiangqi engine. Where it is built it is always usable, because its network
  /// ships inside the app rather than being fetched: there is no download to have failed.
  required final bool pikafish,
}) {
  /// Android and iOS, where the app ships every flavour.
  static const phone = EngineAvailability(
    sfLight: true,
    sfLatest: true,
    fairy: true,
    lc0: true,
    pikafish: true,
  );

  /// The Linux desktop build: the light Stockfish and Fairy-Stockfish, both compiled into the
  /// bundle, and no download needed for either.
  ///
  /// The two the app does not ship there are left out for different reasons.
  ///
  /// `sfLatest` is out because its network is a 73 MB download for a deeper search on the same three
  /// variants the light Stockfish plays out of the box — and the desktop's one advantage over the
  /// phone is that it works the moment it is installed, offline. There is a harder reason underneath
  /// that one, which makes the missing 73 MB beside the point: a Stockfish that loads its network
  /// from a file goes through the system-wide shared allocation in the engine's `shm.h`, and on
  /// Linux that deadlocks — the engine reads `go`, unlinks its own socket under
  /// `/tmp/stockfish-<uid>/sfshm_<hash>/`, and then waits for a signal that never comes. That path is
  /// compiled in for `(linux && !android) || apple || *bsd`: Android never has it, and on iOS `/tmp`
  /// is not writable so the engine gives up on the shared net early and keeps it in private memory.
  /// Linux is the only platform where it is both compiled in and able to run, and the only platform
  /// upstream does not build these packages for. Measured on this fork's Linux build, with a network
  /// file and without one, from a clean `/tmp`.
  ///
  /// `lc0` is out because building it is a different order of work from the three Stockfish
  /// flavours: Eigen, protobuf, and a patch to its own build. Until that is done Maia has no engine
  /// to run on the desktop and stays greyed out, which is what the app's `MaiaOpponentSpec` reads
  /// this for.
  static const desktop = EngineAvailability(
    sfLight: true,
    sfLatest: false,
    fairy: true,
    lc0: false,
    pikafish: true,
  );

  /// A build that ships no engine of its own.
  ///
  /// No platform the app is built for, and the value the tests of that behaviour use: the engines
  /// are then whatever the machine has, which is the stockfish on the `PATH` run as a child process,
  /// and no Maia.
  static const none = EngineAvailability(
    sfLight: false,
    sfLatest: false,
    fairy: false,
    lc0: false,
    pikafish: false,
  );

  /// Whether the app has any engine of its own here.
  ///
  /// What the boolean this replaced was asked, and the only thing it could be asked: where it is
  /// false the engines are the machine's, which is the branch every remaining caller of this is on.
  bool get any => sfLight || sfLatest || fairy || lc0 || pikafish;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineAvailability &&
          other.sfLight == sfLight &&
          other.sfLatest == sfLatest &&
          other.fairy == fairy &&
          other.lc0 == lc0 &&
          other.pikafish == pikafish;

  @override
  int get hashCode => Object.hash(sfLight, sfLatest, fairy, lc0, pikafish);

  @override
  String toString() {
    final flavours = [
      if (sfLight) 'light',
      if (sfLatest) 'latest',
      if (fairy) 'fairy',
      if (lc0) 'lc0',
      if (pikafish) 'pikafish',
    ];
    return 'EngineAvailability(${flavours.isEmpty ? 'none' : flavours.join(', ')})';
  }
}
