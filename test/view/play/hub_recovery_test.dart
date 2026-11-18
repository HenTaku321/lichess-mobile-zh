import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/play/tournaments_hub_screen.dart';
import 'package:lichess_mobile/src/view/user/leaderboard_hub_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';
import '../xiangqi/xiangqi_leaderboard_screen_test.dart' as ranks;

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets(
    'retrying a tournament source leaves the other calendar open and fetches it only once',
    (tester) async {
      var lichessRequests = 0;
      var xiangqiRequests = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/tournament/list') {
          xiangqiRequests++;
          return http.Response('{"active":[{"id":"cup","name":"River Cup"}],"previous":[]}', 200);
        }
        if (request.url.path == '/api/tournament') {
          lichessRequests++;
          return lichessRequests == 1
              ? http.Response('', 503)
              : http.Response('{"created":[],"started":[],"finished":[]}', 200);
        }
        return http.Response('', 404);
      });
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const TournamentsHubScreen(),
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (_) => FakeHttpClientFactory(() => client),
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('River Cup'), findsOneWidget);
      final l10n = tester.element(find.byType(TournamentsHubScreen)).l10n;
      await tester.tap(find.text(l10n.more).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.less), findsOneWidget);
      final retry = find.byTooltip(l10n.retry);
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(lichessRequests, 2);
      expect(xiangqiRequests, 1);
      expect(find.text(l10n.less), findsOneWidget);
      expect(retry, findsNothing);
      expect(find.text('River Cup'), findsOneWidget);
    },
  );

  testWidgets(
    'a slow or failed speed never hides the available rankings and retries independently',
    (tester) async {
      final delayed = Completer<http.Response>();
      final counts = <String, int>{};
      final client = MockClient((request) async {
        if (request.url.path != '/api/leaders/v2/list') return http.Response('{}', 200);
        final mode = request.url.queryParameters['mode']!;
        counts[mode] = (counts[mode] ?? 0) + 1;
        if (mode == 'bullet' && counts[mode] == 1) return await delayed.future;
        final rows = mode == 'rapid' || mode == 'bullet'
            ? [ranks.row(name: '$mode player', rating: 1630)]
            : <Map<String, Object?>>[];
        return http.Response(jsonEncode(ranks.board(data: rows)), 200);
      });
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const LeaderboardHubScreen(),
          surfaceSize: const Size(800, 1400),
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (_) => FakeHttpClientFactory(() => client),
            ),
          },
        ),
      );
      await ranks.settle(tester, rounds: 8);
      expect(counts['rapid'], 1);
      expect(find.text('rapid player'), findsOneWidget);
      delayed.complete(http.Response('', 503));
      await ranks.settle(tester, rounds: 8);
      final retry = find.byTooltip(tester.element(find.byType(LeaderboardHubScreen)).l10n.retry);
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await ranks.settle(tester, rounds: 6);
      expect(find.text('rapid player'), findsOneWidget);
      expect(find.text('bullet player'), findsOneWidget);
      expect(counts, {'rapid': 1, 'bullet': 2, 'daily': 1, 'puzzle': 1});
      expect(retry, findsNothing);
    },
  );
}
