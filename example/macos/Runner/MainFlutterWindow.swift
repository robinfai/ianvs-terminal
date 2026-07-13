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

  private struct Osc72DropTarget {
    let sessionId: String
    let mimeTypes: [String]
  }

  private struct Osc72DropPayload {
    let mimeTypes: [String]
    let dataByMimeType: [String: Data]
  }

  private static let chromeBarHeight: CGFloat = 44
  private static let leadingWindowDragWidth: CGFloat = 132
  private static let maxOsc72DropBytes = 64 * 1024 * 1024
  private static let mimePasteboardTypePrefix = "dev.ianvs.terminal.mime."

  private var windowBridgeChannel: FlutterMethodChannel?
  private var hotkeyWindowController: HotkeyWindowController?
  private var trafficLightCenteringWorkItem: DispatchWorkItem?
  private var notificationExpiryWorkItems: [String: DispatchWorkItem] = [:]
  private var nativeWindowDragState: NativeWindowDragState?
  private var osc72DropTarget: Osc72DropTarget?
  private var osc72DropPayloads: [String: Osc72DropPayload] = [:]
  private var osc72DropDecision: NSDragOperation = []

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

  static func pasteboardType(forMime mime: String) -> NSPasteboard.PasteboardType {
    switch mime.lowercased() {
    case "text/plain": return .string
    case "text/html": return .html
    case "text/rtf": return .rtf
    case "image/png": return .png
    case "image/tiff": return .tiff
    default:
      let encoded = mime.utf8.map { String(format: "%02x", $0) }.joined()
      return NSPasteboard.PasteboardType(mimePasteboardTypePrefix + encoded)
    }
  }

  static func mime(forPasteboardType type: NSPasteboard.PasteboardType) -> String {
    switch type {
    case .string: return "text/plain"
    case .html: return "text/html"
    case .rtf: return "text/rtf"
    case .png: return "image/png"
    case .tiff: return "image/tiff"
    default:
      if type.rawValue.hasPrefix(mimePasteboardTypePrefix) {
        let encoded = type.rawValue.dropFirst(mimePasteboardTypePrefix.count)
        guard encoded.count.isMultiple(of: 2) else { return type.rawValue.lowercased() }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(encoded.count / 2)
        var index = encoded.startIndex
        while index < encoded.endIndex {
          let next = encoded.index(index, offsetBy: 2)
          guard let byte = UInt8(encoded[index..<next], radix: 16) else {
            return type.rawValue.lowercased()
          }
          bytes.append(byte)
          index = next
        }
        return String(bytes: bytes, encoding: .utf8) ?? type.rawValue.lowercased()
      }
      switch type.rawValue.lowercased() {
      case "nsstringpboardtype": return "text/plain"
      case "apple png pasteboard type": return "image/png"
      case "next tiff v4.0 pasteboard type": return "image/tiff"
      default: return type.rawValue.lowercased()
      }
    }
  }

  static func isMimeType(_ value: String) -> Bool {
    let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.count <= 127 }
  }

  static func mimePattern(_ pattern: String, matches mime: String) -> Bool {
    if pattern == "*/*" { return true }
    let patternParts = pattern.split(separator: "/", maxSplits: 1).map(String.init)
    let mimeParts = mime.split(separator: "/", maxSplits: 1).map(String.init)
    guard patternParts.count == 2, mimeParts.count == 2 else { return pattern == mime }
    return (patternParts[0] == "*" || patternParts[0] == mimeParts[0])
      && (patternParts[1] == "*" || patternParts[1] == mimeParts[1])
  }

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

        let allowedSchemes: Set<String> = ["http", "https", "file"]
        guard
          let scheme = url.scheme?.lowercased(),
          allowedSchemes.contains(scheme),
          (scheme == "file" ? !url.path.isEmpty : url.host != nil)
        else {
          result(
            FlutterError(
              code: "unsupported_url_scheme",
              message: "External URL scheme is not allowed",
              details: nil
            )
          )
          return
        }

        if !NSWorkspace.shared.open(url) {
          result(
            FlutterError(
              code: "open_failed",
              message: "macOS could not open the URL",
              details: rawUrl
            )
          )
          return
        }
        result(nil)
      case "showNotification":
        self.showNotification(arguments: call.arguments, result: result)
      case "closeNotification":
        self.closeNotification(arguments: call.arguments, result: result)
      case "configureOsc72DropTarget":
        self.configureOsc72DropTarget(arguments: call.arguments, result: result)
      case "setOsc72DropDecision":
        self.setOsc72DropDecision(arguments: call.arguments, result: result)
      case "readOsc72DropData":
        self.readOsc72DropData(arguments: call.arguments, result: result)
      case "releaseOsc72Drop":
        self.releaseOsc72Drop(arguments: call.arguments, result: result)
      case "osc72DropTargetStatus":
        result([
          "enabled": self.osc72DropTarget != nil,
          "sessionId": (self.osc72DropTarget?.sessionId as Any?) ?? NSNull(),
          "mimeTypes": self.osc72DropTarget?.mimeTypes ?? [],
          "decision": Self.osc72OperationMask(self.osc72DropDecision),
          "cachedDrops": self.osc72DropPayloads.count
        ])
      case "writeClipboardMime":
        self.writeClipboardMime(arguments: call.arguments, result: result)
      case "writeClipboardText":
        self.writeClipboardText(arguments: call.arguments, result: result)
      case "readClipboardMime":
        self.readClipboardMime(arguments: call.arguments, result: result)
      case "listClipboardMimeTypes":
        result(Self.clipboardMimeTypes(NSPasteboard.general))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
    scheduleTrafficLightCentering()
  }

  deinit {
    trafficLightCenteringWorkItem?.cancel()
    for workItem in notificationExpiryWorkItems.values {
      workItem.cancel()
    }
    notificationExpiryWorkItems.removeAll()
    osc72DropPayloads.removeAll()
    NotificationCenter.default.removeObserver(self)
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(frameRect, display: flag)
    scheduleTrafficLightCentering()
  }

  override func sendEvent(_ event: NSEvent) {
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

  override func becomeKey() {
    super.becomeKey()
    scheduleTrafficLightCentering()
  }

  @objc func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    osc72DropDecision = []
    reportOsc72DragEvent(sender, phase: "move")
    return []
  }

  @objc func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    reportOsc72DragEvent(sender, phase: "move")
    return supportedOsc72Operation(sender.draggingSourceOperationMask)
  }

  @objc func draggingExited(_ sender: (any NSDraggingInfo)?) {
    guard let target = osc72DropTarget else {
      return
    }
    windowBridgeChannel?.invokeMethod(
      "osc72DragEvent",
      arguments: [
        "phase": "leave",
        "sessionId": target.sessionId,
        "mimeTypes": [String](),
        "x": -1.0,
        "y": -1.0,
        "operations": 0
      ]
    )
    osc72DropDecision = []
  }

  @objc func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard
      let target = osc72DropTarget,
      !supportedOsc72Operation(sender.draggingSourceOperationMask).isEmpty,
      let payload = captureOsc72DropPayload(sender.draggingPasteboard, target: target)
    else {
      return false
    }
    let dropId = UUID().uuidString
    osc72DropPayloads[dropId] = payload
    reportOsc72DragEvent(sender, phase: "drop", dropId: dropId, mimeTypes: payload.mimeTypes)
    return true
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

  private func configureOsc72DropTarget(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let arguments = arguments as? [String: Any] else {
      result(FlutterMethodNotImplemented)
      return
    }
    let enabled = arguments["enabled"] as? Bool ?? false
    guard enabled else {
      unregisterDraggedTypes()
      osc72DropTarget = nil
      osc72DropDecision = []
      osc72DropPayloads.removeAll()
      result(nil)
      return
    }
    guard
      let sessionId = arguments["sessionId"] as? String,
      !sessionId.isEmpty,
      let rawMimeTypes = arguments["mimeTypes"] as? [String]
    else {
      result(
        FlutterError(
          code: "invalid_osc72_target",
          message: "OSC 72 target session and MIME types are required",
          details: nil
        )
      )
      return
    }
    let mimeTypes = Array(Set(rawMimeTypes.filter { !$0.isEmpty })).sorted()
    let pasteboardTypes = Set(mimeTypes.flatMap(Self.osc72PasteboardTypes))
    guard !pasteboardTypes.isEmpty else {
      result(
        FlutterError(
          code: "unsupported_osc72_mime",
          message: "No requested MIME type maps to a macOS pasteboard type",
          details: nil
        )
      )
      return
    }
    osc72DropTarget = Osc72DropTarget(sessionId: sessionId, mimeTypes: mimeTypes)
    osc72DropDecision = []
    registerForDraggedTypes(Array(pasteboardTypes))
    result(nil)
  }

  static func osc72PasteboardTypes(for mimeType: String) -> [NSPasteboard.PasteboardType] {
    switch mimeType.lowercased() {
    case "text/plain":
      return [.string]
    case "text/uri-list":
      return [.fileURL, .URL]
    default:
      return [NSPasteboard.PasteboardType(mimeType)]
    }
  }

  private func setOsc72DropDecision(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let operation = arguments["operation"] as? Int
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    osc72DropDecision = switch operation {
    case 1: .copy
    case 2: .move
    default: []
    }
    result(nil)
  }

  private func supportedOsc72Operation(_ source: NSDragOperation) -> NSDragOperation {
    if osc72DropDecision.contains(.move), source.contains(.move) {
      return .move
    }
    if osc72DropDecision.contains(.copy), source.contains(.copy) {
      return .copy
    }
    return []
  }

  private func offeredOsc72MimeTypes(
    _ pasteboard: NSPasteboard,
    target: Osc72DropTarget
  ) -> [String] {
    target.mimeTypes.filter { mimeType in
      Self.osc72PasteboardTypes(for: mimeType).contains { pasteboard.availableType(from: [$0]) != nil }
    }
  }

  private func reportOsc72DragEvent(
    _ sender: any NSDraggingInfo,
    phase: String,
    dropId: String? = nil,
    mimeTypes explicitMimeTypes: [String]? = nil
  ) {
    guard let target = osc72DropTarget else {
      return
    }
    let point = sender.draggingLocation
    let contentHeight = contentView?.bounds.height ?? frame.height
    let mimeTypes = explicitMimeTypes ?? offeredOsc72MimeTypes(sender.draggingPasteboard, target: target)
    var arguments: [String: Any] = [
      "phase": phase,
      "sessionId": target.sessionId,
      "mimeTypes": mimeTypes,
      "x": Double(point.x),
      "y": Double(contentHeight - point.y),
      "operations": Self.osc72OperationMask(sender.draggingSourceOperationMask)
    ]
    if let dropId {
      arguments["dropId"] = dropId
    }
    windowBridgeChannel?.invokeMethod("osc72DragEvent", arguments: arguments)
  }

  static func osc72OperationMask(_ operations: NSDragOperation) -> Int {
    var value = 0
    if operations.contains(.copy) {
      value |= 1
    }
    if operations.contains(.move) {
      value |= 2
    }
    return value
  }

  static func osc72UriListData(_ urls: [URL]) -> Data? {
    urls
      .map(\.absoluteString)
      .joined(separator: "\r\n")
      .appending(urls.isEmpty ? "" : "\r\n")
      .data(using: .utf8)
  }

  static func osc72ReadRange(offset: Int, maxBytes: Int, dataCount: Int) -> Range<Int>? {
    guard offset >= 0, maxBytes > 0, maxBytes <= 3072, offset <= dataCount else {
      return nil
    }
    return offset..<min(offset + maxBytes, dataCount)
  }

  private func captureOsc72DropPayload(
    _ pasteboard: NSPasteboard,
    target: Osc72DropTarget
  ) -> Osc72DropPayload? {
    let offered = offeredOsc72MimeTypes(pasteboard, target: target)
    var dataByMimeType: [String: Data] = [:]
    var totalBytes = 0
    for mimeType in offered {
      let data: Data?
      switch mimeType.lowercased() {
      case "text/plain":
        data = pasteboard.string(forType: .string)?.data(using: .utf8)
      case "text/uri-list":
        let urlObjects = pasteboard.readObjects(
          forClasses: [NSURL.self],
          options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        let urls = urlObjects.compactMap { object -> URL? in
          (object as? NSURL).map { $0 as URL }
        }
        data = Self.osc72UriListData(urls)
      default:
        data = pasteboard.data(forType: NSPasteboard.PasteboardType(mimeType))
      }
      guard let data else {
        continue
      }
      totalBytes += data.count
      guard totalBytes <= Self.maxOsc72DropBytes else {
        return nil
      }
      dataByMimeType[mimeType] = data
    }
    let mimeTypes = offered.filter { dataByMimeType[$0] != nil }
    guard !mimeTypes.isEmpty else {
      return nil
    }
    return Osc72DropPayload(mimeTypes: mimeTypes, dataByMimeType: dataByMimeType)
  }

  private func readOsc72DropData(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let dropId = arguments["dropId"] as? String,
      let mimeType = arguments["mimeType"] as? String,
      let offset = arguments["offset"] as? Int,
      let maxBytes = arguments["maxBytes"] as? Int,
      let data = osc72DropPayloads[dropId]?.dataByMimeType[mimeType],
      let range = Self.osc72ReadRange(
        offset: offset,
        maxBytes: maxBytes,
        dataCount: data.count
      )
    else {
      result(
        FlutterError(
          code: "invalid_osc72_read",
          message: "OSC 72 drop data request is invalid or expired",
          details: nil
        )
      )
      return
    }
    let end = range.upperBound
    result([
      "bytes": FlutterStandardTypedData(bytes: data.subdata(in: range)),
      "eof": end == data.count,
      "size": data.count
    ])
  }

  private func releaseOsc72Drop(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let dropId = arguments["dropId"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    osc72DropPayloads.removeValue(forKey: dropId)
    result(nil)
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
    let expiresAfterMs = arguments["expiresAfterMs"] as? Int
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
          self.notificationExpiryWorkItems.removeValue(forKey: identifier)?.cancel()
          if let expiresAfterMs, expiresAfterMs > 0 {
            let expiryWorkItem = DispatchWorkItem { [weak self] in
              center.removePendingNotificationRequests(withIdentifiers: [identifier])
              center.removeDeliveredNotifications(withIdentifiers: [identifier])
              self?.notificationExpiryWorkItems.removeValue(forKey: identifier)
            }
            self.notificationExpiryWorkItems[identifier] = expiryWorkItem
            DispatchQueue.main.asyncAfter(
              deadline: .now() + .milliseconds(expiresAfterMs),
              execute: expiryWorkItem
            )
          }
          result(nil)
        }
      }
    }
  }

  static func clipboardMimeTypes(_ pasteboard: NSPasteboard) -> [String] {
    Array(
      Set(
        (pasteboard.types ?? [])
          .map(Self.mime(forPasteboardType:))
          .filter(Self.isMimeType)
      )
    ).sorted()
  }

  static func writeClipboardEntries(
    _ entries: [(NSPasteboard.PasteboardType, Data)],
    to pasteboard: NSPasteboard
  ) -> Bool {
    let item = NSPasteboardItem()
    for (type, data) in entries where !item.setData(data, forType: type) {
      return false
    }
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  static func itermClipboardPasteboardName(for selection: String) -> NSPasteboard.Name {
    switch selection {
    case "find":
      return .find
    case "font":
      return .font
    default:
      return .general
    }
  }

  private func writeClipboardText(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let text = arguments["text"] as? String,
      text.utf8.count <= 4 * 1024 * 1024,
      let selection = arguments["selection"] as? String,
      ["c", "find", "font"].contains(selection)
    else {
      result(FlutterError(code: "invalid_clipboard_text", message: "Clipboard text request is invalid", details: nil))
      return
    }
    let name = Self.itermClipboardPasteboardName(for: selection)
    let pasteboard = name == .general ? NSPasteboard.general : NSPasteboard(name: name)
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      result(FlutterError(code: "clipboard_text_write_failed", message: "macOS rejected clipboard text", details: nil))
      return
    }
    result(nil)
  }

  private func writeClipboardMime(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let rawItems = arguments["items"] as? [[String: Any]],
      !rawItems.isEmpty,
      rawItems.count <= 64
    else {
      result(FlutterError(code: "invalid_clipboard_mime", message: "Clipboard MIME items are invalid", details: nil))
      return
    }
    var entries: [(NSPasteboard.PasteboardType, Data)] = []
    var totalBytes = 0
    for rawItem in rawItems {
      guard
        let mime = rawItem["mime"] as? String,
        !mime.isEmpty,
        mime.utf8.count <= 255,
        let typedData = rawItem["data"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "invalid_clipboard_mime", message: "Clipboard MIME entry is invalid", details: nil))
        return
      }
      let data = typedData.data
      totalBytes += data.count
      guard totalBytes <= 4 * 1024 * 1024 else {
        result(FlutterError(code: "clipboard_mime_too_large", message: "Clipboard MIME payload exceeds the limit", details: nil))
        return
      }
      entries.append((Self.pasteboardType(forMime: mime), data))
      if let aliases = rawItem["aliases"] as? [String] {
        for alias in aliases.prefix(16) where !alias.isEmpty && alias.utf8.count <= 255 {
          entries.append((Self.pasteboardType(forMime: alias), data))
        }
      }
    }
    let pasteboard = NSPasteboard.general
    guard Self.writeClipboardEntries(entries, to: pasteboard) else {
      result(FlutterError(code: "clipboard_mime_write_failed", message: "macOS rejected clipboard MIME transaction", details: nil))
      return
    }
    result(nil)
  }

  private func readClipboardMime(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let patterns = arguments["mimeTypes"] as? [String],
      !patterns.isEmpty,
      patterns.count <= 64
    else {
      result(FlutterError(code: "invalid_clipboard_mime", message: "Clipboard MIME request is invalid", details: nil))
      return
    }
    let pasteboard = NSPasteboard.general
    var items: [[String: Any]] = []
    var seen = Set<String>()
    var totalBytes = 0
    for type in pasteboard.types ?? [] {
      let mime = Self.mime(forPasteboardType: type)
      guard
        Self.isMimeType(mime),
        !seen.contains(mime),
        patterns.contains(where: { Self.mimePattern($0, matches: mime) })
      else {
        continue
      }
      guard let data = pasteboard.data(forType: type) else { continue }
      totalBytes += data.count
      guard totalBytes <= 4 * 1024 * 1024 else {
        result(FlutterError(code: "clipboard_mime_too_large", message: "Clipboard MIME payload exceeds the limit", details: nil))
        return
      }
      seen.insert(mime)
      items.append(["mime": mime, "data": FlutterStandardTypedData(bytes: data)])
      if items.count >= 64 { break }
    }
    result(["items": items])
  }

  private func closeNotification(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let identifier = arguments["identifier"] as? String,
      !identifier.isEmpty
    else {
      result(
        FlutterError(
          code: "invalid_notification",
          message: "Notification identifier is required",
          details: nil
        )
      )
      return
    }
    notificationExpiryWorkItems.removeValue(forKey: identifier)?.cancel()
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    result(nil)
  }

  func notificationAuthorizationFailedError(message: String) -> FlutterError {
    FlutterError(
      code: "notification_authorization_failed",
      message: message,
      details: nil
    )
  }
}
