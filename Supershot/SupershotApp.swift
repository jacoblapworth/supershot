import SwiftUI
import SQLiteData
import ComposableArchitecture

@main struct SupershotApp: App {
  init() {
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
