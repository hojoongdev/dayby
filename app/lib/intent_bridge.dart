import 'package:flutter/services.dart';

/// The bridge to the iOS App Intent behind the Action button and Siri. When the button
/// opens the app, the native side leaves an action in UserDefaults; this reads and clears
/// it. Anywhere the channel is not wired -- Android, web, tests -- it just returns null.
class IntentBridge {
  const IntentBridge();

  static const _channel = MethodChannel('dev.hojoong.dayby/intents');

  /// The action the app was opened to perform, or null. Reading it clears it, so a resume
  /// that was not from the button returns null the next time.
  Future<String?> takePendingAction() async {
    try {
      return await _channel.invokeMethod<String>('consumePendingAction');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
