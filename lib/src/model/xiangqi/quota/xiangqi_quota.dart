import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' show Client, Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

part 'xiangqi_quota.freezed.dart';

/// The name xiangqi.com files its daily puzzle allowance under.
///
/// The names are the server's own strings, and they are spelled out here rather than typed at each
/// call site because they are what the endpoints take and give back: `POST /api/quota/usage` is
/// asked to consume one by name, and `GET /api/quota/state` answers a map keyed by them.
const kXiangqiQuotaPuzzles = 'puzzles';

/// The name of the daily hint allowance, which is the one feature the puzzle screen consumes.
const kXiangqiQuotaPuzzleHints = 'puzzle_hints';

/// The name of the daily puzzle-race allowance.
const kXiangqiQuotaPuzzleRace = 'puzzle_race';

/// One feature's allowance, as `GET /api/quota/state` reports it.
@freezed
sealed class const XiangqiQuotaFeature._() with _$XiangqiQuotaFeature {
  const factory({
    /// How much of the allowance is left today.
    required int remaining,

    /// What the allowance is for the day.
    required int limit,
  }) = _XiangqiQuotaFeature;

  /// Whether the day's allowance is spent.
  ///
  /// `remaining <= 0` rather than `== 0`: the server has only ever been measured answering zero, but
  /// a negative would mean the same thing and there is no reason to draw a bar for it.
  bool get isExhausted => remaining <= 0;
}

/// What xiangqi.com says is left of every daily allowance, from `GET /api/quota/state`.
///
/// ## What this is, and what it is not
///
/// It is a **report**, and the screen draws it as one: "3 of 15 puzzles left today". It is not a
/// gate, and nothing in this app refuses a request because of what it says. The server refuses —
/// `GET /api/puzzle/P/<id>` answers `429` once `puzzles` is spent, and `POST /api/quota/usage`
/// answers `allowed: false` once `puzzle_hints` is — and a client that also refused would be a
/// second, staler opinion about a number only the server keeps. The shipped web client gets this
/// wrong in the other direction: it marks `puzzles` and `puzzle_race` as locally enforced and never
/// asks, while the server enforces both anyway. See `xiangqi-com-re/docs/quota.md`.
@freezed
sealed class const XiangqiQuotaState._() with _$XiangqiQuotaState {
  const factory({
    /// `user_type`: `"free"` on the account every measurement was taken with.
    required String userType,

    /// `reset_in_seconds`: how long until the day's allowances come back.
    required Duration resetIn,

    /// Every feature the server reports, by its own name.
    required IMap<String, XiangqiQuotaFeature> features,
  }) = _XiangqiQuotaState;

  /// What is left of [name], or null for a feature the server did not report.
  XiangqiQuotaFeature? feature(String name) => features[name];
}

/// The answer to a request to spend one allowance, from `POST /api/quota/usage`.
@freezed
sealed class const XiangqiQuotaUsage._() with _$XiangqiQuotaUsage {
  const factory({
    /// The feature that was asked for.
    required String feature,

    /// Whether the server let the request through.
    required bool allowed,

    /// What is left afterwards, when the server says.
    int? remaining,

    /// Why the server answered as it did: `"ok"`, `"exhausted"` or `"subscription_required"`, or
    /// null when it says nothing.
    String? reason,
  }) = _XiangqiQuotaUsage;
}

/// A provider for [XiangqiQuotaRepository].
final xiangqiQuotaRepositoryProvider = Provider<XiangqiQuotaRepository>((Ref ref) {
  return XiangqiQuotaRepository(ref.read(xiangqiClientProvider));
}, name: 'XiangqiQuotaRepositoryProvider');

/// The daily allowances, from `GET /api/quota/state`.
///
/// **No session, no request**: an account that has never signed in to xiangqi.com has no allowances
/// there, and asking would be a request the server can only refuse. Offline is an [Error] rather
/// than an empty state, for the reason every other xiangqi provider gives — `lichessProviderRetry`
/// never retries an [Error], so being offline is settled at once.
final xiangqiQuotaStateProvider = FutureProvider.autoDispose<XiangqiQuotaState>((Ref ref) {
  if (ref.watch(xiangqiAuthControllerProvider) == null) {
    throw StateError('No xiangqi.com session; not asking for the daily allowances.');
  }
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw StateError('The device is offline; not asking xiangqi.com for the daily allowances.');
  }
  return ref.read(xiangqiQuotaRepositoryProvider).state();
}, name: 'XiangqiQuotaStateProvider');

/// The two quota endpoints, as calls.
///
/// A class rather than loose functions because the puzzle screen's hint button has to *spend* an
/// allowance and then act on the answer, which is a sequence rather than a fetch — see
/// `XiangqiPuzzleController.hint`. The read side is still a provider
/// ([xiangqiQuotaStateProvider]), so a screen that only wants to draw the numbers does not have to
/// hold this at all.
class const XiangqiQuotaRepository(final Client _client) {
  /// What is left of every allowance today.
  Future<XiangqiQuotaState> state() async {
    final uri = xiangqiUri('quota/state');
    final response = await _client.get(uri, headers: const {'Accept': 'application/json'});
    _check(response, uri, 'xiangqi.com quota lookup failed.');
    final json = _decodeObject(_bodyText(response));

    final features = <String, XiangqiQuotaFeature>{};
    final raw = json['features'];
    if (raw is Map<String, dynamic>) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        features[entry.key] = XiangqiQuotaFeature(
          remaining: _int(value['remaining']) ?? 0,
          limit: _int(value['limit']) ?? 0,
        );
      }
    }

    return XiangqiQuotaState(
      userType: json['user_type'] is String ? json['user_type'] as String : '',
      resetIn: Duration(seconds: _int(json['reset_in_seconds']) ?? 0),
      features: features.lock,
    );
  }

  /// Asks the server to spend one [feature], and reports what it said.
  ///
  /// **This is the gate, and it is the server's.** A caller that wants to know whether it may show a
  /// hint asks here rather than counting locally; `allowed: false` is the answer, and there is no
  /// second opinion to be had. The endpoint is a `POST` and not a `GET` — measured on 2026-10-16,
  /// a `GET` is a `405` — because it is a spend and not a read.
  ///
  /// Only the three features the shipped client marks as server-enforced may be spent here:
  /// `puzzle_hints`, `undo_bot` and `bot_hints`. `puzzles` and `puzzle_race` answer `400
  /// "feature is not consumable via this endpoint"` because their own endpoints charge for them
  /// implicitly, and this method passes that failure through as a [ServerException] rather than
  /// pretending it succeeded.
  Future<XiangqiQuotaUsage> consume(String feature) async {
    final uri = xiangqiUri('quota/usage');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'feature': feature}),
    );
    _check(response, uri, 'xiangqi.com quota spend failed.');
    final json = _decodeObject(_bodyText(response));
    return XiangqiQuotaUsage(
      feature: json['feature'] is String ? json['feature'] as String : feature,
      allowed: json['allowed'] == true,
      remaining: _int(json['remaining']),
      reason: json['reason'] is String ? json['reason'] as String : null,
    );
  }
}

/// Throws a [ServerException] unless [response] is a success.
void _check(Response response, Uri uri, String message) {
  if (response.statusCode < 400) return;
  throw ServerException(response.statusCode, message, uri, null);
}

/// The response body as text, decoded as UTF-8 whatever the headers claim.
String _bodyText(Response response) => utf8.decode(response.bodyBytes);

/// The JSON object [body] holds, or a [FormatException] if it holds anything else.
Map<String, dynamic> _decodeObject(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    throw const FormatException('xiangqi.com answered with something that is not JSON.');
  }
  if (json is! Map<String, dynamic>) {
    throw const FormatException('xiangqi.com answered with JSON that is not an object.');
  }
  return json;
}

/// [value] as an integer, or null. A JSON number may arrive as a double, so both are accepted.
int? _int(Object? value) => value is num ? value.toInt() : null;
