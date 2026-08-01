import SwiftUI
import SQLiteData

@main struct NetscoreApp: App {
  
  static let model = AppModel()
  
  init() {
//    if !isTesting {
      try! prepareDependencies {
        try $0.bootstrapDatabase()
      }
//    }
  }
  
  var body: some Scene {
    WindowGroup {
      AppView()
    }
  }
}
