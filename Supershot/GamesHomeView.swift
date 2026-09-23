import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct GamesHomeView: View {
  @Fetch(GamesRequest(), animation: .default)
  private var gamesResponse = GamesRequest.Value()
  let proAccess: SubscriptionEntitlement
  @Bindable var store: StoreOf<GamesFeature>

  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      gamesList
    } destination: { pathStore in
      switch pathStore.case {
      case .gameDetail(let gameDetailStore):
        GameDetailView(
          store: gameDetailStore,
          showsProPromotion: proAccess == .free,
          proPromotionTapped: { store.send(.proPromotionTapped) }
        )
      case .scoring(let scoringStore):
        ScoringView(store: scoringStore)
#if os(iOS)
          .toolbarVisibility(.hidden, for: .tabBar)
#endif
      case .setup(let setupStore):
        NewGameView(store: setupStore)
#if os(iOS)
          .toolbarVisibility(.hidden, for: .tabBar)
#endif
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
  }

  private var gamesList: some View {
    List {
      if proAccess == .free {
        Section {
          ProPromotionCard(
            exploreProTapped: { store.send(.proPromotionTapped) }
          )
          .listRowBackground(Color.clear)
          .listRowInsets(.all, 0)
        }
      }

      Section {
        if gamesResponse.games.isEmpty {
          ContentUnavailableView {
            Label("No games yet", systemImage: "sportscourt")
          } description: {
            Text("Start a game to keep score and build your history.")
          } actions: {
            Button("New Game") {
              store.send(.newGameButtonTapped)
            }
            .buttonStyle(.borderedProminent)
            .fontWeight(.medium)
            .controlSize(.large)
          }
          .listRowBackground(Color.clear)
        } else {
          ForEach(gamesResponse.games) { game in
            Button {
              store.send(.gameRowTapped(game))
            } label: {
              GameRow(game: game)
            }
            
            .buttonStyle(.plain)
            .listRowInsets(.all, 0)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .disabled(store.pendingGameResume != nil)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button("Delete", systemImage: "trash", role: .destructive) {
                store.send(.deleteGameButtonTapped(game.id))
              }
            }
          }
        }
      }
    }
    .navigationTitle("Games")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.newGameButtonTapped)
        } label: {
          Label("New game", systemImage: "plus")
        }
        .disabled(store.pendingGameResume != nil)
      }
    }
  }
}

#Preview("Games") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  GamesHomeView(
    proAccess: .free,
    store: Store(initialState: GamesFeature.State()) {
      GamesFeature()
    }
  )
}
