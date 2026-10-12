import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PikafishNnueService');

/// A provider for [PikafishNnueService].
final pikafishNnueServiceProvider = Provider<PikafishNnueService>((Ref ref) {
  return PikafishNnueService(ref);
}, name: 'PikafishNnueServiceProvider');

/// Puts the Pikafish network where the engine can read it.
///
/// Pikafish takes its network from a path rather than from bytes — its `EvalFile` option — so the
/// copy in the asset bundle is not enough: it has to exist as a file before an engine is started,
/// and this service is what makes that true.
///
/// The network is bundled rather than downloaded, and that is the whole of the difference between
/// this and `StockfishNnueService`: a xiangqi game is played offline, on a plane or in a tunnel, and
/// an opponent that needs 48 MB over the wire before its first move is not an offline opponent. So
/// there is no download here, no progress to report and no failure that depends on the network —
/// only a copy out of the bundle, and the two ways it can go wrong are a file that was not bundled
/// and a file that did not survive being written.
class PikafishNnueService(final Ref _ref) {
  /// The write in progress, so that a second caller joins it rather than writing the same 48 MB a
  /// second time — the screen and the controller both ask, and on a cold start they ask together.
  Future<String>? _inFlight;

  /// Where the network lives, whether or not it is there yet.
  ///
  /// A directory of its own under the app support directory: see [kPikafishNnueDirName] for why it
  /// must not sit in the app support directory itself.
  ///
  /// Throws if the app support directory is not available.
  File get nnueFile {
    final appSupportDirectory = _ref.read(preloadedDataProvider).requireValue.appSupportDirectory;
    if (appSupportDirectory == null) {
      throw Exception('App support directory is null.');
    }
    return File('${appSupportDirectory.path}/$kPikafishNnueDirName/$kPikafishNnueFileName');
  }

  /// The absolute path to pass to the engine as its `EvalFile`, writing the network out if it is
  /// not already there.
  ///
  /// Throws if the network cannot be produced — the bundle does not hold it, or the write did not
  /// survive its checksum. Both mean there is no xiangqi opponent to be had on this build, and the
  /// caller is better off saying so than starting a game against an engine that evaluates noise.
  Future<String> ensureNnue() {
    if (_inFlight case final inFlight?) return inFlight;
    final write = _ensure().whenComplete(() => _inFlight = null);
    _inFlight = write;
    return write;
  }

  Future<String> _ensure() async {
    final file = nnueFile;
    if (await _isThere(file)) return file.path;
    return await _writeFromBundle(file);
  }

  /// Whether the network is on disk whole.
  ///
  /// The size alone, and not the checksum: the file is one this app wrote and checked, so the only
  /// thing that can happen to it afterwards is being truncated or removed by someone else, and a
  /// size test catches both without reading 48 MB off the disk on every launch. The checksum is
  /// spent where it is worth spending — on the write, which is the one moment the file is new.
  Future<bool> _isThere(File file) async {
    try {
      if (!await file.exists()) return false;
      return await file.length() == kPikafishNnueSize;
    } catch (e, st) {
      _logger.warning('Could not look at ${file.path}:', e, st);
      return false;
    }
  }

  Future<String> _writeFromBundle(File file) async {
    _logger.info('Writing the bundled Pikafish network to ${file.path}');
    try {
      await file.parent.create(recursive: true);
      final bytes = await rootBundle.load(kPikafishNnueAsset);
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } catch (e, st) {
      _logger.severe('Could not write the Pikafish network:', e, st);
      throw Exception('The Pikafish network could not be written to disk.');
    }

    final path = file.path;
    final ok = await Isolate.run(() => _sha256Of(path) == kPikafishNnueSha256);
    if (!ok) {
      _logger.severe('The Pikafish network did not survive being written, deleting it.');
      try {
        await file.delete();
      } catch (e, st) {
        _logger.warning('Could not delete ${file.path}:', e, st);
      }
      throw Exception('The Pikafish network did not survive being written.');
    }
    return path;
  }
}

String _sha256Of(String filePath) => sha256.convert(File(filePath).readAsBytesSync()).toString();
