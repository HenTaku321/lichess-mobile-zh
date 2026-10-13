import 'package:freezed_annotation/freezed_annotation.dart';

part 'xiangqi_session.freezed.dart';

/// The signed-in xiangqi.com account.
///
/// Deliberately not a [User]-shaped profile: xiangqi.com's identity is a single
/// account per backend, carrying nothing the lichess account model has.
@freezed
sealed class const XiangqiSession._() with _$XiangqiSession {
  const factory({
    required String userId,
    required String name,
    required String accessToken,
    String? refreshToken,
    required bool isGuest,
  }) = _XiangqiSession;
}
