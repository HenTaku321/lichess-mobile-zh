import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/service/linux_audio_processes.dart';
import 'package:logging/logging.dart';
import 'package:sound_effect/sound_effect.dart';

/// Maximum number of concurrent sounds that can be played.
const _kMaxConcurrentStreams = 2;

final _soundEffectPlugin = SoundEffect();

final _logger = Logger('SoundService');

// Must match name of files in assets/sounds/standard
enum Sound() {
  move,
  capture,
  explosion,
  lowTime,
  dong,
  error,
  confirmation,
  puzzleStormEnd,
  clock,
  berserk,

  // Sounds of the learn feature, which exist in the standard theme only.
  learnTake,
  learnLevelStart,
  learnLevelEnd,
  learnStageStart,
  learnStageEnd,
  learnFailure,
}

/// A provider for [SoundService].
final soundServiceProvider = Provider<SoundService>((Ref ref) {
  final service = SoundService(ref);
  ref.onDispose(() => service.release());
  return service;
}, name: 'SoundServiceProvider');

final _extension = defaultTargetPlatform == TargetPlatform.iOS ? 'aifc' : 'mp3';

// The players are process-wide, so initialization, theme changes and release must share a queue
// even when a SoundService provider is disposed and recreated while an asset load is pending.
Future<void> _soundOperations = Future<void>.value();
Future<void>? _soundShutdown;
int _soundGeneration = 0;
bool _soundsReady = false;

bool _isCurrentSoundLoad(int generation) =>
    _soundShutdown == null && generation == _soundGeneration;

Future<void> _queueSoundOperation(Future<void> Function() operation) {
  final result = _soundOperations.then((_) => operation());
  _soundOperations = result.catchError((Object error, StackTrace stack) {
    _logger.warning('Sound operation failed:', error, stack);
  });
  return result;
}

Future<void> _releaseSounds() => defaultTargetPlatform == TargetPlatform.linux
    ? _linuxSoundPlayer.release()
    : _soundEffectPlugin.release();

Future<void> _initializeSoundPlayer() async {
  if (defaultTargetPlatform == TargetPlatform.linux) {
    _linuxSoundPlayer.initialize();
  } else {
    await _soundEffectPlugin.initialize(maxStreams: _kMaxConcurrentStreams);
  }
}

final _linuxSoundPlayer = _LinuxSoundPlayer();

/// Linux audio player using system audio backends (pw-play, paplay, or aplay).
class _LinuxSoundPlayer() {
  final Map<String, String> _soundPaths = {};
  String? _playerCmd;
  LinuxAudioProcesses _processes = LinuxAudioProcesses();
  bool _closed = false;
  int _generation = 0;

  void initialize() {
    if (_hasCmd('pw-play')) {
      _playerCmd = 'pw-play';
    } else if (_hasCmd('paplay')) {
      _playerCmd = 'paplay';
    } else if (_hasCmd('aplay')) {
      _playerCmd = 'aplay';
    }
  }

  bool _hasCmd(String cmd) {
    if (File('/usr/bin/$cmd').existsSync() || File('/usr/local/bin/$cmd').existsSync()) {
      return true;
    }
    try {
      final res = Process.runSync('which', [cmd]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> load(SoundTheme theme, String soundId, String fullPath) async {
    if (_closed) return;
    final generation = _generation;
    try {
      final tmpDir = Directory('${Directory.systemTemp.path}/lichess_sounds');
      if (!tmpDir.existsSync()) {
        tmpDir.createSync(recursive: true);
      }
      final destFile = File('${tmpDir.path}/${theme.name}_$soundId.$_extension');
      if (!destFile.existsSync()) {
        final byteData = await rootBundle.load(fullPath);
        await destFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      }
      if (!_closed && generation == _generation) _soundPaths[soundId] = destFile.path;
    } catch (e) {
      _logger.warning('Failed to cache Linux sound $soundId ($fullPath):', e);
    }
  }

  Future<void> play(String soundId, {double volume = 1.0}) async {
    final filePath = _soundPaths[soundId];
    if (_closed || filePath == null || _playerCmd == null) return;

    final vol = volume.clamp(0.0, 1.0);
    if (_playerCmd == 'pw-play') {
      await _processes.play('pw-play', ['--volume=$vol', filePath]);
    } else if (_playerCmd == 'paplay') {
      final paVol = (vol * 65536).toInt();
      await _processes.play('paplay', ['--volume=$paVol', filePath]);
    } else {
      await _processes.play(_playerCmd!, [filePath]);
    }
  }

  Future<void> release() async {
    _generation++;
    _soundPaths.clear();
    await _processes.shutdown();
    if (!_closed) _processes = LinuxAudioProcesses();
  }

  Future<void> shutdown() {
    _closed = true;
    _generation++;
    _soundPaths.clear();
    return _processes.shutdown();
  }
}

/// Loads all sounds of the given [SoundTheme].
Future<void> _loadAllSounds(SoundTheme soundTheme, int generation) async {
  await Future.wait(Sound.values.map((sound) => _loadSound(soundTheme, sound, generation)));
}

/// Loads a single sound from the given [SoundTheme].
Future<void> _loadSound(SoundTheme theme, Sound sound, int generation) async {
  if (!_isCurrentSoundLoad(generation)) return;
  final themePath = 'assets/sounds/${theme.name}';
  const standardPath = 'assets/sounds/standard';
  final soundId = sound.name;
  final file = '$soundId.$_extension';
  String fullPath = '$themePath/$file';
  // If the sound file is not found in the theme, fallback to the standard theme.
  try {
    await rootBundle.load(fullPath);
  } catch (_) {
    fullPath = '$standardPath/$file';
  }
  if (!_isCurrentSoundLoad(generation)) return;
  if (defaultTargetPlatform == TargetPlatform.linux) {
    await _linuxSoundPlayer.load(theme, soundId, fullPath);
  } else {
    await _soundEffectPlugin.load(soundId, fullPath);
  }
}

/// Service to play game sounds.
class SoundService(final Ref _ref) {
  /// Stop accepting Linux sounds before waiting for player processes to exit.
  static Future<void> shutdown() {
    if (_soundShutdown case final pending?) return pending;
    _soundsReady = false;
    _soundGeneration++;
    // Stop Linux players immediately, including launches already pending. Asset loads drain
    // before the shutdown future completes and cannot publish sounds after the player is sealed.
    final linuxShutdown = _linuxSoundPlayer.shutdown();
    return _soundShutdown = _queueSoundOperation(() async {
      await linuxShutdown;
      if (defaultTargetPlatform != TargetPlatform.linux) await _soundEffectPlugin.release();
    });
  }

  /// Initialize the sound service.
  ///
  /// This will load the sounds from assets and make them ready to be played.
  /// This should be called once when the app starts.
  static Future<void> initialize() async {
    if (_soundShutdown != null) return;
    final generation = ++_soundGeneration;
    _soundsReady = false;
    try {
      await _queueSoundOperation(() async {
        if (!_isCurrentSoundLoad(generation)) return;
        final stored = LichessBinding.instance.sharedPreferences.getString(
          PrefCategory.general.storageKey,
        );
        final theme =
            (stored != null
                    ? GeneralPrefs.fromJson(jsonDecode(stored) as Map<String, dynamic>)
                    : GeneralPrefs.defaults)
                .soundTheme;
        await _initializeSoundPlayer();
        await _loadAllSounds(theme, generation);
        if (_isCurrentSoundLoad(generation)) _soundsReady = true;
      });
    } catch (e, st) {
      _logger.warning('Failed to initialize sound service:', e, st);
    }
  }

  /// Play the given sound if sound is enabled.
  Future<void> play(Sound sound, {double volume = 1.0}) async {
    assert((volume >= 0.0) && (volume <= 1.0));
    if (!_soundsReady || _soundShutdown != null) return;
    final isEnabled = _ref.read(generalPreferencesProvider).isSoundEnabled;
    final finalVolume = _ref.read(generalPreferencesProvider).masterVolume * volume;
    if (!isEnabled || finalVolume == 0.0) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      await _linuxSoundPlayer.play(sound.name, volume: finalVolume);
    } else {
      await _soundEffectPlugin.play(sound.name, volume: finalVolume);
    }
  }

  /// Play the capture sound for the given chess [variant].
  Future<void> playCaptureSound(Variant variant, {double volume = 1.0}) async {
    await play(variant == Variant.atomic ? Sound.explosion : Sound.capture, volume: volume);
  }

  /// Change the sound theme and optionally play a move sound.
  ///
  /// This will release the previous sounds and load the new ones.
  ///
  /// If [playSound] is true, a move sound will be played.
  Future<void> changeTheme(SoundTheme theme, {bool playSound = false}) {
    if (_soundShutdown != null) return Future<void>.value();
    final generation = ++_soundGeneration;
    _soundsReady = false;
    return _queueSoundOperation(() async {
      if (!_isCurrentSoundLoad(generation)) return;
      await _releaseSounds();
      if (!_isCurrentSoundLoad(generation)) return;
      await _initializeSoundPlayer();
      await _loadAllSounds(theme, generation);
      if (!_isCurrentSoundLoad(generation)) return;
      _soundsReady = true;
      if (playSound && _ref.mounted) await play(Sound.move);
    });
  }

  Future<void> release() {
    if (_soundShutdown case final pending?) return pending;
    _soundGeneration++;
    _soundsReady = false;
    return _queueSoundOperation(_releaseSounds);
  }
}
