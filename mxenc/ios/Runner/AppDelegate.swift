import Flutter
import UIKit

// 声明 Rust 函数
@_silgen_name("dummy_method_to_enforce_bundling")
func dummyMethodToEnforceBundling()

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 调用以确保符号不被剥离
    dummyMethodToEnforceBundling()
    
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.maoxiao.mxenc/secure", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enableSecureScreen":
        self?.makeSecure(window: controller.view.window)
        result(nil)
      case "disableSecureScreen":
        self?.makeInsecure()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let fileChannel = FlutterMethodChannel(name: "com.maoxiao.mxenc/file_utils", binaryMessenger: controller.binaryMessenger)
    fileChannel.setMethodCallHandler { call, result in
      if call.method == "copyContentUri" {
        // iOS 主要是 file:// 路径，这里返回原路径或者根据需要实现拷贝逻辑
        // 目前返回 nil 或者原路径以保持接口兼容
        let args = call.arguments as? [String: Any]
        let uri = args?["uri"] as? String
        result(uri)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var secureField: UITextField?

  private func makeSecure(window: UIWindow?) {
    guard let window = window else { return }
    if secureField == nil {
      let field = UITextField()
      field.isSecureTextEntry = true
      window.addSubview(field)
      window.layer.superlayer?.addSublayer(field.layer)
      field.layer.sublayers?.last?.addSublayer(window.layer)
      secureField = field
    }
  }

  private func makeInsecure() {
    secureField?.removeFromSuperview()
    secureField = nil
  }
}
