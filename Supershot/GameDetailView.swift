import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct GameDetailView: View {
  @Fetch private var response: GameDetailRequest.Value
  let store: StoreOf<GameDetailFeature>

  init(store: StoreOf<GameDetailFeature>) {
    self.store = store
    _response = Fetch(
      wrappedValue: GameDetailRequest.Value(),
      GameDetailRequest(gameID: store.gameID)
    )
  }

  var body: some View {
    Group {
      if let detail = response.detail {
        GameDetailContentView(detail: detail)
      } else if $response.isLoading {
        ProgressView("Loading game…")
      } else {
        ContentUnavailableView(
          "Game unavailable",
          systemImage: "exclamationmark.triangle",
          description: Text("This game could not be loaded.")
        )
      }
    }
    .navigationTitle("Game")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Delete game", systemImage: "trash", role: .destructive) {
            store.send(.deleteButtonTapped)
          }
        } label: {
          Label("Game actions", systemImage: "ellipsis")
        }
      }
    }
  }
}

#Preview("Completed game") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  NavigationStack {
    GameDetailView(
      store: Store(
        initialState: GameDetailFeature.State(gameID: UUID(10))
      ) {
        GameDetailFeature()
      }
    )
  }
}
