import Cocoa
import Carbon.HIToolbox
import FlutterMacOS
import UserNotifications

private final class HotkeyWindowController {
  static let shortcutLabel = "⌥⌘Space"

  private static let hotkeySignature = fourCharCode("FLTM")
  private static let hotkeyId = UInt32(1)
  private static let keyCode = UInt32(kVK_Space)
  private static let keyModifiers = UInt32(cmdKey | optionKey)

  private weak var window: NSWindow?
  private var hotkeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private(set) var registrationError: OSStatus?

  var isRegistered: Bool {
    hotkeyRef != nil
  }

  init(window: NSWindow) {
    self.window = window
  }

  deinit {
    unregister()
  }

  func register() {
    guard hotkeyRef == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else {
          return noErr
        }
        let controller = Unmanaged<HotkeyWindowController>
          .fromOpaque(userData)
          .takeUnretainedValue()
        controller.handleHotkeyEvent(event)
        return noErr
      },
      1,
      &eventType,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &eventHandlerRef
    )
    guard handlerStatus == noErr else {
      registrationError = handlerStatus
      return
    }

    let hotkeyId = EventHotKeyID(
      signature: Self.hotkeySignature,
      id: Self.hotkeyId
    )
    let hotkeyStatus = RegisterEventHotKey(
      Self.keyCode,
      Self.keyModifiers,
      hotkeyId,
      GetApplicationEventTarget(),
      0,
      &hotkeyRef
    )
    if hotkeyStatus != noErr {
      registrationError = hotkeyStatus
      if let eventHandlerRef {
        RemoveEventHandler(eventHandlerRef)
      }
      eventHandlerRef = nil
      hotkeyRef = nil
      return
    }

    registrationError = nil
  }

  func unregister() {
    if let hotkeyRef {
      UnregisterEventHotKey(hotkeyRef)
    }
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
    hotkeyRef = nil
    eventHandlerRef = nil
  }

  func toggleWindow() {
    DispatchQueue.main.async { [weak self] in
      guard let self, let window = self.window else {
        return
      }

      if window.isMiniaturized {
        window.deminiaturize(nil)
      }

      if window.isVisible && NSApp.isActive {
        AppDelegate.suppressNextLastWindowTerminate = true
        window.orderOut(nil)
        return
      }

      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func handleHotkeyEvent(_ event: EventRef?) {
    var hotkeyId = EventHotKeyID()
    guard
      let event,
      GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyId
      ) == noErr,
      hotkeyId.signature == Self.hotkeySignature,
      hotkeyId.id == Self.hotkeyId
    else {
      return
    }

    toggleWindow()
  }
}

private func fourCharCode(_ value: String) -> OSType {
  var result: OSType = 0
  for scalar in value.unicodeScalars.prefix(4) {
    result = (result << 8) + OSType(scalar.value)
  }
  return result
}

class MainFlutterWindow: NSWindow {
  private static let chromeBarHeight: CGFloat = 44

  private var windowBridgeChannel: FlutterMethodChannel?
  private var hotkeyWindowController: HotkeyWindowController?
  private var trafficLightCenteringWorkItem: DispatchWorkItem?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovable = false
    self.isMovableByWindowBackground = false
    self.styleMask.insert(.fullSizeContentView)
    observeTrafficLightLayoutChanges()

    RegisterGeneratedPlugins(registry: flutterViewController)
    windowBridgeChannel = FlutterMethodChannel(
      name: "app/window_bridge",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    bindNativePasteMenuItems()
    hotkeyWindowController = HotkeyWindowController(window: self)
    hotkeyWindowController?.register()
    windowBridgeChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "window_unavailable",
            message: "Main window is unavailable",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "resizeBy":
        guard
          let arguments = call.arguments as? [String: Any],
          let widthDelta = arguments["widthDelta"] as? Double,
          let heightDelta = arguments["heightDelta"] as? Double
        else {
          result(FlutterMethodNotImplemented)
          return
        }

        var nextFrame = self.frame
        nextFrame.size.width += CGFloat(widthDelta)
        nextFrame.size.height += CGFloat(heightDelta)
        nextFrame.origin.y -= CGFloat(heightDelta)
        self.setFrame(nextFrame, display: true)
        result(nil)
      case "setTitle":
        guard
          let arguments = call.arguments as? [String: Any],
          let title = arguments["title"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }

        self.title = title
        result(nil)
      case "requestQuitConfirmation":
        NSApp.terminate(nil)
        result(nil)
      case "beginWindowDrag":
        if let event = NSApp.currentEvent {
          let wasMovable = self.isMovable
          self.isMovable = true
          self.performDrag(with: event)
          self.isMovable = wasMovable
        }
        result(nil)
      case "toggleHotkeyWindow":
        self.hotkeyWindowController?.toggleWindow()
        result(nil)
      case "hotkeyStatus":
        var status: [String: Any] = [
          "registered": self.hotkeyWindowController?.isRegistered ?? false,
          "shortcut": HotkeyWindowController.shortcutLabel
        ]
        if let error = self.hotkeyWindowController?.registrationError {
          status["errorCode"] = Int(error)
        }
        result(status)
      case "openExternalUrl":
        guard
          let arguments = call.arguments as? [String: Any],
          let rawUrl = arguments["url"] as? String,
          let url = URL(string: rawUrl)
        else {
          result(
            FlutterError(
              code: "invalid_url",
              message: "External URL is missing or invalid",
              details: nil
            )
          )
          return
        }

        NSWorkspace.shared.open(url)
        result(nil)
      case "showNotification":
        self.showNotification(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
    scheduleTrafficLightCentering()
  }

  deinit {
    trafficLightCenteringWorkItem?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(frameRect, display: flag)
    scheduleTrafficLightCentering()
  }

  override func becomeKey() {
    super.becomeKey()
    scheduleTrafficLightCentering()
  }

  @objc func paste(_ sender: Any?) {
    windowBridgeChannel?.invokeMethod("nativePaste", arguments: nil)
  }

  @objc func pasteAsPlainText(_ sender: Any?) {
    windowBridgeChannel?.invokeMethod("nativePaste", arguments: nil)
  }

  private func bindNativePasteMenuItems() {
    guard let mainMenu = NSApp.mainMenu else {
      return
    }
    for item in mainMenu.items {
      guard item.title == "Edit", let editMenu = item.submenu else {
        continue
      }
      for editItem in editMenu.items {
        switch editItem.title {
        case "Paste":
          editItem.target = self
          editItem.action = #selector(paste(_:))
        case "Paste and Match Style":
          editItem.target = self
          editItem.action = #selector(pasteAsPlainText(_:))
        default:
          continue
        }
      }
    }
  }

  private func observeTrafficLightLayoutChanges() {
    let notifications: [NSNotification.Name] = [
      NSWindow.didResizeNotification,
      NSWindow.didMoveNotification,
      NSWindow.didChangeScreenNotification,
      NSWindow.didChangeBackingPropertiesNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification,
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification
    ]
    for notification in notifications {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleTrafficLightLayoutChange(_:)),
        name: notification,
        object: self
      )
    }
  }

  @objc private func handleTrafficLightLayoutChange(_ notification: Notification) {
    scheduleTrafficLightCentering()
  }

  private func scheduleTrafficLightCentering() {
    trafficLightCenteringWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.centerTrafficLightButtonsInChromeBar()
    }
    trafficLightCenteringWorkItem = workItem
    DispatchQueue.main.async(execute: workItem)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
      guard let self, self.trafficLightCenteringWorkItem === workItem else {
        return
      }
      self.centerTrafficLightButtonsInChromeBar()
    }
  }

  private func centerTrafficLightButtonsInChromeBar() {
    let buttons = [
      standardWindowButton(.closeButton),
      standardWindowButton(.miniaturizeButton),
      standardWindowButton(.zoomButton)
    ].compactMap { $0 }
    guard let buttonSuperview = buttons.first?.superview else {
      return
    }

    for button in buttons {
      var frame = button.frame
      frame.origin.y =
        buttonSuperview.bounds.height -
        Self.chromeBarHeight +
        (Self.chromeBarHeight - frame.height) / 2
      button.setFrameOrigin(frame.origin)
    }
  }

  private func showNotification(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let title = arguments["title"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_notification",
          message: "Notification title is required",
          details: nil
        )
      )
      return
    }

    let body = arguments["body"] as? String
    let identifier = arguments["identifier"] as? String ?? UUID().uuidString
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      if let error {
        DispatchQueue.main.async {
          result(self.notificationAuthorizationFailedError(message: error.localizedDescription))
        }
        return
      }
      guard granted else {
        DispatchQueue.main.async {
          result(
            self.notificationAuthorizationFailedError(
              message: "Notifications are disabled for Ianvs Terminal in System Settings."
            )
          )
        }
        return
      }

      let content = UNMutableNotificationContent()
      content.title = title
      if let body, !body.isEmpty {
        content.body = body
      }
      content.sound = .default

      let request = UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: nil
      )
      center.add(request) { error in
        DispatchQueue.main.async {
          if let error {
            result(
              FlutterError(
                code: "notification_delivery_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
            return
          }
          result(nil)
        }
      }
    }
  }

  fileprivate func notificationAuthorizationFailedError(message: String) -> FlutterError {
    FlutterError(
      code: "notification_authorization_failed",
      message: message,
      details: nil
    )
  }
}
