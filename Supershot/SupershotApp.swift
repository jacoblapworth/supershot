import SwiftUI
import SQLiteData
import ComposableArchitecture
import RevenueCat

@main struct SupershotApp: App {
  @Dependency(\.context) var context
  
  init() {
    guard
      let revenueCatAPIKey = Bundle.main.object(
        forInfoDictionaryKey: "RevenueCatAPIKey"
      ) as? String,
      !revenueCatAPIKey.isEmpty,
      !revenueCatAPIKey.hasPrefix("$(")
        else {
      preconditionFailure(
        "RevenueCat is not configured. Set REVENUECAT_API_KEY in the archive or CI build settings."
      )
    }
    
    Purchases.configure(
      withAPIKey: revenueCatAPIKey
    )
#if DEBUG
    Purchases.shared.logIn("dev") { _,_,_  in }
#endif
    try! prepareDependencies {
      try $0.bootstrapDatabase()
//      try $0.defaultSyncEngine = SyncEngine.init(
//        for: $0.defaultDatabase,
//        tables: Team.self, Game.self, GamePeriod.self, Goal.self
//      )
#if DEBUG
      try $0.defaultDatabase.seedDebugExamplesIfNeeded()
#endif
    }
  }
  
  var body: some Scene {
    WindowGroup {
      AppView(
        store: Store(initialState: AppFeature.State()) {
          AppFeature()
        }
      )
    }
  }
}
