import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `window_manager` channel that records what it was asked and answers as told.
///
/// Held apart from the service's test because the title bar's test needs it too, and the two would
/// otherwise have to keep two answers to the same question in step by hand.
class FakeWindowChannel() {
  final List<MethodCall> calls = [];

  /// The bounds [getBounds] answers with.
  Rect bounds = const Rect.fromLTWH(100, 50, 1280, 720);

  /// What `isMaximized` answers with, kept true or false by `maximize`/`unmaximize` as well.
  bool maximized = false;

  /// The methods the app called, in order.
  List<String> get methods => [for (final call in calls) call.method];

  Map<Object?, Object?>? argsOf(String method) {
    for (final call in calls) {
      if (call.method == method) return call.arguments as Map<Object?, Object?>;
    }
    return null;
  }

  /// The size the last `setBounds` carrying one asked for, or null where none did.
  ///
  /// The plugin sends the size and the position through the same method, so which of the two a call
  /// is has to be read off its arguments.
  Size? get requestedSize {
    for (final call in calls.reversed) {
      if (call.method != 'setBounds') continue;
      final arguments = call.arguments as Map<Object?, Object?>;
      final width = arguments['width'];
      if (width is! num) continue;
      return Size(width.toDouble(), (arguments['height']! as num).toDouble());
    }
    return null;
  }

  /// The position the last `setBounds` carrying one asked to move the window to, or null where none
  /// did — which is what tells "the window was placed" apart from "it was left where it opened".
  Offset? get requestedPosition {
    for (final call in calls.reversed) {
      if (call.method != 'setBounds') continue;
      final arguments = call.arguments as Map<Object?, Object?>;
      final x = arguments['x'];
      if (x is! num) continue;
      return Offset(x.toDouble(), (arguments['y']! as num).toDouble());
    }
    return null;
  }

  /// Answers the channel, recording every call. [onCall] is asked first, for a test that wants the
  /// window to react the way the plugin would.
  void install({void Function(FakeWindowChannel channel, String method)? onCall}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        calls.add(call);
        onCall?.call(this, call.method);
        return switch (call.method) {
          'isMaximized' => maximized,
          'getBounds' => {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          },
          _ => null,
        };
      },
    );
  }

  /// Keeps [maximized] following the calls, which is what the plugin does.
  void followMaximizeCalls() {
    install(
      onCall: (channel, method) => switch (method) {
        'maximize' => channel.maximized = true,
        'unmaximize' => channel.maximized = false,
        _ => null,
      },
    );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  }
}

/// Answers `getAllDisplays` with one screen whose work area is [workArea], or throws where null.
void installDisplays(Rect? workArea) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
    (call) async {
      if (workArea == null) throw PlatformException(code: 'unavailable');
      return {
        'displays': [
          {
            'id': '0',
            'name': 'test',
            'size': {'width': workArea.width, 'height': workArea.height},
            'visiblePosition': {'dx': workArea.left, 'dy': workArea.top},
            'visibleSize': {'width': workArea.width, 'height': workArea.height},
            'scaleFactor': 1.0,
          },
        ],
      };
    },
  );
}

void uninstallDisplays() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
    null,
  );
}
