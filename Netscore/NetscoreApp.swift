import SwiftUI
import SQLiteData
import ComposableArchitecture

@main struct NetscoreApp: App {
  init() {
    try! prepareDependencies {
      try $0.bootstrapDatabase()
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
