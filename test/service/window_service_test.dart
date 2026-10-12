import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/service/window_service.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../binding.dart';
import 'fake_window_manager.dart';

/// The preference key the service stores its record under. A literal, because the service keeps it
/// private: a test that read it from the service would keep passing after the key was renamed, and
/// the rename is exactly what would lose every user's window size.
const _key = 'window_geometry_v1';

Future<void> store(WindowGeometry geometry) =>
    testBinding.sharedPreferences.setString(_key, geometry.encode());

WindowGeometry? stored() => WindowGeometry.tryDecode(testBinding.sharedPreferences.getString(_key));

void main() {
  TestLichessBinding.ensureInitialized();

  group('WindowGeometry.tryDecode', () {
    test('refuses everything that is not a usable record', () {
      expect(WindowGeometry.tryDecode(null), isNull);
      expect(WindowGeometry.tryDecode(42), isNull);
      expect(WindowGeometry.tryDecode(''), isNull);
      expect(WindowGeometry.tryDecode('not json'), isNull);
      expect(WindowGeometry.tryDecode('[]'), isNull);
      expect(WindowGeometry.tryDecode('{}'), isNull);
      expect(WindowGeometry.tryDecode('{"width": 100}'), isNull);
      expect(WindowGeometry.tryDecode('{"width": 0, "height": 100}'), isNull);
      expect(WindowGeometry.tryDecode('{"width": -100, "height": 100}'), isNull);
      expect(WindowGeometry.tryDecode('{"width": "100", "height": 100}'), isNull);
      expect(WindowGeometry.tryDecode('{"width": ${double.nan}, "height": 100}'), isNull);
    });

    test('reads a full record', () {
      final geometry = WindowGeometry.tryDecode(
        '{"width": 1600, "height": 900, "x": 120, "y": 80, "maximized": true}',
      );
      expect(geometry, isNotNull);
      expect(geometry!.size, const Size(1600, 900));
      expect(geometry.position, const Offset(120, 80));
      expect(geometry.isMaximized, isTrue);
    });

    test('takes half a pair of coordinates as no position at all', () {
      final geometry = WindowGeometry.tryDecode('{"width": 1600, "height": 900, "x": 120}');
      expect(geometry, isNotNull);
      expect(geometry!.position, isNull);
      expect(geometry.size, const Size(1600, 900), reason: 'the size is still good');
    });

    test('a flag stored as anything but true is false', () {
      expect(
        WindowGeometry.tryDecode('{"width": 1, "height": 1, "maximized": "yes"}')?.isMaximized,
        isFalse,
      );
      expect(WindowGeometry.tryDecode('{"width": 1, "height": 1}')?.isMaximized, isFalse);
    });

    test('survives a round trip, with the position left out where there is none', () {
      const withPosition = WindowGeometry(
        size: Size(1600, 900),
        position: Offset(120, 80),
        isMaximized: true,
      );
      final read = WindowGeometry.tryDecode(withPosition.encode());
      expect(read!.size, withPosition.size);
      expect(read.position, withPosition.position);
      expect(read.isMaximized, isTrue);

      const atOrigin = WindowGeometry(size: Size(1600, 900), position: Offset.zero);
      final readOrigin = WindowGeometry.tryDecode(atOrigin.encode());
      expect(readOrigin!.position, Offset.zero, reason: 'a window at 0,0 was at 0,0');

      const nowhere = WindowGeometry(size: Size(1600, 900));
      expect(nowhere.toJson().containsKey('x'), isFalse);
      expect(WindowGeometry.tryDecode(nowhere.encode())!.position, isNull);
    });
  });

  group('clampWindowGeometry', () {
    const desktop = Rect.fromLTWH(0, 0, 1920, 1080);
    const small = Rect.fromLTWH(0, 0, 1024, 768);

    test('leaves a geometry that fits alone', () {
      const geometry = WindowGeometry(size: Size(1280, 720), position: Offset(100, 100));
      expect(clampWindowGeometry(geometry, workAreas: const [desktop]), geometry);
    });

    test('raises a size below the minimum the app is usable at', () {
      const geometry = WindowGeometry(size: Size(200, 100));
      final clamped = clampWindowGeometry(geometry, workAreas: const [desktop]);
      expect(clamped.size, kMinimumWindowSize);
    });

    test('caps a size at the largest work area', () {
      const geometry = WindowGeometry(size: Size(3000, 2000));
      expect(clampWindowGeometry(geometry, workAreas: const [desktop]).size, desktop.size);
    });

    test('caps at the largest of several work areas', () {
      const geometry = WindowGeometry(size: Size(3000, 2000));
      final clamped = clampWindowGeometry(geometry, workAreas: const [small, desktop]);
      expect(clamped.size, desktop.size);
    });

    test('keeps a position that overlaps a work area enough to be reachable', () {
      // The right edge of the window lands 100px inside the desktop: the least that is still a
      // grabbable title bar.
      const geometry = WindowGeometry(size: Size(1280, 720), position: Offset(-1180, 0));
      expect(clampWindowGeometry(geometry, workAreas: const [desktop]).position, geometry.position);
    });

    test('drops a position that overlaps by less than that', () {
      const geometry = WindowGeometry(size: Size(1280, 720), position: Offset(-1181, 0));
      final clamped = clampWindowGeometry(geometry, workAreas: const [desktop]);
      expect(clamped.position, isNull);
      expect(clamped.size, geometry.size, reason: 'only the position is unusable');
    });

    test('drops a position on a screen that is gone', () {
      const geometry = WindowGeometry(size: Size(1280, 720), position: Offset(4000, 3000));
      expect(clampWindowGeometry(geometry, workAreas: const [desktop]).position, isNull);
    });

    test('keeps a position inside a second screen', () {
      const second = Rect.fromLTWH(1920, 0, 1920, 1080);
      const geometry = WindowGeometry(size: Size(1280, 720), position: Offset(2000, 100));
      final clamped = clampWindowGeometry(geometry, workAreas: const [desktop, second]);
      expect(clamped.position, geometry.position);
    });

    test('clamps nothing but the minimum where no work area was reported', () {
      const geometry = WindowGeometry(size: Size(3000, 2000), position: Offset(9000, 9000));
      expect(clampWindowGeometry(geometry, workAreas: const []), geometry);
      const tiny = WindowGeometry(size: Size(10, 10));
      expect(
        clampWindowGeometry(tiny, workAreas: const []).size,
        kMinimumWindowSize,
        reason: 'the minimum is about the app, not about the screens',
      );
    });

    test('keeps the maximized flag through every clamp', () {
      const geometry = WindowGeometry(size: Size(3000, 2000), isMaximized: true);
      expect(clampWindowGeometry(geometry, workAreas: const [desktop]).isMaximized, isTrue);
      expect(clampWindowGeometry(geometry, workAreas: const []).isMaximized, isTrue);
    });
  });

  group('geometryToStore', () {
    const geometry = WindowGeometry(
      size: Size(1280, 720),
      position: Offset(120, 80),
      isMaximized: true,
    );

    test('keeps the position where the session can put the window back', () {
      expect(geometryToStore(geometry, canRestorePosition: true), geometry);
    });

    test('drops the position where it cannot, keeping the rest', () {
      final stored = geometryToStore(geometry, canRestorePosition: false);
      expect(stored.position, isNull);
      expect(stored.size, geometry.size);
      expect(stored.isMaximized, isTrue);
    });
  });

  group('isPositionRestorable', () {
    test('is true for x11 and nothing else', () {
      expect(isPositionRestorable('x11'), isTrue);
      expect(isPositionRestorable('X11'), isTrue);
      expect(isPositionRestorable('wayland'), isFalse);
      expect(isPositionRestorable(''), isFalse);
      expect(isPositionRestorable(null), isFalse);
    });
  });

  group('workAreasOf', () {
    test('is each display minus its panels, and skips the ones that reported none', () {
      final displays = [
        const Display(
          id: '0',
          size: Size(1920, 1080),
          visiblePosition: Offset.zero,
          visibleSize: Size(1920, 1040),
        ),
        const Display(id: '1', size: Size(1280, 800)),
        const Display(
          id: '2',
          size: Size(1280, 800),
          visiblePosition: Offset(1920, 0),
          visibleSize: Size(1280, 800),
        ),
      ];
      expect(workAreasOf(displays), const [
        Rect.fromLTWH(0, 0, 1920, 1040),
        Rect.fromLTWH(1920, 0, 1280, 800),
      ]);
    });
  });

  group('WindowService.restore', () {
    late FakeWindowChannel channel;

    setUp(() {
      channel = FakeWindowChannel()..install();
      installDisplays(const Rect.fromLTWH(0, 0, 1920, 1080));
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(testBinding.reset);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        channel.uninstall();
        uninstallDisplays();
      });
    });

    test('does nothing at all off Linux', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await store(const WindowGeometry(size: Size(1600, 900)));
      await WindowService().restore();

      expect(channel.methods, isEmpty);
    });

    test('sizes the window from the stored record, after the minimum', () async {
      await store(const WindowGeometry(size: Size(1600, 900)));
      await WindowService().restore();

      expect(channel.methods, ['ensureInitialized', 'setMinimumSize', 'setBounds']);
      expect(channel.requestedSize, const Size(1600, 900));
      expect(channel.argsOf('setMinimumSize'), containsPair('width', kMinimumWindowSize.width));
    });

    test('opens at the runner default where there is no record', () async {
      await WindowService().restore();

      expect(channel.methods, ['ensureInitialized', 'setMinimumSize']);
    });

    test('opens at the runner default where the record is damaged', () async {
      await testBinding.sharedPreferences.setString(_key, 'not json');
      await WindowService().restore();

      expect(channel.methods, ['ensureInitialized', 'setMinimumSize']);
    });

    test('places the window where the session can put it back', () async {
      await store(const WindowGeometry(size: Size(1600, 900), position: Offset(120, 80)));
      await WindowService().restore(restorePosition: true);

      expect(channel.methods, ['ensureInitialized', 'setMinimumSize', 'setBounds', 'setBounds']);
      expect(channel.requestedPosition, const Offset(120, 80));
    });

    test(
      'never asks to be placed where the session cannot, so much as a stored position',
      () async {
        await store(const WindowGeometry(size: Size(1600, 900), position: Offset(120, 80)));
        await WindowService().restore(restorePosition: false);

        expect(channel.methods, ['ensureInitialized', 'setMinimumSize', 'setBounds']);
        expect(channel.requestedPosition, isNull);
        expect(channel.requestedSize, const Size(1600, 900));
      },
    );

    test('fits the record to the screens that are attached now', () async {
      installDisplays(const Rect.fromLTWH(0, 0, 1024, 768));
      await store(const WindowGeometry(size: Size(3000, 2000), position: Offset(4000, 3000)));
      await WindowService().restore(restorePosition: true);

      expect(channel.requestedSize, const Size(1024, 768));
      expect(channel.requestedPosition, isNull);
    });

    test('keeps the position as stored where the screens could not be read', () async {
      installDisplays(null);
      await store(const WindowGeometry(size: Size(1600, 900), position: Offset(4000, 3000)));
      await WindowService().restore(restorePosition: true);

      expect(channel.requestedSize, const Size(1600, 900));
      expect(channel.requestedPosition, const Offset(4000, 3000));
    });

    test('opens maximized where that is how it was left, and says so', () async {
      await store(const WindowGeometry(size: Size(1600, 900), isMaximized: true));
      final service = WindowService();
      await service.restore();

      expect(channel.methods.last, 'maximize');
      expect(service.maximized.value, isTrue);
    });

    test('is not fatal when the plugin is not there', () async {
      channel.uninstall();
      await store(const WindowGeometry(size: Size(1600, 900)));

      await expectLater(WindowService().restore(), completes);
    });
  });

  group('WindowService.start, close and the window events', () {
    late FakeWindowChannel channel;

    setUp(() {
      channel = FakeWindowChannel()..install();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(testBinding.reset);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        channel.uninstall();
      });
    });

    test('remembers what the window was when the app closes', () async {
      channel.bounds = const Rect.fromLTWH(100, 50, 1600, 900);
      final service = WindowService();
      await service.start();
      await service.close();

      expect(channel.methods, contains('close'));
      expect(stored()?.size, const Size(1600, 900));
      expect(stored()?.isMaximized, isFalse);
    });

    test('watches nothing off Linux, not even to initialize', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = WindowService();
      await service.start();

      expect(channel.methods, isEmpty);
      expect(stored(), isNull);
    });

    test('closing while maximized keeps the size it was maximized from', () async {
      channel.bounds = const Rect.fromLTWH(0, 0, 1280, 720);
      final service = WindowService();
      await service.start();

      // What the window reports once it is maximized, which is what must not be remembered.
      channel.bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
      service.onWindowMaximize();
      await Future<void>.delayed(Duration.zero);

      expect(service.maximized.value, isTrue);
      expect(stored()?.size, const Size(1280, 720));
      expect(stored()?.isMaximized, isTrue);

      await service.close();
      expect(stored()?.size, const Size(1280, 720));
      expect(stored()?.isMaximized, isTrue);
    });

    test('restoring goes back to the size it had before it was maximized', () async {
      channel.bounds = const Rect.fromLTWH(0, 0, 1280, 720);
      final service = WindowService();
      await service.start();

      channel.bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
      service.onWindowMaximize();
      await Future<void>.delayed(Duration.zero);

      channel.bounds = const Rect.fromLTWH(0, 0, 1280, 720);
      service.onWindowUnmaximize();
      await Future<void>.delayed(Duration.zero);

      expect(service.maximized.value, isFalse);
      expect(stored()?.size, const Size(1280, 720));
      expect(stored()?.isMaximized, isFalse);
    });

    test('says which way the window is maximized only once per change', () async {
      final service = WindowService();
      await service.start();

      var changes = 0;
      service.maximized.addListener(() => changes++);

      service.onWindowMaximize();
      service.onWindowMaximize();
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);

      service.onWindowUnmaximize();
      expect(changes, 2);
      expect(service.maximized.value, isFalse);
    });
  });
}
