import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_hub_screen.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('shows both analysis boards without a game picker', (tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const AnalysisHubScreen(),
        overrides: {
          engineAvailabilityProvider: engineAvailabilityProvider.overrideWithValue(
            EngineAvailability.phone,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chess'), findsOneWidget);
    expect(find.text('Xiangqi'), findsOneWidget);
    expect(find.text('Analyse a xiangqi position with Pikafish.'), findsOneWidget);
  });

  testWidgets('leaves the xiangqi card out where Pikafish is not shipped', (tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const AnalysisHubScreen(),
        overrides: {
          engineAvailabilityProvider: engineAvailabilityProvider.overrideWithValue(
            EngineAvailability.none,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chess'), findsOneWidget);
    expect(find.text('Analyse a xiangqi position with Pikafish.'), findsNothing);
  });
}
