import 'dart:convert';
import 'dart:io';

import 'package:chessground/chessground.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/view/puzzle/puzzle_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/pgn.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';
import 'example_data.dart' as chess;

// The Actions job runs this same probe inside two independent source checkouts.
void main() {
  TestLichessBinding.ensureInitialized();
  final output = Platform.environment['CHESS_LAYOUT_OUTPUT'];
  final reference = Platform.environment['CHESS_LAYOUT_REFERENCE'];
  if (output == null) return;

  // This probe is copied into the fixed reference checkout, whose test harness predates the
  // device-info mock. Keep the same platform response on both revisions so Android gesture
  // setup cannot stop the reference run before any geometry has been measured.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (call) async => <String, Object?>{
        'version': <String, Object?>{
          'baseOS': '',
          'codename': 'REL',
          'incremental': 'test',
          'previewSdkInt': 0,
          'release': '9',
          'sdkInt': 28,
          'securityPatch': '',
        },
        for (final field in [
          'board',
          'bootloader',
          'brand',
          'device',
          'display',
          'fingerprint',
          'hardware',
          'host',
          'id',
          'manufacturer',
          'model',
          'product',
          'name',
          'tags',
          'type',
        ])
          field: 'test',
        'time': 0,
        'isPhysicalDevice': false,
        'freeDiskSize': 0,
        'totalDiskSize': 0,
        'isLowRamDevice': false,
        'physicalRamSize': 4096,
        'availableRamSize': 2048,
      },
    );
  });

  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    testWidgets('opening a chess puzzle preserves its layout at $size', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: PuzzleScreen(angle: const PuzzleTheme(PuzzleThemeKey.mix), puzzle: chess.puzzle),
          surfaceSize: size,
          failOnOverflow: true,
        ),
      );
      await tester.pumpAndSettle();
      final bounds = <String, List<double>>{};
      for (final (role, finder) in [
        ('board', find.byType(Chessboard)),
        ('feedback', find.text('Your turn')),
        ('actions', find.byType(BottomBar)),
        if (size.width > size.height) ('notation', find.byType(DebouncedPgnTreeView)),
      ]) {
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        bounds[role] = [rect.left, rect.top, rect.width, rect.height];
      }
      final name = '${size.width.toInt()}x${size.height.toInt()}.json';
      await tester.runAsync(() async {
        await Directory(output).create(recursive: true);
        await File('$output/$name').writeAsString(jsonEncode(bounds));
        if (reference != null) {
          final expected =
              jsonDecode(await File('$reference/$name').readAsString()) as Map<String, dynamic>;
          expect(bounds.keys, unorderedEquals(expected.keys));
          for (final entry in bounds.entries) {
            final values = expected[entry.key]! as List<dynamic>;
            expect(
              entry.value,
              orderedEquals([for (final value in values) closeTo(value as num, 1)]),
              reason: '${entry.key} at $size',
            );
          }
        }
      });
      expect(tester.takeException(), isNull);
    });
  }
}
