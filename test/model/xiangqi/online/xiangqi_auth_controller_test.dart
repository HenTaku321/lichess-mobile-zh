import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';

import '../../../network/fake_http_client_factory.dart';
import '../../../test_container.dart';
import '../../../test_helpers.dart';

/// A session store that never touches the disk.
///
/// [xiangqiAuthStorageProvider] is a plain provider — no `keepAlive`, no network — so overriding it
/// with this is what AGENTS.md allows, and it keeps the real secure storage out of the test.
class FakeXiangqiAuthStorage([var XiangqiSession? session]) implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession value) async => session = value;

  @override
  Future<void> delete() async => session = null;
}

/// A JWT carrying [claims] as its payload.
///
/// The signature is three characters of junk and is never checked — the controller reads the `sub`
/// without verifying it, which is the whole point: this token is our own, not a trust boundary.
String jwt(Map<String, Object?> claims) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(const {'alg': 'none'})}.${segment(claims)}.sig';
}

/// A container with the xiangqi client stubbed at the HTTP layer and the session store in memory.
Future<ProviderContainer> makeControllerContainer({
  required MockClient client,
  required FakeXiangqiAuthStorage storage,
}) {
  return makeContainer(
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => client);
      }),
      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith((ref) => storage),
    },
  );
}

/// A client answering `POST /api/users/signin` with [body] and [status], and nothing else.
MockClient signInClient(String body, {int status = 200, void Function(http.Request)? onRequest}) {
  return MockClient((request) {
    onRequest?.call(request);
    if (request.method == 'POST' && request.url.path == '/api/users/signin') {
      return mockResponse(body, status);
    }
    return mockResponse('', 404);
  });
}

/// The access and refresh tokens a proxy server would recognise, in a real-looking JWT.
///
/// The `sub` is a stand-in account id; what the tests read is that it comes back as a string.
String get _accessToken => jwt(const {'sub': 100001, 'type': 'access'});

void main() {
  group('signInWithPassword', () {
    test('posts the email and password and stores the session', () async {
      final storage = FakeXiangqiAuthStorage();
      http.Request? sent;
      final container = await makeControllerContainer(
        storage: storage,
        client: signInClient(
          jsonEncode({
            'access_token': _accessToken,
            'refresh_token': 'the-refresh-token',
            'user': {'username': 'alice'},
          }),
          onRequest: (request) => sent = request,
        ),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();

      await container
          .read(xiangqiAuthControllerProvider.notifier)
          .signInWithPassword(email: 'alice@example.com', password: 'hunter2');

      expect(sent!.method, 'POST');
      expect(sent!.url.path, '/api/users/signin');
      expect(jsonDecode(sent!.body), {'email': 'alice@example.com', 'password': 'hunter2'});

      final session = container.read(xiangqiAuthControllerProvider);
      expect(session, isNotNull);
      expect(session!.accessToken, _accessToken);
      expect(session.refreshToken, 'the-refresh-token');
      expect(session.userId, '100001');
      expect(session.name, 'alice');
      expect(session.isGuest, isFalse);
      // The session is on disk, not only in memory.
      expect(storage.session, session);
    });

    // The response field names are the candidate set read out of the shipped bundle and have not
    // been measured against the server (`auth.rs:3-6`); each candidate must be accepted on its own.
    for (final field in const ['access_token', 'jwt', 'token', 'accessToken']) {
      test('reads the access token from "$field"', () async {
        final container = await makeControllerContainer(
          storage: FakeXiangqiAuthStorage(),
          client: signInClient(jsonEncode({field: _accessToken})),
        );
        container.listen(xiangqiAuthControllerProvider, (_, _) {});
        await container.pump();

        await container
            .read(xiangqiAuthControllerProvider.notifier)
            .signInWithPassword(email: 'a@b.c', password: 'pw');

        expect(container.read(xiangqiAuthControllerProvider)?.accessToken, _accessToken);
      });
    }

    for (final field in const ['refresh_token', 'refresh', 'refreshToken']) {
      test('reads the refresh token from "$field"', () async {
        final container = await makeControllerContainer(
          storage: FakeXiangqiAuthStorage(),
          client: signInClient(
            jsonEncode({'access_token': _accessToken, field: 'the-refresh-token'}),
          ),
        );
        container.listen(xiangqiAuthControllerProvider, (_, _) {});
        await container.pump();

        await container
            .read(xiangqiAuthControllerProvider.notifier)
            .signInWithPassword(email: 'a@b.c', password: 'pw');

        expect(container.read(xiangqiAuthControllerProvider)?.refreshToken, 'the-refresh-token');
      });
    }

    test('falls back to the user id for the name when the response has no username', () async {
      final container = await makeControllerContainer(
        storage: FakeXiangqiAuthStorage(),
        client: signInClient(jsonEncode({'access_token': _accessToken})),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();

      await container
          .read(xiangqiAuthControllerProvider.notifier)
          .signInWithPassword(email: 'a@b.c', password: 'pw');

      expect(container.read(xiangqiAuthControllerProvider)?.name, '100001');
    });

    for (final status in const [401, 400]) {
      test('throws XiangqiInvalidCredentialsException on HTTP $status', () async {
        final storage = FakeXiangqiAuthStorage();
        final container = await makeControllerContainer(
          storage: storage,
          client: signInClient('', status: status),
        );
        container.listen(xiangqiAuthControllerProvider, (_, _) {});
        await container.pump();

        await expectLater(
          container
              .read(xiangqiAuthControllerProvider.notifier)
              .signInWithPassword(email: 'a@b.c', password: 'wrong'),
          throwsA(isA<XiangqiInvalidCredentialsException>()),
        );
        expect(container.read(xiangqiAuthControllerProvider), isNull);
        expect(storage.session, isNull);
      });
    }

    test('a 500 is not reported as wrong credentials', () async {
      final container = await makeControllerContainer(
        storage: FakeXiangqiAuthStorage(),
        client: signInClient('boom', status: 500),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();

      await expectLater(
        container
            .read(xiangqiAuthControllerProvider.notifier)
            .signInWithPassword(email: 'a@b.c', password: 'pw'),
        throwsA(isA<ServerException>()),
      );
      expect(container.read(xiangqiAuthControllerProvider), isNull);
    });
  });

  group('signInAsGuest', () {
    MockClient guestClient({void Function(http.Request)? onRequest}) {
      return MockClient((request) {
        onRequest?.call(request);
        if (request.url.path == '/api/users/guest_jwt') {
          return mockResponse(
            jsonEncode({
              'jwt': jwt(const {'sub': 'guest7zuq8'}),
            }),
            200,
          );
        }
        return mockResponse('', 404);
      });
    }

    test('posts an empty body and reads the user id from the token subject', () async {
      final storage = FakeXiangqiAuthStorage();
      http.Request? sent;
      final container = await makeControllerContainer(
        storage: storage,
        client: guestClient(onRequest: (request) => sent = request),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();

      await container.read(xiangqiAuthControllerProvider.notifier).signInAsGuest();

      expect(sent!.method, 'POST');
      expect(sent!.url.path, '/api/users/guest_jwt');
      final session = container.read(xiangqiAuthControllerProvider);
      expect(session, isNotNull);
      expect(session!.isGuest, isTrue);
      expect(session.userId, 'guest7zuq8');
      expect(session.name, 'guest7zuq8');
      expect(session.refreshToken, isNull);
      expect(storage.session, session);
    });

    test('a guest holds a session but is not logged in', () async {
      final container = await makeControllerContainer(
        storage: FakeXiangqiAuthStorage(),
        client: guestClient(),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();

      await container.read(xiangqiAuthControllerProvider.notifier).signInAsGuest();

      expect(container.read(hasXiangqiSessionProvider), isTrue);
      expect(container.read(isXiangqiLoggedInProvider), isFalse);
    });
  });

  group('ensureGuestSession', () {
    test('creates a guest once and never a second time', () async {
      var requests = 0;
      final container = await makeControllerContainer(
        storage: FakeXiangqiAuthStorage(),
        client: MockClient((request) {
          requests++;
          if (request.url.path == '/api/users/guest_jwt') {
            return mockResponse(
              jsonEncode({
                'jwt': jwt(const {'sub': 'guest00001'}),
              }),
              200,
            );
          }
          return mockResponse('', 404);
        }),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();
      final notifier = container.read(xiangqiAuthControllerProvider.notifier);

      await notifier.ensureGuestSession();
      expect(requests, 1, reason: 'no session yet, so a guest is made');

      await notifier.ensureGuestSession();
      expect(requests, 1, reason: 'a session already exists, so nothing is requested');
    });
  });

  group('session lifecycle', () {
    test('restores a stored session after the initial null', () async {
      final stored = XiangqiSession(
        userId: '42',
        name: 'alice',
        accessToken: jwt(const {'sub': 42}),
        isGuest: false,
      );
      final container = await makeControllerContainer(
        storage: FakeXiangqiAuthStorage(stored),
        client: MockClient((request) => mockResponse('', 200)),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});

      // build() answered before storage did.
      expect(container.read(xiangqiAuthControllerProvider), isNull);

      await container.pump();

      expect(container.read(xiangqiAuthControllerProvider), stored);
      expect(container.read(isXiangqiLoggedInProvider), isTrue);
    });

    test('signOut drops the session from storage and from the state', () async {
      final container = await makeControllerContainer(
        storage: FakeXiangqiAuthStorage(),
        client: signInClient(
          jsonEncode({
            'access_token': _accessToken,
            'user': {'username': 'alice'},
          }),
        ),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();
      final notifier = container.read(xiangqiAuthControllerProvider.notifier);
      await notifier.signInWithPassword(email: 'a@b.c', password: 'pw');
      expect(container.read(xiangqiAuthControllerProvider), isNotNull);

      await notifier.signOut();

      expect(container.read(xiangqiAuthControllerProvider), isNull);
      expect(container.read(hasXiangqiSessionProvider), isFalse);
    });

    test('checkToken reflects a session that the client cleared behind the controller', () async {
      final storage = FakeXiangqiAuthStorage(
        XiangqiSession(
          userId: '42',
          name: 'alice',
          accessToken: jwt(const {'sub': 42}),
          isGuest: false,
        ),
      );
      final container = await makeControllerContainer(
        storage: storage,
        client: MockClient((request) => mockResponse('', 200)),
      );
      container.listen(xiangqiAuthControllerProvider, (_, _) {});
      await container.pump();
      expect(container.read(xiangqiAuthControllerProvider), isNotNull);

      // This is what XiangqiClient does on a second 401: it clears the store by itself.
      await storage.delete();
      expect(container.read(xiangqiAuthControllerProvider), isNotNull);

      await container.read(xiangqiAuthControllerProvider.notifier).checkToken();

      expect(container.read(xiangqiAuthControllerProvider), isNull);
    });
  });
}
