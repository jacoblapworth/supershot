import ComposableArchitecture
import Database
import Dependencies
import GameAnalysis
import GameCore
import GameServices
import PreviewSupport
import SQLiteData
import SharedModels
import Styleguide
import SwiftUI

package struct GameDetailView: View {
  @Fetch private var response: GameDetailRequest.Value
  package let store: StoreOf<GameDetailFeature>
  package var showsProPromotion: Bool
  package var proPromotionTapped: () -> Void

  package init(
    store: StoreOf<GameDetailFeature>,
    showsProPromotion: Bool,
    proPromotionTapped: @escaping () -> Void
  ) {
    self.store = store
    self.showsProPromotion = showsProPromotion
    self.proPromotionTapped = proPromotionTapped
    _response = Fetch(
      wrappedValue: GameDetailRequest.Value(),
      GameDetailRequest(gameID: store.gameID)
    )
  }

  package var body: some View {
    Group {
      if let detail = response.detail {
        GameDetailContentView(
          detail: detail,
          showsProPromotion: showsProPromotion,
          proPromotionTapped: proPromotionTapped
        )
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
      },
      showsProPromotion: true,
      proPromotionTapped: {}
    )
  }
}
