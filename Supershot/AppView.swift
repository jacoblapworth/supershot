import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct AppView: View {
  @Fetch(GamesRequest(), animation: .default)
  private var response = GamesRequest.Value()
  @Bindable var store: StoreOf<AppFeature>

  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      GamesHomeView(
        games: response.games,
        loadingGameID: store.loadingGameID,
        gameTapped: { store.send(.gameRowTapped($0)) },
        newGameTapped: { store.send(.newGameButtonTapped) }
      )
    } destination: { pathStore in
      switch pathStore.case {
      case .gameDetail(let gameDetailStore):
        GameDetailView(store: gameDetailStore)
      case .scoring(let scoringStore):
        ScoringView(store: scoringStore)
      case .setup(let setupStore):
        SetupView(store: setupStore)
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
    .onOpenURL { store.send(.deepLinkOpened($0)) }
  }
}

#Preview("Games") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedPreviewGames()
  }
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
