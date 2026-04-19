import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowBridgeChannel: FlutterMethodChannel?

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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
