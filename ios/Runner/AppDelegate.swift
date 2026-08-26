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

    // 注册 AR 量尺平台视图（ar_measure_view）。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ArMeasureViewPlugin") {
      registrar.register(
        ArMeasureViewFactory(messenger: registrar.messenger()),
        withId: "ar_measure_view")
    }
  }
}
