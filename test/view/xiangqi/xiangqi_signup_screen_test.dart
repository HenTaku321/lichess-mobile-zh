// Tests for the screen a xiangqi.com account is made on.
//
// The screen is driven over a stubbed HTTP client, and what is pinned is the three-step shape the
// server imposes: an address is given a code, the code is handed back, and only then is there
// anything to attach a username and a password to. Measured on 2026-10-19 — see
// `xiangqi-com-re/docs/auth.md` — and every value here is this file's own.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_signup_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// The session store, in memory — the real one is secure storage, which this test never touches.
class FakeSignUpStorage([var XiangqiSession? session]) implements XiangqiAuthStorage {
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

/// The country list the form's picker is built from, as the endpoint answers it.
const _countries =
    '[{"code":"CN","name":"China","value":1},'
    '{"code":"HK","name":"Hong Kong, China","value":2}]';

/// The bodies the sign-up endpoints answer with when everything goes right.
String _okBody(String path) => switch (path) {
  '/api/users/signup_email' => '{"message": "Verification Code sent to your email"}',
  '/api/users/verify_otp' => '{"message": "Email Verified!", "email": "a@example.com"}',
  '/api/users/signup_details' => jsonEncode({
    'message': 'Logged in as alice',
    'access_token': jwt(const {'sub': 100001}),
    'refresh_token': 'the-refresh-token',
  }),
  '/api/users/countries' => _countries,
  _ => '{}',
};

/// Opens the screen over a client that answers [handler], falling back to the happy path.
///
/// [handler] answers with a response or with null, and null means "this is not the request I am
/// about to refuse" — the fallback is what the happy path is made of.
Future<FakeSignUpStorage> pumpSignUp(
  WidgetTester tester, {
  Future<http.Response?> Function(http.Request)? handler,
  List<(String, String)>? sent,
}) async {
  final storage = FakeSignUpStorage();
  final client = MockClient((request) async {
    // Connectivity probes are not traffic this screen produced.
    if (internetCheckUris.contains(request.url)) return http.Response('', 200);
    sent?.add((request.url.path, request.body));
    final custom = handler == null ? null : await handler(request);
    if (custom != null) return custom;
    return http.Response(_okBody(request.url.path), 200);
  });

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const XiangqiSignUpScreen(),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith((ref) => storage),
      },
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

/// Walks the first two steps, leaving the form on the details step.
Future<void> reachDetails(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@example.com');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Send the code'));
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextField, 'Code'), '123456');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Code'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks for a code first, and only then for the rest', (tester) async {
    final sent = <(String, String)>[];
    await pumpSignUp(tester, sent: sent);

    // The first step is the address and nothing else: there is nothing to attach an account to
    // until the address has answered a code.
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Code'), findsNothing);
    expect(find.widgetWithText(TextField, 'Username'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send the code'));
    await tester.pumpAndSettle();

    // The country list is asked for beside it, which is the form's own doing and not this step's.
    final asked = sent.where((request) => request.$1 == '/api/users/signup_email').single;
    expect(jsonDecode(asked.$2), {'email': 'a@example.com', 'locale': 'en'});
    // The address is now read-only: the code went to it, not to whatever is typed over it.
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Email')).enabled, isFalse);
    expect(find.widgetWithText(TextField, 'Code'), findsOneWidget);
  });

  testWidgets('makes the account, and signs in with it', (tester) async {
    final sent = <(String, String)>[];
    final storage = await pumpSignUp(tester, sent: sent);
    await reachDetails(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'alice');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'a-password');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('China').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create an account'));
    await tester.pumpAndSettle();

    final details = jsonDecode(
      sent.lastWhere((request) => request.$1 == '/api/users/signup_details').$2,
    );
    expect(details, {
      'username': 'alice',
      'email': 'a@example.com',
      'password': 'a-password',
      'profileImage': '',
      'country': '1',
      'locale': 'en',
    });
    // The last call signs the account in, so there is nothing to sign in to afterwards.
    expect(storage.session?.name, 'alice');
    expect(storage.session?.isGuest, isFalse);
  });

  testWidgets('says so when the code is refused, and stays on that step', (tester) async {
    await pumpSignUp(
      tester,
      handler: (request) async => request.url.path == '/api/users/verify_otp'
          ? http.Response('{"message": "Invalid or expired verification code"}', 400)
          : null,
    );

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send the code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Code'), '000000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Code'));
    await tester.pumpAndSettle();

    expect(find.text('That code is not right.'), findsOneWidget);
    // Still on the code step, with the code still in the field: the reader has to be able to try
    // again without the form throwing away what they typed.
    expect(find.widgetWithText(TextField, 'Code'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Username'), findsNothing);
  });

  testWidgets('says so when the address already has an account', (tester) async {
    await pumpSignUp(
      tester,
      handler: (request) async => request.url.path == '/api/users/signup_email'
          ? http.Response(
              '{"message": "Email already exists. Please login", '
              '"errors": {"error_msg": "Email already exists. Please login"}}',
              400,
            )
          : null,
    );

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'taken@example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send the code'));
    await tester.pumpAndSettle();

    expect(find.text('That address already has an account.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Code'), findsNothing);
  });
}
