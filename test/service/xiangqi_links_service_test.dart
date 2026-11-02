import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/service/xiangqi_links_service.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_leaderboard_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../network/fake_http_client_factory.dart';
import '../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../test_provider_scope.dart';

class const NestedLinkHost({
  required final void Function(BuildContext, Future<void> Function()) onReady,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) => buildScreenRoute(
      screen: Consumer(
        builder: (context, ref, _) {
          onReady(
            context,
            () => ref.read(xiangqiLinksServiceProvider).openContentLink(context, '/leaders'),
          );
          return const Scaffold(body: Text('Nested link source'));
        },
      ),
    ),
  );
}

void main() {
  TestLichessBinding.ensureInitialized();

  for (final covered in [false, true]) {
    testWidgets('content links respect the parent route of a nested navigator ($covered)', (
      tester,
    ) async {
      BuildContext? sourceContext;
      Future<void> Function()? open;
      final requests = <http.Request>[];
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: NestedLinkHost(
            onReady: (context, callback) {
              sourceContext = context;
              open = callback;
            },
          ),
          failOnOverflow: true,
          overrides: {
            xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
              FakeXiangqiAuthStorage(signedInSession),
            ),
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (_) => FakeHttpClientFactory(
                () => MockClient((request) async {
                  requests.add(request);
                  return http.Response(
                    '{"meta":{"total_pages":0,"total_players":0,"current_page":1},"data":[]}',
                    200,
                  );
                }),
              ),
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      final root = Navigator.of(sourceContext!, rootNavigator: true);
      if (covered) {
        unawaited(
          root.push(buildScreenRoute(screen: const Scaffold(body: Text('Root covering page')))),
        );
        await tester.pumpAndSettle();
        // The nested route is still its own navigator's top, which is not sufficient to be visible.
        expect(ModalRoute.of(sourceContext!)!.isCurrent, isTrue);
        expect(sourceContext!.mounted, isTrue);
      }
      unawaited(open!());
      await tester.pumpAndSettle();
      final screen = find.byType(XiangqiLeaderboardScreen, skipOffstage: false);
      expect(screen, covered ? findsNothing : findsOneWidget);
      expect(requests, covered ? isEmpty : hasLength(1));
      if (!covered) {
        root.pop();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
