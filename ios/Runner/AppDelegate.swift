// ios/Runner/AppDelegate.swift

import UIKit
import Flutter
import FirebaseCore
import FirebaseAppCheck

#if DEBUG
final class MWAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    return AppCheckDebugProvider(app: app)
  }
}
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "mw.voip"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // ---- Firebase config first ----
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
      print("[Firebase] configured")
    }

    // ---- App Check ----
    // Debug builds: use Debug provider so you can test easily
    // Release/TestFlight: DON'T set a factory here to avoid missing symbols.
    // Firebase will use the default provider configured for the app.
    #if DEBUG
    AppCheck.setAppCheckProviderFactory(MWAppCheckProviderFactory())
    #endif

    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.binaryMessenger
    )

    VoipPushManager.shared.setChannel(channel)
    VoipPushManager.shared.register()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
