import AVFoundation
import Speech
import StoreKit
import CoreFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var fileExport: TrailFileExport?
  private var aiPurchases: TrailAiPurchases?
  private var voiceInput: TrailVoiceInput?
  private var externalUrlChannel: FlutterMethodChannel?
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailAiPurchases") {
      aiPurchases = TrailAiPurchases(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailFileExport") {
      fileExport = TrailFileExport(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailVoiceInput") {
      voiceInput = TrailVoiceInput(messenger: registrar.messenger())
    }
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailExternalUrl") {
      let channel = FlutterMethodChannel(
        name: "app/window_bridge",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "setPageBackground",
           let args = call.arguments as? [String: Any], let argb = args["argb"] as? NSNumber {
          let value = argb.uint32Value
          let color = UIColor(red: CGFloat((value >> 16) & 255) / 255,
                              green: CGFloat((value >> 8) & 255) / 255,
                              blue: CGFloat(value & 255) / 255,
                              alpha: CGFloat((value >> 24) & 255) / 255)
          for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
              window.backgroundColor = color
              window.rootViewController?.view.backgroundColor = color
              window.overrideUserInterfaceStyle = (args["dark"] as? Bool == true) ? .dark : .light
            }
          }
          result(nil)
          return
        }
        guard call.method == "openExternalUrl" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let arguments = call.arguments as? [String: Any],
              let raw = arguments["url"] as? String,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme),
              scheme == "file" || !(url.host ?? "").isEmpty else {
          result(FlutterError(code: "invalid_url", message: nil, details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened ? nil : FlutterError(code: "open_url_failed", message: nil, details: nil))
        }
      }
      externalUrlChannel = channel
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

/// Owns one hold-to-dictate session, including permission and teardown races.
private final class TrailVoiceInput {
  private let channel: FlutterMethodChannel
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var completion: FlutterResult?
  private var sessionId: Int?
  private var transcript = ""
  private var tapped = false
  private var audioActive = false
  private var timeout: DispatchWorkItem?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app/voice_input", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self,
            let args = call.arguments as? [String: Any],
            let id = args["id"] as? Int else {
        result(FlutterError(code: "invalid_request", message: nil, details: nil))
        return
      }
      switch call.method {
      case "start":
        self.finish(nil)
        self.sessionId = id
        self.completion = result
        self.authorize(id: id, locale: args["locale"] as? String ?? Locale.current.identifier)
      case "stop":
        if self.sessionId == id {
          if self.request == nil {
            // Finger released during permission UI: never start recording later.
            self.finish(nil)
          } else {
            self.stopAudio()
            self.request?.endAudio()
            self.scheduleFinish(after: 3, id: id)
          }
        }
        result(nil)
      case "cancel":
        if self.sessionId == id { self.finish(nil) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    for name in [UIApplication.didEnterBackgroundNotification,
                 AVAudioSession.interruptionNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in self?.finish(nil) })
    }
  }

  private func authorize(id: Int, locale: String) {
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      DispatchQueue.main.async {
        guard let self, self.sessionId == id else { return }
        guard status == .authorized else { self.fail("permission_denied"); return }
        AVAudioApplication.requestRecordPermission { [weak self] allowed in
          DispatchQueue.main.async {
            guard let self, self.sessionId == id else { return }
            guard allowed else { self.fail("permission_denied"); return }
            self.startAudio(id: id, locale: locale)
          }
        }
      }
    }
  }

  private func startAudio(id: Int, locale: String) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
          recognizer.isAvailable else { fail("unavailable"); return }
    self.recognizer = recognizer
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true)
      audioActive = true
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
      self.request = request
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        fail("unavailable")
        return
      }
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
      }
      tapped = true
      task = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
        DispatchQueue.main.async {
          guard let self, self.sessionId == id else { return }
          if let recognition { self.transcript = recognition.bestTranscription.formattedString }
          if recognition?.isFinal == true {
            self.finish(self.transcript)
          } else if error != nil {
            self.fail("recognition_failed")
          }
        }
      }
      engine.prepare()
      try engine.start()
      scheduleFinish(after: 55, id: id)
    } catch {
      fail("audio_unavailable")
    }
  }

  private func scheduleFinish(after seconds: Double, id: Int) {
    timeout?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.sessionId == id else { return }
      self.finish(self.transcript)
    }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  private func stopAudio() {
    engine.stop()
    if tapped {
      engine.inputNode.removeTap(onBus: 0)
      tapped = false
    }
    if audioActive {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      audioActive = false
    }
  }

  private func fail(_ code: String) {
    finish(FlutterError(code: code, message: nil, details: nil))
  }

  private func finish(_ value: Any?) {
    let result = completion
    completion = nil
    sessionId = nil
    timeout?.cancel()
    timeout = nil
    stopAudio()
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    recognizer = nil
    transcript = ""
    result?(value)
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    finish(nil)
  }
}

private final class TrailFileExport: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app/file_export", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "export",
            let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented); return
      }
      guard self.pending == nil else {
        result(FlutterError(code: "busy", message: "File export is already open", details: nil)); return
      }
      guard FileManager.default.fileExists(atPath: path),
            var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
              .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
        result(FlutterError(code: "unavailable", message: "Cannot export file", details: nil)); return
      }
      while let presented = presenter.presentedViewController { presenter = presented }
      self.pending = result
      let picker = UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: path)], asCopy: true)
      picker.delegate = self
      presenter.present(picker, animated: true)
    }
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    pending?(!urls.isEmpty); pending = nil
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(false); pending = nil
  }
}

/// StoreKit owns unfinished transactions until the backend confirms delivery.
/// This bridge never grants quota and never finishes a purchase on receipt alone.
@MainActor
private final class TrailAiPurchases {
  private let channel: FlutterMethodChannel
  private var products: [String: Product] = [:]
  private var transactions: [UInt64: StoreKit.Transaction] = [:]
  private var updates: Task<Void, Never>?
  private var purchasing = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app/ai_purchases", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor [weak self] in
        guard let self else { return }
        do { try await self.handle(call, result: result) }
        catch { result(FlutterError(code: "store_unavailable", message: "App Store is unavailable. Please retry.", details: nil)) }
      }
    }
    updates = Task { [weak self] in
      for await update in StoreKit.Transaction.updates {
        guard let self else { return }
        if case .verified(let transaction) = update {
          self.transactions[transaction.id] = transaction
          self.channel.invokeMethod("transactionsChanged", arguments: nil)
        }
      }
    }
  }

  private func value(_ transaction: StoreKit.Transaction) -> [String: Any] {
    ["transaction_id": String(transaction.id), "product_id": transaction.productID,
     "app_account_token": transaction.appAccountToken?.uuidString.lowercased() ?? ""]
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async throws {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "products":
      let ids = args["ids"] as? [String] ?? []
      let found = try await Product.products(for: ids)
      products = Dictionary(uniqueKeysWithValues: found.filter { $0.type == .consumable }.map { ($0.id, $0) })
      result(products.values.sorted { $0.price < $1.price }.map {
        ["id": $0.id, "title": $0.displayName, "price": $0.displayPrice]
      })
    case "purchase":
      guard !purchasing else { result(FlutterError(code: "purchase_busy", message: nil, details: nil)); return }
      guard AppStore.canMakePayments,
            let id = args["product_id"] as? String, let product = products[id],
            let rawToken = args["app_account_token"] as? String, let token = UUID(uuidString: rawToken) else {
        result(FlutterError(code: "purchase_unavailable", message: nil, details: nil)); return
      }
      purchasing = true
      defer { purchasing = false }
      switch try await product.purchase(options: [.appAccountToken(token)]) {
      case .success(let verification):
        guard case .verified(let transaction) = verification else {
          result(FlutterError(code: "purchase_unverified", message: nil, details: nil)); return
        }
        transactions[transaction.id] = transaction
        result(["status": "purchased", "transaction": value(transaction)])
      case .pending: result(["status": "pending"])
      case .userCancelled: result(["status": "cancelled"])
      @unknown default: result(["status": "pending"])
      }
    case "unfinished":
      for await verification in StoreKit.Transaction.unfinished {
        if case .verified(let transaction) = verification { transactions[transaction.id] = transaction }
      }
      result(transactions.values.filter { $0.productType == .consumable }.map(value))
    case "finish":
      guard let raw = args["transaction_id"] as? String, let id = UInt64(raw),
            let transaction = transactions[id] else {
        result(FlutterError(code: "transaction_missing", message: nil, details: nil)); return
      }
      await transaction.finish()
      transactions.removeValue(forKey: id)
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
  deinit { updates?.cancel() }
}
