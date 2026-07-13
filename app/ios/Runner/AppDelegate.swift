import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The App Intent (Action button / Siri) leaves an action in UserDefaults. Flutter asks
    // for it on launch and on resume; reading clears it, so an ordinary resume gets nothing.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DaybyIntents")
    else { return }
    let channel = FlutterMethodChannel(
      name: "dev.hojoong.dayby/intents",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "consumePendingAction" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let defaults = UserDefaults.standard
      let action = defaults.string(forKey: pendingActionKey)
      defaults.removeObject(forKey: pendingActionKey)
      result(action)
    }
  }
}
