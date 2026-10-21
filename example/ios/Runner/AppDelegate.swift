import AVFoundation
import Speech
import CoreFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var voiceInput: TrailVoiceInput?
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
