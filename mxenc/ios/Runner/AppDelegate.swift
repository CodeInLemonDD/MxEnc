import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.maoxiao.mxenc/secure", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "enableSecureScreen":
        if #available(iOS 11.0, *) {
          controller.view.window?.isHidden = false
        }
        if #available(iOS 13.0, *) {
          controller.view.window?.isSecureTextEntry = true
        }
        controller.view.window?.makeKeyAndVisible()
        controller.view.window?.screen.capturedDidChangeNotification
        controller.view.window?.isHidden = false
        if #available(iOS 11.0, *) {
          controller.view.window?.isSecureTextEntry = true
        }
        result(nil)
      case "disableSecureScreen":
        if #available(iOS 13.0, *) {
          controller.view.window?.isSecureTextEntry = false
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
