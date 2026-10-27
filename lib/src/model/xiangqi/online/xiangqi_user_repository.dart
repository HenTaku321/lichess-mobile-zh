import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' show Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

part 'xiangqi_user_repository.freezed.dart';

/// A signed-in xiangqi.com account's profile, as far as this app shows it.
///
/// Only the fields the account row draws are modelled. The endpoint answers with a good deal more
/// than this — badges, an email address, a friend count and a handful of access flags — and none of
/// it is carried here: a field that is not on this class is a field nothing in the app reads.
///
/// The ratings are nullable because an account that has never played a given speed has no rating
/// for it rather than a zero, and the country is nullable because the wire sends `null` for an
/// account that has not set one.
@freezed
sealed class const XiangqiUserProfile._() with _$XiangqiUserProfile {
  const factory({
    required String username,
    int? bulletRating,
    int? rapidRating,
    int? dailyRating,
    int? puzzleRating,
    required bool isOnline,
    String? countryName,

    /// The account's own short biography, or null when it has never been set.
    ///
    /// The wire sends `null` and the edit form sends the empty string, so both mean "nothing to
    /// read" and both are kept as the string they are. The profile screen decides whether to draw
    /// a row; the model does not turn one into the other.
    String? bio,

    /// When the account was created, from `member_since`.
    ///
    /// Nullable although the wire does send it: the value is an RFC-1123 HTTP-date
    /// (`"Tue, 14 Nov 2023 22:13:20 GMT"`, the shape measured on 2026-08-30) and a value this app
    /// cannot read
    /// is dropped rather than turned into a made-up instant.
    DateTime? memberSince,
  }) = _XiangqiUserProfile;
}

/// The xiangqi.com profile of [username], from `GET /api/users/account/<username>`.
///
/// **A guest token is enough for this endpoint.** It is a public account lookup, and it was
/// measured answering 200 to a session that is not a real account — so the fetch is gated on the
/// device being online and on nothing else. Gating it on a real account would leave the row blank
/// for a guest for no reason the server asked for.
///
/// Offline, this throws a [StateError] rather than asking. An [Error] and not an [Exception],
/// deliberately: `lichessProviderRetry` never retries an [Error], so being offline is settled at
/// once instead of six times over with a back-off in between (see `utils/riverpod.dart`). The row
/// that watches this draws no subtitle for a profile that is loading or failed, so an error here is
/// a quieter state than a spinner would be.
final xiangqiUserProvider = FutureProvider.autoDispose.family<XiangqiUserProfile, String>((
  Ref ref,
  String username,
) async {
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw StateError('The device is offline; not asking xiangqi.com for $username.');
  }

  // The username goes in raw: [xiangqiUri] builds the URL with `Uri.https`, which percent-encodes
  // the path itself, so pre-encoding it here would double-encode it.
  final uri = xiangqiUri('users/account/$username');
  final response = await ref.read(xiangqiClientProvider).get(uri);

  if (response.statusCode >= 400) {
    throw ServerException(response.statusCode, 'xiangqi.com account lookup failed.', uri, null);
  }

  return xiangqiUserProfileFromJson(_decodeObject(_bodyText(response)), username: username);
}, name: 'XiangqiUserProvider');

/// The profile [json] describes, read for the fields [XiangqiUserProfile] carries.
///
/// Every field is read defensively: a missing rating is a null rating, a missing country is a null
/// country, and a `member_since` that will not parse is a null date. Nothing here throws on a
/// payload that is merely thin — only [_decodeObject] rejects a body that is not a JSON object, and
/// the HTTP status is what rejects a request the server refused.
///
/// [username] is the name the profile was asked for, and is the fallback when the payload does not
/// carry one.
XiangqiUserProfile xiangqiUserProfileFromJson(
  Map<String, dynamic> json, {
  required String username,
}) {
  final country = json['country'];
  final memberSince = json['member_since'];
  final bio = json['bio'];

  return XiangqiUserProfile(
    username: _string(json['username']) ?? username,
    bulletRating: _int(json['bullet_rating']),
    rapidRating: _int(json['rapid_rating']),
    dailyRating: _int(json['daily_rating']),
    puzzleRating: _int(json['puzzle_rating']),
    isOnline: json['is_online'] == true,
    countryName: country is Map<String, dynamic> ? _string(country['name']) : null,
    bio: bio is String ? bio : null,
    memberSince: memberSince is String ? _httpDate(memberSince) : null,
  );
}

/// The fields the edit-profile form starts from, read from the same account payload.
///
/// This is deliberately separate from [XiangqiUserProfile]: the profile row is a public summary,
/// while an edit form also needs the account's email and the numeric country id the write endpoint
/// takes. Keeping the write-only shape out of the public model means a profile screen cannot
/// accidentally draw an email it was never meant to show.
final class const XiangqiEditableProfile({
  required final String username,
  required final String email,
  required final String bio,
  final int? countryId,
  final String? countryCode,
  final String? countryName,
  final String? profileImage,
});

/// One row of `GET /api/users/countries`.
///
/// The edit endpoint wants the numeric `value` under the name `country`, while the UI shows the
/// human name. Both are kept together so a selected country can be sent without a second lookup.
final class const XiangqiCountryOption({
  required final int id,
  required final String code,
  required final String name,
});

/// Thrown when the account update endpoint refuses the submitted profile.
///
/// [message] is the server's own sentence when it sent one; otherwise it is a neutral fallback.
final class const XiangqiProfileUpdateException(final String message) implements Exception {
  @override
  String toString() => message;
}

/// The edit form's starting values for [username].
final xiangqiEditableProfileProvider = FutureProvider.autoDispose
    .family<XiangqiEditableProfile, String>((Ref ref, String username) async {
      ref.watch(xiangqiAccountGenerationProvider);
      if (!ref.watch(isDeviceOnlineProvider)) {
        throw StateError('The device is offline; not asking xiangqi.com for $username.');
      }
      final uri = xiangqiUri('users/account/$username');
      final response = await ref.read(xiangqiClientProvider).get(uri);
      if (response.statusCode >= 400) {
        throw ServerException(response.statusCode, 'xiangqi.com account lookup failed.', uri, null);
      }
      return xiangqiEditableProfileFromJson(_decodeObject(_bodyText(response)), username: username);
    }, name: 'XiangqiEditableProfileProvider');

/// The country choices the edit form offers, read once for the whole session.
final xiangqiCountryOptionsProvider = FutureProvider<List<XiangqiCountryOption>>((Ref ref) async {
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw StateError('The device is offline; not asking xiangqi.com for the country list.');
  }
  final uri = xiangqiUri('users/countries');
  final response = await ref.read(xiangqiClientProvider).get(uri);
  if (response.statusCode >= 400) {
    throw ServerException(response.statusCode, 'xiangqi.com country lookup failed.', uri, null);
  }
  final json = jsonDecode(utf8.decode(response.bodyBytes));
  if (json is! List) {
    throw const FormatException('xiangqi.com answered the country list with something else.');
  }
  final options = <XiangqiCountryOption>[];
  for (final row in json) {
    if (row is! Map<String, dynamic>) continue;
    final id = _int(row['value']) ?? _int(row['id']);
    final code = _string(row['code']);
    final name = _string(row['name']);
    if (id == null || code == null || name == null) continue;
    options.add(XiangqiCountryOption(id: id, code: code, name: name));
  }
  options.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return List.unmodifiable(options);
}, name: 'XiangqiCountryOptionsProvider');

/// Reads an account payload into the edit form's shape.
XiangqiEditableProfile xiangqiEditableProfileFromJson(
  Map<String, dynamic> json, {
  required String username,
}) {
  final country = json['country'];
  final countryMap = country is Map<String, dynamic> ? country : null;
  return XiangqiEditableProfile(
    username: _string(json['username']) ?? username,
    email: _string(json['email']) ?? '',
    bio: json['bio'] is String ? json['bio'] as String : '',
    countryId: _int(countryMap?['id']),
    countryCode: _string(countryMap?['code']),
    countryName: _string(countryMap?['name']),
    profileImage: _string(json['profile_image']),
  );
}

/// Saves the editable fields of [username] and returns the account the server answered with.
///
/// Measured against the live endpoint on 2026-10-17: `PUT /api/users/account/<username>` accepts
/// `{country, bio, username, password}` and answers with the updated account object. The website's
/// own edit form sends the same fields, plus a locale it uses for its own UI; this app leaves the
/// website's locale alone and sends only what it is changing. `password` may be empty when the
/// username is unchanged; the server accepts that.
Future<XiangqiEditableProfile> updateXiangqiProfile(
  XiangqiClient client, {
  required String username,
  required String newUsername,
  required String bio,
  required int? countryId,
  required String password,
}) async {
  final uri = xiangqiUri('users/account/$username');
  final response = await client.put(
    uri,
    headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: jsonEncode({
      'username': newUsername,
      'bio': bio,
      'password': password,
      'country': ?countryId,
    }),
  );
  if (response.statusCode >= 400) {
    throw XiangqiProfileUpdateException(_profileUpdateMessage(response));
  }
  return xiangqiEditableProfileFromJson(_decodeObject(_bodyText(response)), username: newUsername);
}

/// The server's own sentence for a refused profile update, or a neutral fallback.
String _profileUpdateMessage(Response response) {
  try {
    final json = _decodeObject(_bodyText(response));
    final message = json['message'];
    if (message is String && message.isNotEmpty) return message;
    final errors = json['errors'];
    if (errors is Map<String, dynamic>) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty && value.first is String) {
          return value.first as String;
        }
        if (value is String && value.isNotEmpty) return value;
      }
    }
  } catch (_) {
    // The status is still the failure; an unreadable body only loses its explanation.
  }
  return 'xiangqi.com could not save the profile (${response.statusCode}).';
}

/// The instant `last_online` names, or null if it cannot be read.
///
/// The wire value is neither a JSON number nor an ISO-8601 string. It is a Python `bytes` literal
/// wrapped around a Unix epoch in **seconds**, and it arrives as the JSON string `"b'1600000000'"`
/// — the exact form measured on `GET /api/users/account/<username>` on 2026-08-30, and the same
/// shape the account payload carries for every account seen. `int.parse` and `DateTime.parse` both
/// reject it, so the `b'` prefix and the closing `'` are stripped first and the remainder is read
/// as an integer.
///
/// Not a field of [XiangqiUserProfile]: the row this app draws says whether the account is online
/// *now*, which is `is_online`, and nothing shows a last-seen time. It is parsed here anyway, and
/// tested, so that whoever does want it is not the one who finds out what shape it is.
///
/// The result is UTC because a Unix epoch is absolute — that says nothing about which zone the
/// server keeps its own clock in, which is not established.
DateTime? xiangqiLastOnlineFromJson(Object? value) {
  if (value is! String) return null;
  var text = value;
  if (text.startsWith("b'") && text.endsWith("'")) {
    text = text.substring(2, text.length - 1);
  }
  final seconds = int.tryParse(text);
  if (seconds == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// The response body as text, decoded as UTF-8 whatever the headers claim.
///
/// `Response.body` falls back to Latin-1 when the server sends no charset, which would mangle a
/// non-ASCII username; the bytes are what is actually on the wire.
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

/// [value] as a non-empty string, or null.
String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;

/// [value] as an integer, or null. A JSON number may arrive as a double, so both are accepted.
int? _int(Object? value) => value is num ? value.toInt() : null;

/// The instant [value], an RFC-1123 HTTP-date, names — or null if it will not parse.
///
/// `DateTime.parse` cannot read this form; `HttpDate.parse` is the one that can, and it returns a
/// UTC instant, which is what the trailing `GMT` on the wire says it is.
DateTime? _httpDate(String value) {
  try {
    return HttpDate.parse(value);
  } catch (_) {
    return null;
  }
}
