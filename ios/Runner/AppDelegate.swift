// ios/Runner/AppDelegate.swift

import UIKit
import Flutter
import FirebaseCore
import FirebaseAppCheck

#if DEBUG
final class MWAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    AppCheckDebugProvider(app: app)
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

    #if DEBUG
    AppCheck.setAppCheckProviderFactory(MWAppCheckProviderFactory())
    #endif

    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
      print("[Firebase] configured")
    }

    let result = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: controller.binaryMessenger
      )

      VoipPushManager.shared.setChannel(channel)
      VoipPushManager.shared.register()
      print("[VoIP] channel attached and registration started")
    } else {
      print("[VoIP] FlutterViewController not available at launch")
    }

    return result
  }
}