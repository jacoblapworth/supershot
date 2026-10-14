import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct GamesHomeView: View {
  @Fetch(GamesRequest(), animation: .default)
  private var gamesResponse = GamesRequest.Value()
  let proAccess: SubscriptionEntitlement
  @Bindable var store: StoreOf<GamesFeature>
  var isPresentingPaywall = false

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
        ScoringView(store: scoringStore, proAccess: proAccess, isPresentingPaywall: isPresentingPaywall)
#if os(iOS)
          .toolbarVisibility(.hidden, for: .tabBar)
#endif
      case .setup(let setupStore):
        NewGameView(store: setupStore, proAccess: proAccess)
#if os(iOS)
          .toolbarVisibility(.hidden, for: .tabBar)
#endif
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
  }

  private var gamesList: some View {
    let visibleGames = store.filter.games(from: gamesResponse.games)
    return List {
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
        } else if visibleGames.isEmpty {
          ContentUnavailableView {
            Label(store.filter.emptyTitle, systemImage: "line.3.horizontal.decrease")
          } description: {
            Text("Choose another filter to see your game history.")
          } actions: {
            Button("Show all games") {
              store.send(.filterButtonTapped(.all))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("gamesFilter.showAll")
          }
          .listRowBackground(Color.clear)
        } else {
          ForEach(visibleGames) { game in
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
      ToolbarItem(placement: .principal) {
        GamesFilterControl(selection: store.filter) { filter in
          store.send(.filterButtonTapped(filter))
        }
      }
#if os(iOS)
      .sharedBackgroundVisibility(.hidden)
#endif
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

#Preview("In progress") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  var state = GamesFeature.State()
  state.filter = .inProgress
  return GamesHomeView(
    proAccess: .pro,
    store: Store(initialState: state) {
      GamesFeature()
    }
  )
}

#Preview("Completed") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  var state = GamesFeature.State()
  state.filter = .completed
  return GamesHomeView(
    proAccess: .pro,
    store: Store(initialState: state) {
      GamesFeature()
    }
  )
}
