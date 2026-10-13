// Tests for the xiangqi.com HTTP client: identity, path routing, the request throttle, and the
// one-refresh-at-a-time 401 dance.
//
// Every timing-sensitive case runs inside `fakeAsync` under `package:clock`'s fake clock, because
// the client spaces requests by 1.5 s and a test that actually slept for that would be a second and
// a half of nothing. The fake clock is what `_RequestThrottle` reads, so `async.elapse` moves both
// the timers and the timestamps together.

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/ui_events.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

import '../test_container.dart';
import 'fake_http_client_factory.dart';

/// A [XiangqiAuthStorage] that keeps the session in memory.
///
/// The real one writes to secure storage; nothing in these tests should touch a platform channel,
/// and [deleteCount] is the observable for "the session was cleared exactly once".
class FakeXiangqiAuthStorage([var XiangqiSession? session]) extends XiangqiAuthStorage {
  int deleteCount = 0;

  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession newSession) async {
    session = newSession;
  }

  @override
  Future<void> delete() async {
    session = null;
    deleteCount++;
  }
}

/// The session every 401 test starts from.
const signedInSession = XiangqiSession(
  userId: 'u-1',
  name: 'Tester',
  accessToken: 'access-old',
  refreshToken: 'refresh-1',
  isGuest: false,
);

/// A moment inside the fake clock's year, used only as the epoch of the timeline.
final testEpoch = DateTime(2026, 1, 1);

void main() {
  group('headers and routing', () {
    test('sends the fixed user agent and no bearer when nobody is signed in', () async {
      final seen = <http.Request>[];
      final client = XiangqiClient(
        inner: MockClient((request) async {
          seen.add(request);
          return http.Response('{}', 200);
        }),
        storage: FakeXiangqiAuthStorage(),
        uiEventBus: UiEventBus(),
      );

      await client.get(xiangqiUri('me'));

      expect(seen.single.headers['User-Agent'], kXiangqiUserAgent);
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test('sends the stored access token, raw, as a bearer', () async {
      final seen = <http.Request>[];
      final client = XiangqiClient(
        inner: MockClient((request) async {
          seen.add(request);
          return http.Response('{}', 200);
        }),
        storage: FakeXiangqiAuthStorage(signedInSession),
        uiEventBus: UiEventBus(),
      );

      await client.get(xiangqiUri('me'));

      // The lichess client signs its bearer with an HMAC shared with lichess; this one must not.
      expect(seen.single.headers['Authorization'], 'Bearer access-old');
    });

    test('leaves an authorization the caller set itself alone', () async {
      final seen = <http.Request>[];
      final client = XiangqiClient(
        inner: MockClient((request) async {
          seen.add(request);
          return http.Response('{}', 200);
        }),
        storage: FakeXiangqiAuthStorage(signedInSession),
        uiEventBus: UiEventBus(),
      );

      // The sign-in call is the case: it must go out unsigned even though a session is stored.
      await client.post(xiangqiUri('users/guest'), headers: {'Authorization': 'Bearer caller-set'});

      expect(seen.single.headers['Authorization'], 'Bearer caller-set');
    });

    test('routes a request that carries only a path to api.xiangqi.com', () async {
      final seen = <http.Request>[];
      final client = XiangqiClient(
        inner: MockClient((request) async {
          seen.add(request);
          return http.Response('{}', 200);
        }),
        storage: FakeXiangqiAuthStorage(),
        uiEventBus: UiEventBus(),
      );

      await client.get(Uri(path: 'games'));

      expect(seen.single.url.toString(), 'https://api.xiangqi.com/api/games');
    });

    test('leaves a request that already carries a host as it stands', () async {
      final seen = <http.Request>[];
      final client = XiangqiClient(
        inner: MockClient((request) async {
          seen.add(request);
          return http.Response('{}', 200);
        }),
        storage: FakeXiangqiAuthStorage(),
        uiEventBus: UiEventBus(),
      );

      await client.get(Uri.parse('https://elsewhere.example/thing'));

      expect(seen.single.url.toString(), 'https://elsewhere.example/thing');
    });

    test('read throws the shared ServerException with the body as jsonError', () async {
      final client = XiangqiClient(
        inner: MockClient((request) async => http.Response('{"error":"nope"}', 404)),
        storage: FakeXiangqiAuthStorage(),
        uiEventBus: UiEventBus(),
      );

      await expectLater(
        client.read(xiangqiUri('me')),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'statusCode', 404).having(
            (e) => e.jsonError,
            'jsonError',
            {'error': 'nope'},
          ),
        ),
      );
    });
  });

  group('request throttle', () {
    test('keeps two requests to the host at least 1.5 s apart', () {
      fakeAsync((async) {
        withClock(async.getClock(testEpoch), () {
          final startedAt = <DateTime>[];
          final client = XiangqiClient(
            inner: MockClient((request) async {
              startedAt.add(clock.now());
              return http.Response('{}', 200);
            }),
            storage: FakeXiangqiAuthStorage(),
            uiEventBus: UiEventBus(),
          );

          client.get(xiangqiUri('a')).ignore();
          client.get(xiangqiUri('b')).ignore();
          async.flushMicrotasks();

          // The first one goes out at once; the second must still be waiting.
          expect(startedAt, hasLength(1));

          async.elapse(const Duration(milliseconds: 1499));
          expect(startedAt, hasLength(1), reason: 'not yet a full spacing');

          async.elapse(const Duration(milliseconds: 1));
          async.flushMicrotasks();

          expect(startedAt, hasLength(2));
          expect(
            startedAt[1].difference(startedAt[0]),
            greaterThanOrEqualTo(kXiangqiMinRequestSpacing),
          );
        });
      });
    });

    test('serialises a burst rather than letting it overlap', () {
      fakeAsync((async) {
        withClock(async.getClock(testEpoch), () {
          final startOrder = <String>[];
          final client = XiangqiClient(
            inner: MockClient((request) async {
              startOrder.add(request.url.path);
              return http.Response('{}', 200);
            }),
            storage: FakeXiangqiAuthStorage(),
            uiEventBus: UiEventBus(),
          );

          for (final path in ['a', 'b', 'c']) {
            client.get(xiangqiUri(path)).ignore();
          }
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();

          expect(startOrder, ['/api/a', '/api/b', '/api/c']);
        });
      });
    });
  });

  group('401 handling', () {
    test('refreshes once and retries the original request', () {
      fakeAsync((async) {
        withClock(async.getClock(testEpoch), () {
          final requests = <String>[];
          final storage = FakeXiangqiAuthStorage(signedInSession);
          final client = XiangqiClient(
            inner: MockClient((request) async {
              requests.add(
                '${request.method} ${request.url.path} ${request.headers['Authorization']}',
              );
              if (request.url.path == '/api/users/jwt/refresh') {
                return http.Response(jsonEncode({'jwt': 'access-new'}), 200);
              }
              if (request.headers['Authorization'] == 'Bearer access-new') {
                return http.Response('{"ok":true}', 200);
              }
              return http.Response('', 401);
            }),
            storage: storage,
            uiEventBus: UiEventBus(),
          );

          http.Response? result;
          client.get(xiangqiUri('me')).then((response) => result = response);
          async.elapse(const Duration(seconds: 20));
          async.flushMicrotasks();

          expect(result?.statusCode, 200);
          expect(requests, [
            'GET /api/me Bearer access-old',
            // The refresh goes out with the refresh token, not the dead access token.
            'POST /api/users/jwt/refresh Bearer refresh-1',
            'GET /api/me Bearer access-new',
          ]);
          // The refresh token is not rotated, so only the access token moves.
          expect(storage.session?.accessToken, 'access-new');
          expect(storage.session?.refreshToken, 'refresh-1');
          expect(storage.deleteCount, 0);
        });
      });
    });

    test('accepts access_token and accessToken as well as jwt', () {
      for (final key in ['access_token', 'accessToken']) {
        fakeAsync((async) {
          withClock(async.getClock(testEpoch), () {
            final storage = FakeXiangqiAuthStorage(signedInSession);
            final client = XiangqiClient(
              inner: MockClient((request) async {
                if (request.url.path == '/api/users/jwt/refresh') {
                  return http.Response(jsonEncode({key: 'access-new'}), 200);
                }
                return request.headers['Authorization'] == 'Bearer access-new'
                    ? http.Response('{}', 200)
                    : http.Response('', 401);
              }),
              storage: storage,
              uiEventBus: UiEventBus(),
            );

            http.Response? result;
            client.get(xiangqiUri('me')).then((response) => result = response);
            async.elapse(const Duration(seconds: 20));
            async.flushMicrotasks();

            expect(result?.statusCode, 200, reason: 'token read from $key');
            expect(storage.session?.accessToken, 'access-new');
          });
        });
      }
    });

    test('clears the session and tells the user once when the retry is also a 401', () {
      fakeAsync((async) {
        withClock(async.getClock(testEpoch), () {
          final bus = UiEventBus();
          final events = <UiEvent>[];
          bus.stream.listen(events.add);
          final storage = FakeXiangqiAuthStorage(signedInSession);
          final client = XiangqiClient(
            inner: MockClient((request) async {
              if (request.url.path == '/api/users/jwt/refresh') {
                return http.Response(jsonEncode({'jwt': 'access-new'}), 200);
              }
              // Always a 401: the refreshed token is dead too.
              return http.Response('', 401);
            }),
            storage: storage,
            uiEventBus: bus,
          );

          http.Response? result;
          client.get(xiangqiUri('me')).then((response) => result = response);
          async.elapse(const Duration(seconds: 20));
          async.flushMicrotasks();

          expect(result?.statusCode, 401);
          expect(storage.session, isNull);
          expect(storage.deleteCount, 1);
          expect(events, hasLength(1));
          expect(events.single, isA<ShowErrorEvent>());
          expect((events.single as ShowErrorEvent).message, kXiangqiSessionExpiredMessage);

          // A later request — sign-in has not happened, so there is no session at all — must not
          // produce a second message for what is the same dead session.
          client.get(xiangqiUri('me')).then((response) => result = response);
          async.elapse(const Duration(seconds: 20));
          async.flushMicrotasks();

          expect(events, hasLength(1));
          expect(storage.deleteCount, 1);
        });
      });
    });

    test('clears the session without a refresh when there is no refresh token', () {
      fakeAsync((async) {
        withClock(async.getClock(testEpoch), () {
          final bus = UiEventBus();
          final events = <UiEvent>[];
          bus.stream.listen(events.add);
          final storage = FakeXiangqiAuthStorage(
            const XiangqiSession(
              userId: 'u-1',
              name: 'Tester',
              accessToken: 'access-old',
              isGuest: true,
            ),
          );
          var refreshAttempts = 0;
          final client = XiangqiClient(
            inner: MockClient((request) async {
              if (request.url.path == '/api/users/jwt/refresh') {
                refreshAttempts++;
                return http.Response(jsonEncode({'jwt': 'access-new'}), 200);
              }
              return http.Response('', 401);
            }),
            storage: storage,
            uiEventBus: bus,
          );

          client.get(xiangqiUri('me')).ignore();
          async.elapse(const Duration(seconds: 20));
          async.flushMicrotasks();

          expect(refreshAttempts, 0, reason: 'nothing to refresh with');
          expect(storage.session, isNull);
          expect(events, hasLength(1));
        });
      });
    });

    test('two requests that 401 together share one refresh', () {
      fakeAsync((async) {
        withClock(async.getClock(testEpoch), () {
          var refreshCount = 0;
          // Held open until the test releases it, so the first refresh is provably still in flight
          // when the second request deals with its own 401.
          final gate = Completer<void>();
          final storage = FakeXiangqiAuthStorage(signedInSession);
          final client = XiangqiClient(
            inner: MockClient((request) async {
              if (request.url.path == '/api/users/jwt/refresh') {
                refreshCount++;
                await gate.future;
                return http.Response(jsonEncode({'jwt': 'access-new'}), 200);
              }
              return request.headers['Authorization'] == 'Bearer access-new'
                  ? http.Response('{"ok":true}', 200)
                  : http.Response('', 401);
            }),
            storage: storage,
            uiEventBus: UiEventBus(),
          );

          client.get(xiangqiUri('a')).ignore();
          client.get(xiangqiUri('b')).ignore();
          // Well under the 30 s request timeout, which would otherwise fire on the held-open
          // refresh request and turn this into a different test.
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();

          expect(refreshCount, 1, reason: 'the second 401 waits on the first refresh');

          gate.complete();
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();

          expect(refreshCount, 1);
          expect(storage.session?.accessToken, 'access-new');
          expect(storage.deleteCount, 0);
        });
      });
    });

    test('a failed refresh clears the session and keeps the original 401 response', () {
      fakeAsync((async) {
        withClock(async.getClock(testEpoch), () {
          final storage = FakeXiangqiAuthStorage(signedInSession);
          final client = XiangqiClient(
            inner: MockClient((request) async {
              if (request.url.path == '/api/users/jwt/refresh') {
                return http.Response('{"error":"bad refresh token"}', 403);
              }
              return http.Response('{"error":"expired"}', 401);
            }),
            storage: storage,
            uiEventBus: UiEventBus(),
          );

          http.Response? result;
          client.get(xiangqiUri('me')).then((response) => result = response);
          async.elapse(const Duration(seconds: 20));
          async.flushMicrotasks();

          expect(result?.statusCode, 401);
          expect(result?.body, '{"error":"expired"}');
          expect(storage.session, isNull);
          expect(storage.deleteCount, 1);
        });
      });
    });
  });

  group('provider', () {
    test('takes its transport from httpClientFactoryProvider and is kept alive', () async {
      final seen = <Uri>[];
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(
              () => MockClient((request) async {
                seen.add(request.url);
                return http.Response('{}', 200);
              }),
            ),
          ),
        },
      );

      final client = container.read(xiangqiClientProvider);
      await client.get(xiangqiUri('me'));

      expect(seen.single, xiangqiUri('me'));
      expect(container.read(xiangqiClientProvider), same(client));
    });

    test('the stored session is what the request is authorised with', () async {
      final seen = <http.Request>[];
      final container = await makeContainer(
        overrides: {
          xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
            FakeXiangqiAuthStorage(signedInSession),
          ),
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(
              () => MockClient((request) async {
                seen.add(request);
                return http.Response('{}', 200);
              }),
            ),
          ),
        },
      );

      await container.read(xiangqiClientProvider).get(xiangqiUri('me'));

      expect(seen.single.headers['Authorization'], 'Bearer access-old');
    });
  });
}
