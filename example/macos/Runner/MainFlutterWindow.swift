import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

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
  private var windowBridgeChannel: FlutterMethodChannel?
  private var hotkeyWindowController: HotkeyWindowController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovableByWindowBackground = true
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)
    windowBridgeChannel = FlutterMethodChannel(
      name: "app/window_bridge",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
