import Cocoa
import Sparkle
import os

/// Sparkle owns downloading, signature verification and replacement. Termination
/// still goes through AppDelegate's confirmation and Dart shutdown handshake.
final class SoftwareUpdateController: NSObject, SPUUpdaterDelegate {
  private static let logger = Logger(subsystem: "work.ianvs.trail", category: "SoftwareUpdate")
  private var controller: SPUStandardUpdaterController?
  private(set) var configurationError: String?

  static func configurationError(info: [String: Any], bundleIdentifier: String?) -> String? {
    let isTestBuild = bundleIdentifier == "work.ianvs.trail.update-test"
    guard bundleIdentifier == "work.ianvs.trail" || isTestBuild else {
      return "Automatic updates are available in the release version of Trail."
    }
    guard let encodedKey = info["SUPublicEDKey"] as? String,
      let key = Data(base64Encoded: encodedKey), key.count == 32
    else {
      return "This build does not have an update signing key. Install an official release to enable updates."
    }
    guard let feed = info["SUFeedURL"] as? String, let url = URL(string: feed),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
      url.fragment == nil,
      url.scheme == "https"
        || (isTestBuild && url.scheme == "http" && host == "127.0.0.1")
    else {
      return "This build does not have a secure update feed. Install an official release to enable updates."
    }
    return nil
  }

  func start() {
    guard controller == nil else { return }
    configurationError = Self.configurationError(
      info: Bundle.main.infoDictionary ?? [:], bundleIdentifier: Bundle.main.bundleIdentifier
    )
    guard configurationError == nil else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )
    do {
      try controller.updater.start()
      // Never silently close terminals, even if an old preference enabled it.
      controller.updater.automaticallyDownloadsUpdates = false
      self.controller = controller
    } catch {
      configurationError = error.localizedDescription
    }
  }

  @objc(updaterDidNotFindUpdate:error:)
  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    let error = error as NSError
    let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue ?? -1
    Self.logger.notice("No update available; reason=\(reason, privacy: .public)")
  }

  @objc(updater:didAbortWithError:)
  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    let error = error as NSError
    // Do not log feed URLs, file paths, or arbitrary error userInfo.
    Self.logger.notice("Update cycle ended; domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public)")
  }

  // Let Sparkle's button/accessibility action return before AppDelegate opens
  // its modal quit confirmation. Installation still uses the normal shutdown
  // handshake, including cancellation and the Dart save acknowledgement.
  @objc(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)
  func updater(
    _ updater: SPUUpdater,
    shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    DispatchQueue.main.async(execute: installHandler)
    return true
  }

  @objc func checkForUpdates(_ sender: Any?) {
    start()
    guard let controller else {
      let alert = NSAlert()
      alert.messageText = "Updates Unavailable"
      alert.informativeText = configurationError ?? "The updater could not be started."
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }
    guard controller.updater.canCheckForUpdates else { return }
    controller.checkForUpdates(sender)
  }
}
