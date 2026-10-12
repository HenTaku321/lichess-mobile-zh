import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lichess_mobile/firebase_options.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A singleton class that provides access to plugins and external APIs.
///
/// Only one instance of this class will be created during the app's lifetime.
/// See [AppLichessBinding] for the concrete implementation.
///
/// Modeled after the Flutter framework's [WidgetsBinding] class.
///
/// The preferred way to mock or fake a plugin or external API is to create a
/// provider with riverpod because it gives more flexibility and control over
/// the behavior of the fake.
/// However, if the plugin is used in a way that doesn't allow for easy mocking
/// with riverpod, a test binding can be used to provide a fake implementation.
abstract class LichessBinding() {
  this : assert(_instance == null) {
    initInstance();
  }

  /// The single instance of [LichessBinding].
  static LichessBinding get instance => checkInstance(_instance);
  static LichessBinding? _instance;

  @protected
  @mustCallSuper
  void initInstance() {
    _instance = this;
  }

  static T checkInstance<T extends LichessBinding>(T? instance) {
    assert(() {
      if (instance == null) {
        throw FlutterError.fromParts([
          ErrorSummary('Lichess binding has not yet been initialized.'),
          ErrorHint(
            'In the app, this is done by the `AppLichessBinding.ensureInitialized()` call '
            'in the `void main()` method.',
          ),
          ErrorHint(
            'In a test, one can call `TestLichessBinding.ensureInitialized()` as the '
            "first line in the test's `main()` method to initialize the binding.",
          ),
        ]);
      }
      return true;
    }());
    return instance!;
  }

  /// Counts how many times the app has been (cold) started.
  int get numAppStarts;

  /// Which of the engines that ship inside the app can be run here.
  ///
  /// On Android and iOS they are all native libraries in the bundle, which the engine plugin
  /// creates in-process; on the Linux desktop build this fork adds, two of the four are, and the
  /// other two have no library to load.
  EngineAvailability get bundledEngines;

  /// The shared preferences instance. Must be preloaded before use.
  ///
  /// This is a synchronous getter that throws an error if shared preferences
  /// have not yet been initialized.
  SharedPreferencesWithCache get sharedPreferences;

  /// Initialize Firebase.
  ///
  /// This wraps [Firebase.initializeApp].
  ///
  /// This should be called only once before the app starts.
  Future<void> initializeFirebase();

  /// Wraps [FirebaseMessaging.instance].
  FirebaseMessaging get firebaseMessaging;

  /// Wraps [FirebaseCrashlytics.instance].
  FirebaseCrashlytics get firebaseCrashlytics;

  /// Wraps [FirebaseMessaging.onMessage].
  Stream<RemoteMessage> get firebaseMessagingOnMessage;

  /// Wraps [FirebaseMessaging.onMessageOpenedApp].
  Stream<RemoteMessage> get firebaseMessagingOnMessageOpenedApp;

  /// Wraps [FirebaseMessaging.onBackgroundMessage].
  void firebaseMessagingOnBackgroundMessage(BackgroundMessageHandler handler);
}

/// A concrete implementation of [LichessBinding] for the app.
class AppLichessBinding() extends LichessBinding {
  /// Returns an instance of the binding that implements [LichessBinding].
  ///
  /// If no binding has yet been initialized, the [AppLichessBinding] class is
  /// used to create and initialize one.
  factory ensureInitialized() {
    if (LichessBinding._instance == null) {
      AppLichessBinding();
    }
    return LichessBinding.instance as AppLichessBinding;
  }

  late Future<SharedPreferencesWithCache> _sharedPreferencesWithCache;
  SharedPreferencesWithCache? _syncSharedPreferencesWithCache;

  @override
  SharedPreferencesWithCache get sharedPreferences {
    if (_syncSharedPreferencesWithCache == null) {
      throw FlutterError.fromParts([
        ErrorSummary('Shared preferences have not yet been preloaded.'),
        ErrorHint(
          'In the app, this is done by the `await AppLichessBinding.preloadSharedPreferences()` call '
          'in the `Future<void> main()` method.',
        ),
        ErrorHint(
          'In a test, one can call `TestLichessBinding.setInitialSharedPreferencesValues({})` as the '
          "first line in the test's `main()` method.",
        ),
      ]);
    }
    return _syncSharedPreferencesWithCache!;
  }

  static const String _kNumAppStartsKey = 'app_starts';

  @override
  int get numAppStarts => sharedPreferences.getInt(_kNumAppStartsKey) ?? 0;

  /// Read from the platform the app was built for rather than from `dart:io`, because that is what
  /// the engine plugins answer to as well: a flavour is compiled for a target platform or it is not
  /// there at all.
  ///
  /// Linux is the third case, and the one this fork adds: the `multistockfish` packages are built
  /// for it, which is the light Stockfish and Fairy-Stockfish — see [EngineAvailability.desktop] for
  /// why the other two are not.
  @override
  EngineAvailability get bundledEngines => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => EngineAvailability.phone,
    TargetPlatform.linux => EngineAvailability.desktop,
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.fuchsia => EngineAvailability.none,
  };

  /// Preload shared preferences.
  ///
  /// This should be called only once before the app starts. Must be called before
  /// [sharedPreferences] is accessed.
  Future<void> preloadSharedPreferences() async {
    _sharedPreferencesWithCache = SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    _syncSharedPreferencesWithCache = await _sharedPreferencesWithCache;

    final appStarts = sharedPreferences.getInt(_kNumAppStartsKey) ?? 0;
    sharedPreferences.setInt(_kNumAppStartsKey, appStarts + 1);
  }

  @override
  Future<void> initializeFirebase() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    if (kReleaseMode) {
      FlutterError.onError = firebaseCrashlytics.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        if (kDebugMode) {
          return false;
        } else {
          firebaseCrashlytics.recordError(error, stack);
          return true;
        }
      };
    }
  }

  @override
  FirebaseMessaging get firebaseMessaging => FirebaseMessaging.instance;

  @override
  FirebaseCrashlytics get firebaseCrashlytics => FirebaseCrashlytics.instance;

  @override
  void firebaseMessagingOnBackgroundMessage(BackgroundMessageHandler handler) {
    FirebaseMessaging.onBackgroundMessage(handler);
  }

  @override
  Stream<RemoteMessage> get firebaseMessagingOnMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get firebaseMessagingOnMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;
}
