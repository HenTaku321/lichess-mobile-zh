import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/view/auth/email_login_screen.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_options.dart';
import 'package:lichess_mobile/src/view/auth/xiangqi_login_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

/// A page whose only job is to open the sign-in options sheet, so the sheet can be tested without
/// the account screen it lives on.
class const _SignInOptionsHarness() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showSignInOptions(context, ref),
          child: const Text('Open sign in options'),
        ),
      ),
    );
  }
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(tester, home: const _SignInOptionsHarness()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open sign in options'));
  await tester.pumpAndSettle();
}

void main() {
  group('showSignInOptions', () {
    testWidgets('offers the browser, the email and the xiangqi sign-ins', (tester) async {
      await openSheet(tester);

      expect(find.text('Sign in with the browser'), findsOneWidget);
      expect(find.text('Sign in with an email'), findsOneWidget);
      expect(find.text('Sign in to xiangqi.com'), findsOneWidget);
    });

    testWidgets('tapping the email action opens the email login screen', (tester) async {
      await openSheet(tester);

      await tester.tap(find.text('Sign in with an email'));
      await tester.pumpAndSettle();

      expect(find.byType(EmailLoginScreen), findsOneWidget);
      expect(find.byType(XiangqiLoginScreen), findsNothing);
    });

    testWidgets('tapping the xiangqi action opens the xiangqi login screen', (tester) async {
      await openSheet(tester);

      // The third action is what this wave added to the account sheet, and this is what says it
      // really opens the xiangqi screen rather than a second way into the lichess one.
      await tester.tap(find.text('Sign in to xiangqi.com'));
      await tester.pumpAndSettle();

      expect(find.byType(XiangqiLoginScreen), findsOneWidget);
      expect(find.byType(EmailLoginScreen), findsNothing);
    });

    testWidgets('tapping the browser action starts the flow but does not navigate', (tester) async {
      await openSheet(tester);

      // The OAuth flow hands off to the system browser, so this test drives none of it. What it
      // pins down is that the action is not wired to a route of its own: it leaves the caller on
      // the page that opened the sheet, unlike the other two.
      await tester.tap(find.text('Sign in with the browser'));
      await tester.pumpAndSettle();

      expect(find.byType(EmailLoginScreen), findsNothing);
      expect(find.byType(XiangqiLoginScreen), findsNothing);
      expect(find.text('Open sign in options'), findsOneWidget);
    });
  });
}
