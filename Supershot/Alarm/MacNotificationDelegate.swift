#if os(macOS)
  import AppKit
  import Foundation
  import UserNotifications

  /// Install before SwiftUI opens its first scene so cold-launch notification responses are handled.
  final class MacNotificationDelegate: NSObject, NSApplicationDelegate,
    UNUserNotificationCenterDelegate
  {
    func applicationWillFinishLaunching(_: Notification) {
      UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
      _: UNUserNotificationCenter,
      willPresent _: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
      completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
      _: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void
    ) {
      guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let value = response.notification.request.content.userInfo["gameID"] as? String,
            let gameID = UUID(uuidString: value)
      else {
        completionHandler()
        return
      }
      Task { @MainActor in
        let scheme =
          Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String ?? "supershot"
        // Going through the registered URL also reopens the single main window if it was closed.
        if let url = URL(string: "\(scheme)://game/\(gameID.uuidString)") {
          NSWorkspace.shared.open(
            [url],
            withApplicationAt: Bundle.main.bundleURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
          )
        }
        completionHandler()
      }
    }
  }
#endif
