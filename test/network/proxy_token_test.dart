import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// The proxy in front of the app is billed for every request it answers, so the
/// token that gets past it is attached to requests to that proxy and to nothing
/// else. These cases exercise [zhProxyHeaders] directly, so a build that has no
/// token in it — the debug build these tests run as, and CI's — can still check
/// the attaching rules.
void main() {
  const token = 'abcdef0123456789abcdef0123456789';

  group('zhProxyHeaders', () {
    test("attaches the token to this build's own server", () {
      expect(zhProxyHeaders(Uri.https(kLichessHost, '/api/user/thibault'), token: token), {
        kZhProxyTokenHeader: token,
      });
    });

    test('attaches nothing to the other hosts the app talks to', () {
      // The CDN, the opening explorer and the tablebase are not ours to hand a
      // secret to, and neither is lichess.org itself.
      for (final uri in [
        Uri.https('lichess1.org', '/assets/board.png'),
        Uri.https('explorer.lichess.org', '/lichess'),
        Uri.https('tablebase.lichess.org', '/standard'),
        Uri.https('lichess.org', '/api/user/thibault'),
      ]) {
        expect(zhProxyHeaders(uri, token: token), isEmpty, reason: 'token sent to ${uri.host}');
      }
    });

    test('a hostname that merely ends in this one is another host', () {
      expect(
        zhProxyHeaders(Uri.https('$kLichessHost.example.org', '/api/user/thibault'), token: token),
        isEmpty,
      );
      expect(
        zhProxyHeaders(Uri.https('evil.$kLichessHost', '/api/user/thibault'), token: token),
        isEmpty,
      );
    });

    test('another port on this host is another service', () {
      expect(
        zhProxyHeaders(Uri.https('$kLichessHost:9', '/api/user/thibault'), token: token),
        isEmpty,
      );
    });

    test('a build without a token sends nothing anywhere', () {
      expect(zhProxyHeaders(Uri.https(kLichessHost, '/api/user/thibault')), isEmpty);
    });

    test('an empty token is not a token', () {
      expect(zhProxyHeaders(Uri.https(kLichessHost, '/api/user/thibault'), token: ''), isEmpty);
    });
  });
}
