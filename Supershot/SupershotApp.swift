import SwiftUI
import SQLiteData
import ComposableArchitecture
import RevenueCat

@main struct SupershotApp: App {
  init() {
    Purchases.configure(withAPIKey: "test_zKRQzbkGIeFdTqByFkpdStXjvQI")
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
