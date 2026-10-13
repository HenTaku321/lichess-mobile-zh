import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show BaseRequest, Client, Request, Response, StreamedResponse;
import 'package:lichess_mobile/src/db/secure_storage.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart'
    show ServerException, httpClientFactoryProvider;
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';
import 'package:logging/logging.dart';

final _logger = Logger('XiangqiHttpClient');

/// The shortest gap between two requests to xiangqi.com.
///
/// One and a half seconds, and it is not a courtesy: the server **silently drops** requests that
/// arrive closer together. There is no error frame and no response — the request simply never
/// happens, which is the hardest possible kind of failure to see from the outside. Measured against
/// the live host, 0 ms spacing lost about a fifth of a burst; 1000 ms spacing lost none, and 1500 ms
/// is the round number above that.
///
/// This lives here, in the client, rather than in the callers: every request to this host goes
/// through it, so there is no call site left that can forget.
const kXiangqiMinRequestSpacing = Duration(milliseconds: 1500);

/// The User-Agent sent to xiangqi.com.
///
/// Deliberately fixed and identity-free. The lichess build's own user agent names the signed-in
/// lichess user (and its socket carries a random identifier); neither belongs on a request to a
/// third party, so this one names the app and stops there.
const kXiangqiUserAgent = 'Lichess Mobile';

/// The secure-storage key the xiangqi.com session is kept under.
///
/// Mirrors `auth_storage.dart`'s `'<host>.userSession'` shape, with the host spelled out rather
/// than taken from `kLichessHost`: this is a different account on a different service, and the two
/// sessions must never be able to overwrite each other.
const kXiangqiAuthStorageKey = 'xiangqi.com.userSession';

/// The message shown when the session is gone for good and the user has to sign in again.
const kXiangqiSessionExpiredMessage = 'Your xiangqi.com session has expired. Please sign in again.';

/// Stores the xiangqi.com session, in the same secure storage the lichess session uses.
///
/// A class rather than loose functions because it is the one place the on-disk shape of the session
/// is written down, so tests replace it wholesale ([xiangqiAuthStorageProvider] is a plain
/// provider, not a network call).
///
/// The JSON is spelled out by hand rather than taken from [XiangqiSession]: that class is `freezed`
/// without a `fromJson` factory, so it generates no encoder, and the model file is not this file's
/// to change.
class const XiangqiAuthStorage() {
  Future<XiangqiSession?> read() async {
    final string = await SecureStorage.instance.read(key: kXiangqiAuthStorageKey);
    if (string == null) return null;
    final Object? json;
    try {
      json = jsonDecode(string);
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    final userId = json['userId'];
    final name = json['name'];
    final accessToken = json['accessToken'];
    final isGuest = json['isGuest'];
    if (userId is! String || name is! String || accessToken is! String || isGuest is! bool) {
      return null;
    }
    final refreshToken = json['refreshToken'];
    return XiangqiSession(
      userId: userId,
      name: name,
      accessToken: accessToken,
      refreshToken: refreshToken is String ? refreshToken : null,
      isGuest: isGuest,
    );
  }

  Future<void> write(XiangqiSession session) {
    return SecureStorage.instance.write(
      key: kXiangqiAuthStorageKey,
      value: jsonEncode({
        'userId': session.userId,
        'name': session.name,
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
        'isGuest': session.isGuest,
      }),
    );
  }

  Future<void> delete() => SecureStorage.instance.delete(key: kXiangqiAuthStorageKey);
}

/// A provider for [XiangqiAuthStorage].
final xiangqiAuthStorageProvider = Provider<XiangqiAuthStorage>((Ref ref) {
  return const XiangqiAuthStorage();
}, name: 'XiangqiAuthStorageProvider');

/// The http client configured to make requests to the xiangqi.com API.
///
/// Only one instance of this client is created and kept alive for the whole app. It is deliberately
/// **not** a `LichessClient` and not built on one: that client signs its bearer token with an HMAC
/// shared with lichess (`http.dart:414`) and routes any bare path to the lichess host
/// (`http.dart:532`) — xiangqi.com has neither, and a request sent there must carry neither.
final xiangqiClientProvider = Provider<XiangqiClient>((Ref ref) {
  final client = XiangqiClient(
    inner: ref.read(httpClientFactoryProvider)(),
    storage: ref.read(xiangqiAuthStorageProvider),
    uiEventBus: ref.read(uiEventBusProvider),
  );
  ref.onDispose(client.close);
  return client;
}, name: 'XiangqiHttpClientProvider');

/// xiangqi.com HTTP client.
///
/// What it does, over the raw [Client] it wraps:
/// * routes a request that carries only a path to [xiangqiUri];
/// * sets `Authorization: Bearer <the raw JWT>` from the stored [XiangqiSession];
/// * sets an identity-free [kXiangqiUserAgent];
/// * spaces requests to the host by at least [kXiangqiMinRequestSpacing];
/// * on a 401, refreshes the access token once and retries the request once, and if that also
///   401s, clears the session and tells the user, once per dead token.
class XiangqiClient({
  required final Client _inner,
  required final XiangqiAuthStorage _storage,
  required final UiEventBus _uiEventBus,
}) implements Client {
  /// How long a request may wait for the response headers.
  static const defaultRequestTimeout = Duration(seconds: 30);

  /// How long between two requests to this host. See [kXiangqiMinRequestSpacing].
  final Duration minRequestSpacing = kXiangqiMinRequestSpacing;

  late final _RequestThrottle _throttle = _RequestThrottle(minRequestSpacing);

  /// The in-flight token refresh, or null when none is running.
  ///
  /// Two requests that 401 at the same moment share this: the second waits on the first's future
  /// instead of firing a refresh of its own.
  Future<bool>? _refreshInFlight;

  /// The access token whose session has already been cleared.
  ///
  /// A second 401 on the same token does nothing: it is the same dead session, and the user has
  /// been told already. A later sign-in hands out a new token, which is a new value here.
  String? _clearedToken;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    // A Request is snapshotted before it is sent, because the 401 retry needs a second, unsent copy
    // of it and a BaseRequest can only be finalised once. A streamed body cannot be replayed and is
    // simply not retried.
    final replay = request is Request
        ? _ReplayData(request.method, request.url, Map.of(request.headers), request.bodyBytes)
        : null;

    await _throttle.acquire();
    _applyHeaders(request, await _storage.read());

    var response = await _inner.send(request).timeout(defaultRequestTimeout);

    if (response.statusCode != 401 || replay == null) return response;

    final refreshed = await _refresh();
    if (!refreshed) {
      await _clearSessionOnce();
      return response;
    }

    // The 401 body is of no use now that it is about to be replaced; draining it lets the
    // connection go back to the pool.
    await response.stream.drain<void>().catchError((Object _) {});

    final retry = replay.build();
    await _throttle.acquire();
    _applyHeaders(retry, await _storage.read());
    response = await _inner.send(retry).timeout(defaultRequestTimeout);

    if (response.statusCode == 401) {
      await _clearSessionOnce();
    }
    return response;
  }

  /// Puts the identity headers on [request], leaving the caller's own alone.
  ///
  /// The bearer is only set when one is stored and the caller has not set one itself, the way
  /// `LichessClient` treats it: a request that must go out unsigned (the login calls) is one the
  /// caller has already decided about. The user agent is always ours.
  void _applyHeaders(BaseRequest request, XiangqiSession? session) {
    if (session != null && !request.headers.containsKey('Authorization')) {
      request.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    request.headers['User-Agent'] = kXiangqiUserAgent;
  }

  /// Refreshes the access token, at most one refresh at a time.
  Future<bool> _refresh() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    late final Future<bool> future;
    future = _doRefresh().whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    _refreshInFlight = future;
    return future;
  }

  /// Asks for a new access token, keeping the refresh token (the server does not rotate it).
  Future<bool> _doRefresh() async {
    try {
      final session = await _storage.read();
      final refreshToken = session?.refreshToken;
      if (session == null || refreshToken == null || refreshToken.isEmpty) return false;

      await _throttle.acquire();
      final request = Request('POST', xiangqiUri('users/jwt/refresh'));
      request.headers['Authorization'] = 'Bearer $refreshToken';
      request.headers['User-Agent'] = kXiangqiUserAgent;
      request.headers['Accept'] = 'application/json';

      final response = await _inner.send(request).timeout(defaultRequestTimeout);
      if (response.statusCode != 200) {
        _logger.warning('xiangqi.com token refresh answered ${response.statusCode}.');
        return false;
      }
      final body = await response.stream.toBytes();
      final json = jsonDecode(utf8.decode(body));
      if (json is! Map<String, dynamic>) return false;
      final accessToken = json['jwt'] ?? json['access_token'] ?? json['accessToken'];
      if (accessToken is! String || accessToken.isEmpty) return false;

      // The refresh token is not rotated, so only the access token changes.
      await _storage.write(session.copyWith(accessToken: accessToken));
      return true;
    } catch (e, st) {
      _logger.warning('xiangqi.com token refresh failed.', e, st);
      return false;
    }
  }

  /// Clears the session and tells the user, once per dead token.
  Future<void> _clearSessionOnce() async {
    final session = await _storage.read();
    final token = session?.accessToken;
    if (token == null || token == _clearedToken) return;
    _clearedToken = token;
    await _storage.delete();
    _uiEventBus.emit(const ShowErrorEvent(kXiangqiSessionExpiredMessage));
    _logger.warning('xiangqi.com session cleared after a second 401.');
  }

  @override
  void close() {
    _inner.close();
  }

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('HEAD', url, headers);

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('GET', url, headers);

  @override
  Future<Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('POST', url, headers, body, encoding);

  @override
  Future<Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('PUT', url, headers, body, encoding);

  @override
  Future<Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('PATCH', url, headers, body, encoding);

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('DELETE', url, headers, body, encoding);

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.bodyBytes;
  }

  /// Sends a non-streaming [Request] and returns a non-streaming [Response].
  ///
  /// A [url] with no host is routed to [xiangqiUri]; one that carries a host is used as it stands.
  Future<Response> _sendUnstreamed(
    String method,
    Uri url,
    Map<String, String>? headers, [
    Object? body,
    Encoding? encoding,
  ]) {
    final request = Request(
      method,
      url.host.isNotEmpty ? url : xiangqiUri(url.path, url.hasQuery ? url.queryParameters : null),
    );

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      } else {
        throw ArgumentError('Invalid request body "$body".');
      }
    }

    return send(request).then(Response.fromStream);
  }
}

/// A snapshot of the parts of a sent [Request] needed to build a second, unsent copy of it.
///
/// The identity headers are deliberately not part of it: [_applyHeaders] puts the fresh ones back
/// from the refreshed session.
class _ReplayData(
  final String method,
  final Uri url,
  final Map<String, String> headers,
  final Uint8List bodyBytes,
) {
  Request build() {
    final request = Request(method, url);
    request.headers.addAll(headers);
    request.bodyBytes = bodyBytes;
    return request;
  }
}

void _checkResponseSuccess(Uri url, Response response) {
  if (response.statusCode < 400) return;
  var message = 'Request to $url failed with status ${response.statusCode}';
  Map<String, dynamic>? jsonError;
  if (response.body.isNotEmpty) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        jsonError = json;
        if (json.containsKey('error')) {
          message = '$message: ${json['error']}';
        }
      }
    } catch (_) {
      message = '$message: ${response.body}';
    }
  }
  throw ServerException(response.statusCode, message, url, jsonError);
}

/// Keeps requests to one host at least [minSpacing] apart and lets only one run at a time.
///
/// Each [acquire] waits its turn — the previous acquisition has to have finished — and then, if the
/// previous request *started* less than [minSpacing] ago, waits out the remainder. Starting times,
/// not finishing ones: a slow request does not push the next one further away than the spacing
/// already asked for, but no burst can begin inside the window either.
///
/// The clock is `package:clock`'s, so a test can drive it with `FakeAsync` and never sleep for real.
class _RequestThrottle(final Duration minSpacing) {
  DateTime? _lastStart;
  Future<void> _turn = Future<void>.value();

  Future<void> acquire() {
    final previous = _turn;
    final completer = Completer<void>();
    _turn = completer.future;
    return _wait(previous, completer);
  }

  Future<void> _wait(Future<void> previous, Completer<void> completer) async {
    await previous;
    final last = _lastStart;
    if (last != null) {
      final wait = minSpacing - clock.now().difference(last);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastStart = clock.now();
    completer.complete();
  }
}
