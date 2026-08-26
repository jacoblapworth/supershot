import SwiftUI
import SQLiteData
import ComposableArchitecture
import RevenueCat

@main struct SupershotApp: App {
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
      withAPIKey: revenueCatAPIKey,
      appUserID: "dev" as String //TODO: implement ids
    )
    try! prepareDependencies {
      try $0.bootstrapDatabase()
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
