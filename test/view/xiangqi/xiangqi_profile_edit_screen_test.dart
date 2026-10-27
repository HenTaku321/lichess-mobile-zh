import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_edit_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../../test_provider_scope.dart';

class _SlowProfileStorage() extends FakeXiangqiAuthStorage {
  @override
  Future<void> write(XiangqiSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await super.write(session);
  }
}

Future<ProviderContainer> pumpEdit(
  WidgetTester tester, {
  bool failSave = true,
  bool routed = false,
  ValueChanged<String?>? onResult,
}) async {
  final client = MockClient((request) async {
    if (request.method == 'PUT') {
      return failSave
          ? http.Response('{"message":"internal raw error"}', 503)
          : http.Response('{"username":"Renamed","bio":"","country":{"id":1}}', 200);
    }
    if (request.url.path.endsWith('/countries')) {
      return http.Response('[{"value":1,"code":"CN","name":"China"}]', 200);
    }
    return http.Response(
      jsonEncode({
        'username': 'Tester',
        'bio': '',
        'email': 'test@example.invalid',
        'country': {'id': 1, 'code': 'CN', 'name': 'China'},
      }),
      200,
    );
  });
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: routed
          ? Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async => onResult?.call(
                    await Navigator.of(context)
                        .push<String?>(XiangqiProfileEditScreen.buildRoute('Tester')),
                  ),
                  child: const Text('Edit'),
                ),
              ),
            )
          : const XiangqiProfileEditScreen(username: 'Tester'),
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          routed
              ? (_SlowProfileStorage()..session = signedInSession)
              : FakeXiangqiAuthStorage(signedInSession),
        ),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => client),
        ),
      },
    ),
  );
  if (routed) {
    await tester.tap(find.text('Edit'));
    await tester.pump();
  }
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 1600));
  }
  return ProviderScope.containerOf(tester.element(find.byType(XiangqiProfileEditScreen)));
}

void main() {
  TestLichessBinding.ensureInitialized();
  testWidgets('changing the username closes the edit route after a delayed storage write', (
    tester,
  ) async {
    String? result;
    final container = await pumpEdit(
      tester,
      failSave: false,
      routed: true,
      onResult: (value) => result = value,
    );
    final l10n = tester.element(find.byType(XiangqiProfileEditScreen)).l10n;
    await tester.enterText(find.widgetWithText(TextFormField, l10n.username), 'Renamed');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, l10n.password), 'password');
    final save = find.widgetWithText(FilledButton, l10n.save);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(result, 'Renamed');
    expect(container.read(xiangqiAuthControllerProvider)?.name, 'Renamed');
    expect(find.byType(XiangqiProfileEditScreen), findsNothing);
  });
  testWidgets('failed profile saving preserves the draft and shows localized errors', (
    tester,
  ) async {
    await pumpEdit(tester);
    final l10n = tester.element(find.byType(XiangqiProfileEditScreen)).l10n;
    final bio = find.widgetWithText(TextFormField, l10n.biography);
    await tester.enterText(bio, 'Keep this biography');
    final save = find.widgetWithText(FilledButton, l10n.save);
    await tester.ensureVisible(save);
    await tester.tap(save);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 1600));
    }
    expect(tester.widget<TextFormField>(bio).controller!.text, 'Keep this biography');
    expect(find.text('internal raw error'), findsNothing);
    expect(find.text(l10n.mobileSomethingWentWrong), findsOneWidget);
  });

  testWidgets('another account cannot keep the old account edit form open', (tester) async {
    final container = await pumpEdit(tester);
    await container
        .read(xiangqiSessionStoreProvider)
        .write(signedInSession.copyWith(userId: 'B', name: 'B'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('another account with the same username cannot take over the edit route', (
    tester,
  ) async {
    final container = await pumpEdit(tester);
    await container.read(xiangqiSessionStoreProvider).write(signedInSession.copyWith(userId: 'B'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('signing back into the same account does not reopen its old edit form', (
    tester,
  ) async {
    final container = await pumpEdit(tester);
    final store = container.read(xiangqiSessionStoreProvider);
    await store.write(null);
    await tester.pumpAndSettle();
    await store.write(signedInSession);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
  });
}
