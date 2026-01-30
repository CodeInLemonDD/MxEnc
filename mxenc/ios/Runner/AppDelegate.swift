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
    guard let window = window, secureField == nil else { return }
    
    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.translatesAutoresizingMaskIntoConstraints = false
    
    // 找到安全容器视图（通常是 _UITextFieldCanvasView）
    let canvas = field.subviews.first { NSStringFromClass($0.classForCoder).contains("Canvas") }
    guard let secureContainer = canvas ?? field.subviews.first else { return }
    
    // 强制更新布局以确保容器可用
    field.layoutIfNeeded()
    
    window.addSubview(field)
    
    // 将根控制器的视图移入安全容器
    if let rootViewController = window.rootViewController {
        let flutterView = rootViewController.view!
        secureContainer.addSubview(flutterView)
        
        flutterView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            flutterView.topAnchor.constraint(equalTo: window.topAnchor),
            flutterView.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            flutterView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            flutterView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            field.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            field.centerYAnchor.constraint(equalTo: window.centerYAnchor)
        ])
    }
    
    secureField = field
  }

  private func makeInsecure() {
    guard let field = secureField, let window = window else { return }
    
    // Robustly restore the view:
    // We grab the reference from rootViewController directly, ensuring we get the correct instance
    // regardless of where it currently resides in the view hierarchy.
    if let flutterView = window.rootViewController?.view {
        flutterView.removeFromSuperview() // Detach from secure container
        window.addSubview(flutterView)    // Re-attach to window
        
        // Reset constraints and layout
        flutterView.translatesAutoresizingMaskIntoConstraints = true
        flutterView.frame = window.bounds
        
        window.layoutIfNeeded()
    }
    
    field.removeFromSuperview()
    secureField = nil
  }
}
