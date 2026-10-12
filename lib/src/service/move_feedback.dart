import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';

/// A provider for [MoveFeedbackService].
final moveFeedbackServiceProvider = Provider<MoveFeedbackService>((Ref ref) {
  final soundService = ref.watch(soundServiceProvider);
  return MoveFeedbackService(soundService, ref);
}, name: 'MoveFeedbackServiceProvider');

class MoveFeedbackService(final SoundService _soundService, final Ref _ref) {
  void moveFeedback({bool check = false}) {
    _soundService.play(Sound.move);

    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      if (check) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  /// The feedback for a standard chess move written as [san]: a capture or a move, with or without
  /// a check.
  void playedMove(String san) {
    final check = san.contains('+') || san.contains('#');
    if (san.contains('x')) {
      captureFeedback(Variant.standard, check: check);
    } else {
      moveFeedback(check: check);
    }
  }

  /// The feedback for a capture, in the chess [variant] it was played in — or null, for a capture in
  /// a game that is not chess at all.
  ///
  /// Xiangqi is the caller that has no variant to give: its pieces and its rules are none of
  /// `dartchess`'s business, and the only thing a variant decides here is whether the sound is an
  /// atomic explosion, which no game but chess atomic has. A null is therefore handed on as
  /// [Variant.standard] — the capture sound, which is what a capture always sounds like.
  void captureFeedback(Variant? variant, {bool check = false}) {
    _soundService.playCaptureSound(variant ?? Variant.standard);

    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      if (check) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }
}
