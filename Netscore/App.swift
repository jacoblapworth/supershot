import ComposableArchitecture
import Dependencies
import SwiftUI

struct AppView: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    Group {
      if let summaryStore = store.scope(state: \.summary, action: \.summary) {
        SummaryView(store: summaryStore)
      } else if let scoringStore = store.scope(state: \.scoring, action: \.scoring) {
        ScoringView(store: scoringStore)
      } else {
        SetupView(store: store.scope(state: \.setup, action: \.setup))
      }
    }
  }
}

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
  }
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
