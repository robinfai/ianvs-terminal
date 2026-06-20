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
  private struct NativeWindowDragState {
    let startFrameOrigin: NSPoint
    let startMouseLocation: NSPoint
  }

  private static let chromeBarHeight: CGFloat = 44
  private static let leadingWindowDragWidth: CGFloat = 132

  private var windowBridgeChannel: FlutterMethodChannel?
  private var hotkeyWindowController: HotkeyWindowController?
  private var trafficLightCenteringWorkItem: DispatchWorkItem?
  private var nativeWindowDragState: NativeWindowDragState?

  static func shouldStartNativeWindowDrag(
    at point: NSPoint,
    contentSize: NSSize,
    standardButtonFrames: [NSRect] = []
  ) -> Bool {
    guard contentSize.width > 0, contentSize.height > 0 else {
      return false
    }

    let dragWidth = min(leadingWindowDragWidth, contentSize.width)
    guard
      point.x >= 0,
      point.x <= dragWidth,
      point.y >= contentSize.height - chromeBarHeight,
      point.y <= contentSize.height
    else {
      return false
    }

    return !standardButtonFrames.contains { $0.contains(point) }
  }

  static func shouldStartNativeWindowDrag(
    atMouseLocation mouseLocation: NSPoint,
    windowFrame: NSRect,
    standardButtonFrames: [NSRect] = []
  ) -> Bool {
    guard windowFrame.width > 0, windowFrame.height > 0 else {
      return false
    }

    let xFromLeft = mouseLocation.x - windowFrame.minX
    let yFromTop = windowFrame.maxY - mouseLocation.y
    let dragWidth = min(leadingWindowDragWidth, windowFrame.width)
    guard
      xFromLeft >= 0,
      xFromLeft <= dragWidth,
      yFromTop >= 0,
      yFromTop <= chromeBarHeight
    else {
      return false
    }

    return !standardButtonFrames.contains { $0.contains(mouseLocation) }
  }

  static func nativeWindowDragOrigin(
    startFrameOrigin: NSPoint,
    startMouseLocation: NSPoint,
    currentMouseLocation: NSPoint
  ) -> NSPoint {
    NSPoint(
      x: startFrameOrigin.x + currentMouseLocation.x - startMouseLocation.x,
      y: startFrameOrigin.y + currentMouseLocation.y - startMouseLocation.y
    )
  }

  static func launchFrameInsideVisibleScreen(
    _ frame: NSRect,
    visibleFrame: NSRect
  ) -> NSRect {
    var nextFrame = frame
    if nextFrame.width > visibleFrame.width {
      nextFrame.size.width = visibleFrame.width
    }
    if nextFrame.height > visibleFrame.height {
      nextFrame.size.height = visibleFrame.height
    }
    nextFrame.origin.x = min(
      max(nextFrame.origin.x, visibleFrame.minX),
      visibleFrame.maxX - nextFrame.width
    )
    nextFrame.origin.y = min(
      max(nextFrame.origin.y, visibleFrame.minY),
      visibleFrame.maxY - nextFrame.height
    )
    return nextFrame
  }

  static func shouldOpenCommandSearchShortcut(_ event: NSEvent?) -> Bool {
    guard
      let event,
      event.type == .keyDown,
      event.charactersIgnoringModifiers?.lowercased() == "r"
    else {
      return false
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return flags == .command
  }

  static func shouldOrderFrontAfterAwake(isVisible: Bool) -> Bool {
    !isVisible
  }

  override func awakeFromNib() {
    AppDelegate.registerMainWindowForActivation(self)
    let flutterViewController = FlutterViewController()
    let windowFrame = launchFrameForCurrentEnvironment(self.frame)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovable = false
    self.isMovableByWindowBackground = false
    self.isRestorable = false
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
      case "windowMetrics":
        var metrics: [String: Any] = [
          "frameWidth": Double(self.frame.size.width),
          "frameHeight": Double(self.frame.size.height),
          "devicePixelRatio": Double(self.backingScaleFactor)
        ]
        if let contentSize = self.contentView?.bounds.size {
          metrics["contentWidth"] = Double(contentSize.width)
          metrics["contentHeight"] = Double(contentSize.height)
        }
        result(metrics)
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
    if Self.shouldOrderFrontAfterAwake(isVisible: isVisible) {
      DispatchQueue.main.async { [weak self] in
        guard let self else {
          return
        }
        NSApp.activate(ignoringOtherApps: true)
        self.orderFrontRegardless()
        self.makeKeyAndOrderFront(nil)
      }
    }
  }

  private func launchFrameForCurrentEnvironment(_ frame: NSRect) -> NSRect {
    guard
      ProcessInfo.processInfo.environment["IANVS_FORCE_MAIN_SCREEN_WINDOW"] == "1",
      let visibleFrame = NSScreen.main?.visibleFrame
    else {
      return frame
    }
    return Self.launchFrameInsideVisibleScreen(frame, visibleFrame: visibleFrame)
  }

  deinit {
    trafficLightCenteringWorkItem?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(frameRect, display: flag)
    scheduleTrafficLightCentering()
  }

  override func sendEvent(_ event: NSEvent) {
    if Self.shouldOpenCommandSearchShortcut(event) {
      openNativeCommandSearch()
      return
    }

    let eventMouseLocation = convertPoint(toScreen: event.locationInWindow)
    switch event.type {
    case .leftMouseDown where shouldStartNativeWindowDrag(
      atMouseLocation: eventMouseLocation
    ):
      nativeWindowDragState = NativeWindowDragState(
        startFrameOrigin: frame.origin,
        startMouseLocation: eventMouseLocation
      )
      return
    case .leftMouseDragged:
      if let dragState = nativeWindowDragState {
        setFrameOrigin(
          Self.nativeWindowDragOrigin(
            startFrameOrigin: dragState.startFrameOrigin,
            startMouseLocation: dragState.startMouseLocation,
            currentMouseLocation: eventMouseLocation
          )
        )
        return
      }
    case .leftMouseUp:
      if nativeWindowDragState != nil {
        nativeWindowDragState = nil
        return
      }
    default:
      break
    }

    super.sendEvent(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if Self.shouldOpenCommandSearchShortcut(event) {
      openNativeCommandSearch()
      return true
    }
    return super.performKeyEquivalent(with: event)
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

  @objc func performFindPanelAction(_ sender: Any?) {
    let tag = (sender as? NSMenuItem)?.tag ?? 1
    windowBridgeChannel?.invokeMethod("nativeFind", arguments: ["tag": tag])
  }

  private func openNativeCommandSearch() {
    windowBridgeChannel?.invokeMethod("nativeCommandSearch", arguments: nil)
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

  private func shouldStartNativeWindowDrag(atMouseLocation mouseLocation: NSPoint) -> Bool {
    Self.shouldStartNativeWindowDrag(
      atMouseLocation: mouseLocation,
      windowFrame: frame,
      standardButtonFrames: standardWindowButtonFramesInScreenCoordinates()
    )
  }

  private func standardWindowButtonFramesInWindowCoordinates() -> [NSRect] {
    [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton
    ].compactMap { buttonType in
      guard
        let button = standardWindowButton(buttonType),
        !button.isHidden
      else {
        return nil
      }
      return button.convert(button.bounds, to: nil)
    }
  }

  private func standardWindowButtonFramesInScreenCoordinates() -> [NSRect] {
    standardWindowButtonFramesInWindowCoordinates().map { convertToScreen($0) }
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

  func notificationAuthorizationFailedError(message: String) -> FlutterError {
    FlutterError(
      code: "notification_authorization_failed",
      message: message,
      details: nil
    )
  }
}
