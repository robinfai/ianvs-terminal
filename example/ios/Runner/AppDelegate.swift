import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  #if targetEnvironment(simulator)
  private var simulatorAcceptanceChannel: FlutterMethodChannel?
  #endif

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    #if targetEnvironment(simulator)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "IanvsSimulatorAcceptance"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "dev.ianvs.terminal/simulator-acceptance",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "readLaunchConfiguration" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let environment = ProcessInfo.processInfo.environment
      result([
        "IANVS_SIMULATOR_CREDENTIALS_URL": environment["IANVS_SIMULATOR_CREDENTIALS_URL"] ?? "",
        "IANVS_SIMULATOR_REMOTE_API_URL": environment["IANVS_SIMULATOR_REMOTE_API_URL"] ?? "",
      ])
    }
    simulatorAcceptanceChannel = channel
    #endif
  }
}
