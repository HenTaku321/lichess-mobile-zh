import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Client, Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// Thrown when xiangqi.com refuses an email/password pair.
///
/// Only a wrong pair is this: a 500, a dropped connection, or a body that is not JSON anymore is a
/// different failure and must not be reported to the user as "wrong email or password".
class const XiangqiInvalidCredentialsException() implements Exception {
  @override
  String toString() => 'Wrong xiangqi.com email or password.';
}

/// A provider for [XiangqiAuthController].
final xiangqiAuthControllerProvider =
    NotifierProvider.autoDispose<XiangqiAuthController, XiangqiSession?>(
      XiangqiAuthController.new,
      name: 'XiangqiAuthControllerProvider',
    );

/// Whether a real xiangqi.com account — not a guest — is signed in.
final isXiangqiLoggedInProvider = Provider.autoDispose<bool>((Ref ref) {
  return ref.watch(
    xiangqiAuthControllerProvider.select((session) => session != null && !session.isGuest),
  );
}, name: 'IsXiangqiLoggedInProvider');

/// Whether any xiangqi.com session is held, guest or not.
final hasXiangqiSessionProvider = Provider.autoDispose<bool>((Ref ref) {
  return ref.watch(xiangqiAuthControllerProvider.select((session) => session != null));
}, name: 'HasXiangqiSessionProvider');

/// Holds the signed-in xiangqi.com session: the account, or the guest token, or none.
///
/// ## The state is synchronous, and "not known yet" is the same as "none"
///
/// [build] returns a plain [XiangqiSession] — not an `AsyncValue` — because the online xiangqi
/// screens of the next wave have to read a token string *synchronously*, off the same `ref.watch`
/// that draws the UI. [XiangqiAuthStorage.read] is asynchronous, though, so [build] answers `null`
/// at once and [_restore] fills the state in when storage comes back. On a cold start that makes
/// "the app does not know yet" and "there is definitely no session" the very same state.
///
/// Merging the two is honest, not lazy: the whole app treats "no session" as "make a guest session
/// on demand, the first time online xiangqi data is needed" ([ensureGuestSession]), so the two
/// cases are handled the same way anyway — the only difference is a few milliseconds of lag before
/// a stored session appears.
class XiangqiAuthController() extends Notifier<XiangqiSession?> {
  Client get _client => ref.read(xiangqiClientProvider);

  @override
  XiangqiSession? build() {
    // Not awaited: [build] has to return synchronously, and the session is only ever read after
    // this microtask-sized window. See the class doc.
    unawaited(_restore());
    return null;
  }

  /// Reads the stored session and, if there is one, adopts it.
  Future<void> _restore() async {
    final session = await ref.read(xiangqiAuthStorageProvider).read();
    if (!ref.mounted) return;
    if (session != null) state = session;
  }

  /// Signs in to xiangqi.com with an email and password.
  ///
  /// Throws a [XiangqiInvalidCredentialsException] when the pair is wrong, a [ServerException] on
  /// any other HTTP failure, and lets a network error propagate.
  Future<void> signInWithPassword({required String email, required String password}) async {
    final response = await _client.post(
      xiangqiUri('users/signin'),
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    // A wrong pair is a 401; xiangqi.com also answers 400 for the same thing on some shapes. Both
    // mean the credentials, and nothing else does.
    if (response.statusCode == 401 || response.statusCode == 400) {
      throw const XiangqiInvalidCredentialsException();
    }
    if (response.statusCode >= 400) {
      throw ServerException(
        response.statusCode,
        'xiangqi.com sign-in failed.',
        xiangqiUri('users/signin'),
        null,
      );
    }

    final json = _decodeObject(_bodyText(response));

    // The field names below are the candidate set read out of the shipped xiangqi.com JS bundle.
    // They have **not** been measured against the live server — `auth.rs:3-6` says as much — so the
    // first non-empty one wins rather than any single name being trusted on its own. The order is
    // the same one `auth.rs:139-142` uses.
    final accessToken = _pick(json, const ['access_token', 'jwt', 'token', 'accessToken']);
    if (accessToken == null) {
      throw const FormatException('The xiangqi.com sign-in response carried no access token.');
    }
    final refreshToken = _pick(json, const ['refresh_token', 'refresh', 'refreshToken']);

    final userId = _userIdFromToken(accessToken);
    if (userId == null) {
      throw const FormatException('The xiangqi.com access token carries no subject.');
    }

    await _store(
      XiangqiSession(
        userId: userId,
        name: _username(json) ?? userId,
        accessToken: accessToken,
        refreshToken: refreshToken,
        isGuest: false,
      ),
    );
  }

  /// Takes a guest token from xiangqi.com, with no account behind it.
  ///
  /// `POST /api/users/guest_jwt` with an empty body answers `{"jwt": "..."}` — the one shape in
  /// this file that was measured live (`auth.rs:428-430`). The guest's `sub` looks like `guest7zuq8`.
  ///
  /// Not called from any screen yet: see [ensureGuestSession].
  Future<void> signInAsGuest() async {
    final response = await _client.post(
      xiangqiUri('users/guest_jwt'),
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: '{}',
    );

    if (response.statusCode >= 400) {
      throw ServerException(
        response.statusCode,
        'xiangqi.com guest sign-in failed.',
        xiangqiUri('users/guest_jwt'),
        null,
      );
    }

    final json = _decodeObject(_bodyText(response));
    // `jwt` is the measured name; the other two are the same best-effort candidates the sign-in
    // response is read with.
    final token = _pick(json, const ['jwt', 'access_token', 'token']);
    if (token == null) {
      throw const FormatException('The xiangqi.com guest response carried no token.');
    }

    final userId = _userIdFromToken(token);
    if (userId == null) {
      throw const FormatException('The xiangqi.com guest token carries no subject.');
    }

    await _store(XiangqiSession(userId: userId, name: userId, accessToken: token, isGuest: true));
  }

  /// Makes sure a session exists, creating a guest one when there is none.
  ///
  /// **Deliberately called from nowhere in this wave.** The sign-in/account screens do not touch
  /// it: silently creating an anonymous xiangqi.com account the moment a user opens the account
  /// page would be an outward-facing action nobody asked for. The caller is the merged
  /// online-xiangqi screen of the next wave, which calls this when online data is first needed.
  Future<void> ensureGuestSession() async {
    if (state != null) return;
    await signInAsGuest();
  }

  /// Signs out of xiangqi.com, dropping the session from storage and from the UI.
  Future<void> signOut() async {
    await ref.read(xiangqiAuthStorageProvider).delete();
    if (!ref.mounted) return;
    state = null;
  }

  /// Re-reads the stored session and makes [state] agree with it again.
  ///
  /// There is no measured xiangqi.com endpoint that tests a token, and this repo does not invent
  /// protocol, so this does not ask the server. What it is for is the reverse direction:
  /// [XiangqiClient] clears the stored session by itself when a call 401s twice, without telling
  /// this controller, so the screen's "signed in" and the disk can drift apart. Re-reading the disk
  /// closes that gap — and, on an empty disk, correctly drops back to no session.
  Future<void> checkToken() async {
    final session = await ref.read(xiangqiAuthStorageProvider).read();
    if (!ref.mounted) return;
    state = session;
  }

  /// Writes [session] to storage, then adopts it as the state.
  Future<void> _store(XiangqiSession session) async {
    await ref.read(xiangqiAuthStorageProvider).write(session);
    if (!ref.mounted) return;
    state = session;
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

  /// The first non-empty string [json] holds under any of [keys], or null.
  static String? _pick(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  /// The username from the `user` object of a sign-in response, or null.
  static String? _username(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is Map<String, dynamic>) {
      final username = user['username'];
      if (username is String && username.isNotEmpty) return username;
    }
    return null;
  }
}

/// The `sub` of [token], as a string, or null if it cannot be read.
///
/// The payload segment is base64url-decoded and read without checking the signature: this is our
/// own token, handed to us over TLS, so it is not a trust boundary — the same call `auth.rs:307-333`
/// makes. The `sub` is a number for a real account (`484155`) and a string for a guest
/// (`guest7zuq8`), so both are accepted and normalised to a string.
String? _userIdFromToken(String token) {
  final segments = token.split('.');
  if (segments.length < 2) return null;
  final Object? payload;
  try {
    payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))));
  } catch (_) {
    return null;
  }
  if (payload is! Map<String, dynamic>) return null;
  final sub = payload['sub'];
  if (sub is String && sub.isNotEmpty) return sub;
  if (sub is num) return sub.toString();
  return null;
}
