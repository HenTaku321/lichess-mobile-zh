import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/init.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'binding.dart';

void main() {
  TestLichessBinding.ensureInitialized();
  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      'initialization error reporting respects the native capabilities on ${platform.name}',
      (tester) async {
        addTearDown(testBinding.reset);
        PackageInfo.setMockInitialValues(
          appName: 'Test',
          packageName: 'org.lichess.test',
          version: '0.29.1',
          buildNumber: '1',
          buildSignature: 'fixture',
        );
        await testBinding.setInitialSharedPreferencesValues({
          'first_run': false,
          'installed_version': 'invalid version',
        });
        await initializeApp();
        expect(testBinding.sharedPreferences.getBool('first_run'), isFalse);
        expect(
          testBinding.firebaseCrashlytics.recordedErrors,
          platform == TargetPlatform.linux ? isEmpty : hasLength(1),
        );
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
