import AlarmClient
import AppFeature
import Database
import Dependencies
import PreviewSupport
import RevenueCat
import SQLiteData
import SwiftUI

@main struct SupershotApp: App {
  @Dependency(\.context) var context
  private var gamesWidgetObservation: GamesWidgetObservation?
  #if os(macOS)
    @NSApplicationDelegateAdaptor(MacNotificationDelegate.self) private var notificationDelegate
  #endif

  init() {
    // Widget previews can launch the app entry point without the app bundle configuration.
    // Preview and test dependencies already provide their own service implementations.
    guard case .live = context else { return }

    guard
      let revenueCatAPIKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
      !revenueCatAPIKey.isEmpty,
      !revenueCatAPIKey.hasPrefix("$(")
    else {
      preconditionFailure("RevenueCat is not configured. Set REVENUECAT_API_KEY in the archive or CI build settings.")
    }

    Purchases.configure(withAPIKey: revenueCatAPIKey)
    #if DEBUG
      Purchases.shared.logIn("dev") { _, _, _ in }
    #endif
    try! prepareDependencies {
      try $0.bootstrapDatabase()
      $0.alarmClient = .live
//      try $0.defaultSyncEngine = SyncEngine.init(
//        for: $0.defaultDatabase,
//        tables: Team.self, Game.self, GamePeriod.self, Goal.self
//      )
      #if DEBUG
        try $0.defaultDatabase.seedDebugExamplesIfNeeded()
      #endif
    }

    #if os(iOS)
      gamesWidgetObservation = GamesWidgetObservation()
    #endif
  }

  var body: some Scene {
    #if os(macOS)
      SupershotMacScenes()
    #else
      WindowGroup { SupershotRootView() }
    #endif
  }
}
