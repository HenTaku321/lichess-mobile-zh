// Tests for the xiangqi.com account lookup behind the account row's subtitle.
//
// The payload below is the measured one: it is copied from the 2026-08-30 capture of a real
// account (`主动私信.har`, the `GET /api/users/account/%E8%B5%B7%E5%8F%B8%E3%85%A4` entry), so the
// shapes are the server's. Two of them are the reason this file exists at all:
//
//   * `last_online` is not a JSON number. It is a Python `bytes` literal around a Unix epoch in
//     seconds, and it arrives as the string `"b'1788179925'"` — a value `int.parse` and
//     `DateTime.parse` both reject.
//   * `member_since` is an RFC-1123 HTTP-date, which `DateTime.parse` also rejects and `HttpDate`
//     reads.
//
// What is asserted is the reading of those shapes, not the numbers inside them: the fixtures below
// keep the measured field names and replace the values with round ones.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_user_repository.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../../network/fake_http_client_factory.dart';
import '../../../test_container.dart';

/// The username every fixture is asked for, and the one the capture's own payload carries.
const xiangqiAccountUsername = '起司ㅤ';

/// The measured payload, with its numbers rounded and its badges dropped.
///
/// Every field name is the wire's; the ratings are 500/600/700/1200 rather than the capture's own,
/// and the two dates are kept in the exact shapes the capture wrote them in.
Map<String, Object?> xiangqiAccountPayload({
  Object? lastOnline = "b'1788179925'",
  Object? memberSince = 'Tue, 11 Aug 2026 10:46:26 GMT',
  Object? country = const {'id': 226, 'code': 'US', 'name': 'United States'},
  Object? bulletRating = 500,
  Object? rapidRating = 600,
  Object? dailyRating = 700,
  Object? puzzleRating = 1200,
  Object? isOnline = true,
}) => {
  'id': 484155,
  'username': xiangqiAccountUsername,
  'prev_username': '棋手起司',
  'identity': xiangqiAccountUsername,
  'type': 1,
  'active': true,
  'country': country,
  'bio': '',
  'bullet_rating': bulletRating,
  'rapid_rating': rapidRating,
  'daily_rating': dailyRating,
  'puzzle_rating': puzzleRating,
  'profile_image': null,
  'is_online': isOnline,
  'last_online': lastOnline,
  'member_since': memberSince,
  'friend_count': 4,
  'flair': null,
  'email': 'mail@customdom.eu.org',
  'badges': const <Object?>[],
  'is_friend': false,
  'games_access': '2',
  'challenge_access': 1,
  'is_muted': false,
  'is_banned': false,
  'is_game_banned': false,
};

/// A container whose xiangqi client is stubbed at the HTTP layer.
///
/// The client's own token store is the real one and is empty, which is the point: this endpoint
/// answers a guest, so nothing here signs in first.
Future<ProviderContainer> makeUserContainer(MockClient client, {bool offline = false}) {
  return makeContainer(
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => client);
      }),
      if (offline) isDeviceOnlineProvider: isDeviceOnlineProvider.overrideWithValue(false),
    },
  );
}

/// A response carrying [body] as UTF-8 bytes, whatever the headers claim.
///
/// Not `mockResponse` from `test_helpers.dart`: that builds the response with `http.Response(body)`,
/// which encodes a `String` as Latin-1 and throws on the non-ASCII username this file is about. The
/// real server sends UTF-8 bytes with no charset, which is the case the reader has to handle
/// anyway.
Future<http.Response> utf8Response(String body, int status) =>
    Future.value(http.Response.bytes(utf8.encode(body), status));

/// A client answering the account lookup with [body] and [status], and nothing else.
MockClient accountClient(String body, {int status = 200, void Function(http.Request)? onRequest}) {
  return MockClient((request) {
    onRequest?.call(request);
    if (request.url.path.startsWith('/api/users/account/')) {
      return utf8Response(body, status);
    }
    return utf8Response('', 404);
  });
}

void main() {
  group('xiangqiLastOnlineFromJson', () {
    test('reads the Python bytes literal the wire really sends', () {
      // The measured form, quoted: neither a JSON number nor an ISO-8601 string.
      final instant = xiangqiLastOnlineFromJson("b'1788179925'");

      expect(instant, isNotNull);
      expect(instant!.isUtc, isTrue);
      expect(instant, DateTime.fromMillisecondsSinceEpoch(1788179925 * 1000, isUtc: true));
      expect(instant, DateTime.utc(2026, 8, 31, 12, 38, 45));
    });

    test('reads a bare epoch too, which is the same value without the wrapper', () {
      expect(xiangqiLastOnlineFromJson('1788179925'), xiangqiLastOnlineFromJson("b'1788179925'"));
    });

    test('a value it cannot read is null rather than a made-up instant', () {
      expect(xiangqiLastOnlineFromJson(null), isNull);
      expect(xiangqiLastOnlineFromJson(1788179925), isNull, reason: 'a number is not the shape');
      expect(xiangqiLastOnlineFromJson('not a date'), isNull);
      expect(xiangqiLastOnlineFromJson("b'not-a-number'"), isNull);
      expect(xiangqiLastOnlineFromJson(''), isNull);
    });
  });

  group('xiangqiUserProfileFromJson', () {
    test('reads the measured payload', () {
      final profile = xiangqiUserProfileFromJson(
        xiangqiAccountPayload().cast<String, dynamic>(),
        username: xiangqiAccountUsername,
      );

      expect(profile.username, xiangqiAccountUsername);
      expect(profile.bulletRating, 500);
      expect(profile.rapidRating, 600);
      expect(profile.dailyRating, 700);
      expect(profile.puzzleRating, 1200);
      expect(profile.isOnline, isTrue);
      expect(profile.countryName, 'United States');
      expect(profile.memberSince, DateTime.utc(2026, 8, 11, 10, 46, 26));
    });

    test('a rating the account does not have is null, not a zero', () {
      final profile = xiangqiUserProfileFromJson(
        xiangqiAccountPayload(bulletRating: null, puzzleRating: null).cast<String, dynamic>(),
        username: xiangqiAccountUsername,
      );

      expect(profile.bulletRating, isNull);
      expect(profile.puzzleRating, isNull);
      // The ones that are there are untouched.
      expect(profile.rapidRating, 600);
      expect(profile.dailyRating, 700);
    });

    test('no country is a null country name', () {
      final profile = xiangqiUserProfileFromJson(
        xiangqiAccountPayload(country: null).cast<String, dynamic>(),
        username: xiangqiAccountUsername,
      );

      expect(profile.countryName, isNull);
    });

    test('a country object with no name is a null country name', () {
      final profile = xiangqiUserProfileFromJson(
        xiangqiAccountPayload(country: const {'id': 226, 'code': 'US'}).cast<String, dynamic>(),
        username: xiangqiAccountUsername,
      );

      expect(profile.countryName, isNull);
    });

    test('a member_since that will not parse is null, not an error', () {
      final profile = xiangqiUserProfileFromJson(
        xiangqiAccountPayload(memberSince: 'not a date').cast<String, dynamic>(),
        username: xiangqiAccountUsername,
      );

      expect(profile.memberSince, isNull);
    });

    test('a missing username falls back to the one that was asked for', () {
      final json = xiangqiAccountPayload().cast<String, dynamic>()..remove('username');

      expect(
        xiangqiUserProfileFromJson(json, username: xiangqiAccountUsername).username,
        xiangqiAccountUsername,
      );
    });

    test('is_online is read strictly: only true is online', () {
      for (final value in const <Object?>[null, 1, 'true', false]) {
        final profile = xiangqiUserProfileFromJson(
          xiangqiAccountPayload(isOnline: value).cast<String, dynamic>(),
          username: xiangqiAccountUsername,
        );
        expect(profile.isOnline, isFalse, reason: 'is_online: $value');
      }
    });
  });

  group('xiangqiUserProvider', () {
    test('asks for the account by username and reads the profile', () async {
      http.Request? sent;
      final container = await makeUserContainer(
        accountClient(jsonEncode(xiangqiAccountPayload()), onRequest: (request) => sent = request),
      );

      final profile = await container.read(xiangqiUserProvider(xiangqiAccountUsername).future);

      expect(sent!.method, 'GET');
      // `url.path` is the encoded path, so the segment is where the raw username can be read back.
      expect(sent!.url.pathSegments, ['api', 'users', 'account', xiangqiAccountUsername]);
      expect(profile.username, xiangqiAccountUsername);
      expect(profile.rapidRating, 600);
      expect(profile.isOnline, isTrue);
      expect(profile.countryName, 'United States');
    });

    test('a non-ASCII username is percent-encoded once, not twice', () async {
      http.Request? sent;
      final container = await makeUserContainer(
        accountClient(jsonEncode(xiangqiAccountPayload()), onRequest: (r) => sent = r),
      );

      await container.read(xiangqiUserProvider(xiangqiAccountUsername).future);

      // The capture's own URL, byte for byte: `Uri.https` encodes the path itself, so the raw
      // username is what has to be handed to it.
      expect(
        sent!.url.toString(),
        'https://api.xiangqi.com/api/users/account/%E8%B5%B7%E5%8F%B8%E3%85%A4',
      );
    });

    test('a 404 is a ServerException, which the retry policy does not retry', () async {
      final container = await makeUserContainer(accountClient('', status: 404));

      await expectLater(
        container.read(xiangqiUserProvider(xiangqiAccountUsername).future),
        throwsA(isA<ServerException>()),
      );
    });

    test('being offline is an Error, and the request is never sent', () async {
      var requests = 0;
      // `isDeviceOnlineProvider` is not a network provider, so overriding it directly is what
      // AGENTS.md allows; the client underneath it stays a real one over a fake transport.
      final container = await makeUserContainer(
        accountClient(jsonEncode(xiangqiAccountPayload()), onRequest: (_) => requests++),
        offline: true,
      );

      await expectLater(
        container.read(xiangqiUserProvider(xiangqiAccountUsername).future),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0, reason: 'offline means the request is never sent');
    });
  });
}
