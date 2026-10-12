import 'dart:io';
import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:multistockfish/multistockfish.dart';

/// Which of the engines the app ships can be run here.
///
/// What it decides: which spec a flavor resolves to, which variants an opponent can be asked for,
/// and whether the settings that choose between the app's engines are worth showing at all. All
/// four flavours are on a phone and two are on the desktop this fork builds for — see
/// [EngineAvailability], which is where that platform fact is written down and why.
///
/// A provider rather than a question asked of the binding at each call site, because the tests that
/// want the desktop behaviour have no binding to ask — several run in a bare `ProviderContainer` —
/// and because the answer does not change over the life of a process.
final engineAvailabilityProvider = Provider<EngineAvailability>(
  (ref) => LichessBinding.instance.bundledEngines,
  name: 'EngineAvailabilityProvider',
);

/// Maximum number of CPU cores available for engine use.
final maxEngineCores = max(Platform.numberOfProcessors - 1, 1);

/// How much of a device's RAM engines may hold, in MB, given its [physicalMemoryInMb].
int engineMaxMemoryFor(int physicalMemoryInMb) => (physicalMemoryInMb / 16).ceil();

const _nnueDownloadUrl = '$kLichessCDNHost/assets/lifat/nnue/';

/// URL to download the latest NNUE network.
final nnueUrl = Uri.parse('$_nnueDownloadUrl${Stockfish.latestNNUE}');

/// SHA256 hash (first 12 digits) of the latest NNUE network.
final nnueHash = Stockfish.latestNNUE.substring(3, 15);

/// Size in bytes of the NNUE file as it is served.
///
/// Used as fallback for progress reporting when the server omits Content-Length.
const nnueExpectedSize = 73087040;

/// What the NNUE download costs, formatted as a human-readable string.
const nnueDownloadSizeMB = '${nnueExpectedSize ~/ (1024 * 1024)}MB';

/// The size of the net the latest Stockfish evaluates with, uncompressed.
///
/// Both Stockfish flavors the app ships are version 19 and report the same `id name`; the net they
/// evaluate with is the whole of the difference, so its size is what names them apart to the user.
/// Uncompressed on both sides, so that the two are compared like with like — the file this one is
/// read from is smaller on disk, which is what [nnueDownloadSizeMB] says.
const latestNetSizeMB = '94MB';

/// The size of the net built into the light Stockfish, uncompressed. See [latestNetSizeMB].
const lightNetSizeMB = '1MB';

/// Where the Maia networks that do not ship with the app are downloaded from.
const _maiaDownloadUrl = '$kLichessCDNHost/assets/lifat/maia/';

/// The directory, under the app support directory, that Maia networks are kept in.
const kMaiaWeightsDirName = 'maia';

/// The asset bundle directory the bundled Maia networks are read from.
/// See [MaiaRating.isBundled].
const kBundledMaiaAssetDir = 'assets/maia';

/// The asset the bundled Maia network for [fileName] is read from.
String bundledMaiaAsset(String fileName) => '$kBundledMaiaAssetDir/$fileName';

/// URL to download the Maia network for [fileName].
Uri maiaWeightsUrl(String fileName) => Uri.parse('$_maiaDownloadUrl$fileName');

/// The Pikafish network, which is bundled with the app rather than downloaded — see
/// `PikafishNnueService`.
///
/// Pikafish embeds no network: it loads one from disk through its `EvalFile` option, and an engine
/// started without one does not fail, it evaluates every position to noise — which on a board looks
/// like a computer playing at random rather than like a missing file. So the file is an asset, and
/// it is fetched into the asset tree by `scripts/fetch-pikafish-nnue.sh` at build time rather than
/// committed: 48 MB of binary in git is a cost every clone pays for the rest of the project's life.
///
/// The three values below are what that script checks the download against, and what the app checks
/// the copy it writes on first run against. They come in a set because they are one fact about one
/// file: the size and the hash of the network that is paired with the Pikafish snapshot vendored in
/// the `multistockfish_pikafish` package. A network from a different Pikafish is not refused with a
/// message — it is refused deep inside the first search — so if that snapshot is ever bumped,
/// these move with it.
const kPikafishNnueFileName = 'pikafish.nnue';

/// The asset the network is read from.
const kPikafishNnueAsset = 'assets/pikafish/$kPikafishNnueFileName';

/// The directory, under the app support directory, the network is written to.
///
/// A directory of its own rather than the app support directory itself, where Stockfish's networks
/// live: `StockfishNnueService` reads that directory for `*.nnue` files it does not recognise as
/// *Stockfish* networks, to offer reclaiming their space, and a Pikafish network sitting in it
/// would be listed as an outdated 48 MB Stockfish download.
const kPikafishNnueDirName = 'pikafish';

/// The size of the network in bytes, as the release serves it.
const kPikafishNnueSize = 50244700;

/// Its sha256, from the same release.
const kPikafishNnueSha256 = '10b84dd80bb4e324aa389cab327feeb7b4c44578e35a86105d4fcd5f840c3ac7';

final _sfVersionPattern = RegExp(r'Stockfish\s+(\d+)');

/// A function to choose the eval that should be displayed.
Eval? pickBestEval({
  /// The eval from the local engine
  required LocalEval? localEval,

  /// The cached eval which is either a saved eval from the local evaluation or a cloud eval
  required ClientEval? savedEval,

  /// The eval from the server analysis
  required ExternalEval? serverEval,
}) {
  if (localEval?.threatMode == true) {
    return localEval;
  }

  return switch (savedEval) {
    CloudEval() => savedEval,
    final LocalEval eval => localEval != null && localEval.isBetter(eval) ? localEval : eval,
    null => localEval ?? serverEval,
  };
}

/// A function to choose the client eval that should be displayed.
ClientEval? pickBestClientEval({
  /// The eval from the local engine
  required LocalEval? localEval,

  /// The cached eval which is either a saved eval from the local evaluation or a cloud eval
  required ClientEval? savedEval,
}) {
  final eval =
      pickBestEval(localEval: localEval, savedEval: savedEval, serverEval: null) as ClientEval?;

  return eval;
}

/// Extracts a short label like "SF 19" from a UCI engine name like "Stockfish 19.1".
///
/// Pass the [spec] the name came from to have the light Stockfish labelled by its net, which is
/// all that tells it apart from the full-net engine of the same version.
///
/// Returns null if the engine name is null or doesn't match the expected pattern.
String? engineShortLabel(String? engineName, {EngineSpec? spec}) {
  if (engineName == null) return null;
  if (engineName.startsWith('Fairy-Stockfish')) {
    return 'Fairy SF';
  }
  final match = _sfVersionPattern.firstMatch(engineName);
  if (match == null) return null;
  final label = 'SF ${match.group(1)}';
  return isLightStockfish(spec) ? '$label $lightNetSizeMB' : label;
}

/// The engine name to show the user, which says which net a light Stockfish runs.
String engineDisplayName(String? engineName, {EngineSpec? spec}) {
  final name = engineName ?? 'Stockfish';
  // The Fairy-Stockfish version is not the app's to advertise.
  if (name.startsWith('Fairy-Stockfish')) return 'Fairy-Stockfish';
  return isLightStockfish(spec) ? '$name ($lightNetSizeMB)' : name;
}

/// Whether [spec] is the Stockfish with the small net built in.
bool isLightStockfish(EngineSpec? spec) =>
    spec is StockfishSpec && spec.flavor == StockfishFlavor.light;

/// The (fake) position to use in threat mode searches.
Position threatModePosition(Position position) => position.copyWith(
  turn: position.turn.opposite,
  halfmoves: position.halfmoves + 1,
  fullmoves: position.turn == Side.black ? position.fullmoves + 1 : position.fullmoves,
);

/// Variants supported by the official Stockfish engine. Every other variant needs Fairy-Stockfish.
const officialStockfishVariants = {Variant.standard, Variant.chess960, Variant.fromPosition};

/// Whether [position] holds material the official Stockfish will not accept.
bool hasNonStandardMaterial(Position position) =>
    !_isStandardMaterialSide(position.board, Side.white) ||
    !_isStandardMaterialSide(position.board, Side.black);

bool _isStandardMaterialSide(Board board, Side side) {
  int count(Role role) => board.piecesOf(side, role).size;
  final bishops = board.piecesOf(side, Role.bishop);
  // Every piece beyond the ones a side starts with had to be promoted, and every promotion costs a
  // pawn — so pawns and promotions together cannot exceed the eight pawns a side starts with.
  final promoted =
      max(count(Role.queen) - 1, 0) +
      max(count(Role.rook) - 2, 0) +
      max(count(Role.knight) - 2, 0) +
      max(bishops.intersect(SquareSet.lightSquares).size - 1, 0) +
      max(bishops.intersect(SquareSet.darkSquares).size - 1, 0);
  return count(Role.pawn) + promoted <= 8;
}

extension FairyVariantExtension on Variant {
  /// The Fairy-Stockfish variant name, for the `UCI_Variant` option.
  String get fairy => switch (this) {
    Variant.standard => 'chess',
    Variant.chess960 => 'chess',
    Variant.fromPosition => 'chess',
    Variant.antichess => 'antichess',
    Variant.kingOfTheHill => 'kingofthehill',
    Variant.threeCheck => '3check',
    Variant.atomic => 'atomic',
    Variant.horde => 'horde',
    Variant.racingKings => 'racingkings',
    Variant.crazyhouse => 'crazyhouse',
  };
}
