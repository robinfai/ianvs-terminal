import CoreFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var buildIdentityChannel: FlutterMethodChannel?
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailBuildIdentity") {
      let channel = FlutterMethodChannel(
        name: "app/build_identity",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "readIdentity" else {
          result(FlutterMethodNotImplemented)
          return
        }
        var deviceLocalMasterKey = false
        if let marker = Bundle.main.object(
          forInfoDictionaryKey: "TrailPrdDeviceLocalMasterKey"
        ) as? NSNumber {
          deviceLocalMasterKey = CFGetTypeID(marker) == CFBooleanGetTypeID() && marker.boolValue
        }
        result([
          "bundleId": Bundle.main.bundleIdentifier ?? "",
          "deviceLocalMasterKey": deviceLocalMasterKey,
        ])
      }
      buildIdentityChannel = channel
    }
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
