import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/view/auth/xiangqi_login_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The session store, in memory — the real one is secure storage, which this test never touches.
class FakeXiangqiAuthStorage([var XiangqiSession? session]) implements XiangqiAuthStorage {
  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession value) async => session = value;

  @override
  Future<void> delete() async => session = null;
}

/// A JWT carrying [claims] as its payload; the signature is never checked.
String jwt(Map<String, Object?> claims) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(const {'alg': 'none'})}.${segment(claims)}.sig';
}

Future<Widget> makeApp(WidgetTester tester, MockClientHandler handler) {
  return makeTestProviderScopeApp(
    tester,
    home: const XiangqiLoginScreen(),
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => MockClient(handler));
      }),
      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
        (ref) => FakeXiangqiAuthStorage(),
      ),
    },
  );
}

Future<void> submit(WidgetTester tester, {String password = 'hunter2'}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Email'), 'alice@example.com');
  await tester.enterText(find.widgetWithText(TextField, 'Password'), password);
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the invalid-credentials message when the password is wrong', (tester) async {
    final app = await makeApp(tester, (request) {
      // Connectivity probes are not traffic this screen produced.
      if (internetCheckUris.contains(request.url)) return mockResponse('', 200);
      if (request.url.path == '/api/users/signin') return mockResponse('', 401);
      return mockResponse('', 404);
    });
    await tester.pumpWidget(app);

    await submit(tester, password: 'wrong');

    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.byType(XiangqiLoginScreen), findsOneWidget);
  });

  testWidgets('signs in and pops when the credentials are right', (tester) async {
    http.Request? sent;
    final app = await makeApp(tester, (request) {
      if (internetCheckUris.contains(request.url)) return mockResponse('', 200);
      if (request.url.path == '/api/users/signin') {
        sent = request;
        return mockResponse(
          jsonEncode({
            'access_token': jwt(const {'sub': 7}),
            'user': {'username': 'alice'},
          }),
          200,
        );
      }
      return mockResponse('', 404);
    });
    await tester.pumpWidget(app);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(XiangqiLoginScreen)),
      listen: false,
    );
    // The controller is autoDispose: keep it alive so its state outlives the screen being popped.
    container.listen(xiangqiAuthControllerProvider, (_, _) {});

    await submit(tester);

    expect(sent?.method, 'POST');
    expect(sent?.url.path, '/api/users/signin');
    final session = container.read(xiangqiAuthControllerProvider);
    expect(session, isNotNull);
    expect(session!.name, 'alice');
    expect(session.isGuest, isFalse);
    // The session has a real token, so it did not fall through to the guest path.
    expect(session.accessToken, isNotEmpty);
    expect(find.byType(XiangqiLoginScreen), findsNothing);
  });
}
