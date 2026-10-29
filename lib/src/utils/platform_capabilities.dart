import 'package:flutter/foundation.dart';

/// Capabilities of the native integrations shipped by this app, not its screen form factor.
///
/// A desktop window can be phone-sized without gaining Android/iOS plugin implementations.
bool get _mobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

bool get supportsFirebaseMessaging => _mobile;
bool get supportsFirebaseCrashlytics =>
    _mobile || (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);
bool get supportsQuickActions => _mobile;
bool get supportsIncomingPgnShare => _mobile;
bool get supportsHomeWidgets => _mobile;
