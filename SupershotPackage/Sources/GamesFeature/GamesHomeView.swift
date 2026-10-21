import ComposableArchitecture
import Database
import Dependencies
import GameAnalysis
import GameCore
import GameDetailFeature
import GameServices
import NewGameFeature
import PaywallFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import SQLiteData
import Styleguide
import SubscriptionClient
import SwiftUI

package struct GamesHomeView: View {
  @Fetch(GamesRequest(), animation: .default)
  private var gamesResponse = GamesRequest.Value()
  package let proAccess: SubscriptionEntitlement
  @Bindable package var store: StoreOf<GamesFeature>
  package var isPresentingPaywall = false

  package var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      gamesList
    } destination: { pathStore in
      switch pathStore.case {
      case let .gameDetail(gameDetailStore):
        GameDetailView(
          store: gameDetailStore,
          showsProPromotion: proAccess == .free,
          proPromotionTapped: { store.send(.proPromotionTapped) }
        )
      case let .scoring(scoringStore):
        ScoringView(
          store: scoringStore, proAccess: proAccess, isPresentingPaywall: isPresentingPaywall
        )
        #if os(iOS)
        .toolbarVisibility(.hidden, for: .tabBar)
        #endif
      case let .setup(setupStore):
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
    let plannedGames = visibleGames.filter(\.isPlanned)
    let historyGames = visibleGames.filter { !$0.isPlanned }
    return List {
      #if os(iOS)
        Section {
          GamesFilterControl(selection: store.filter) { filter in
            store.send(.filterButtonTapped(filter))
          }
          .listRowBackground(Color.clear)
          .listRowInsets(.all, 0)
        }
      #endif
      if proAccess == .free {
        Section {
          ProPromotionCard(
            exploreProTapped: { store.send(.proPromotionTapped) }
          )
          #if os(macOS)
          .fixedSize(horizontal: false, vertical: true)
          #endif
          .listRowBackground(Color.clear)
          .listRowInsets(.all, 0)
        }
      }

      Group {
        if gamesResponse.games.isEmpty {
          ContentUnavailableView {
            Label("No games yet", systemImage: "sportscourt")
          } description: {
            Text("Create a game for later or start keeping score now.")
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
          if store.filter == .all {
            if !plannedGames.isEmpty {
              Section("Planned") { gameRows(plannedGames) }
            }
            if !historyGames.isEmpty {
              Section("Game history") { gameRows(historyGames) }
            }
          } else {
            gameRows(visibleGames)
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(.background)
    .listRowSpacing(8)
    .navigationTitle("Games")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.large)
    #endif
      .toolbar {
        #if os(macOS)
          ToolbarItem(placement: .principal) {
            GamesFilterControl(selection: store.filter) { filter in
              store.send(.filterButtonTapped(filter))
            }
          }
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

  private func gameRows(_ games: [GameListItem]) -> some View {
    ForEach(games) { game in
      Button {
        store.send(.gameRowTapped(game))
      } label: {
        GameRow(game: game)
      }

      .buttonStyle(.plain)
      .listRowInsets(.all, 0)
      .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
      .disabled(store.pendingGameResume != nil)
      .contextMenu {
        Button("Delete", systemImage: "trash", role: .destructive) {
          store.send(.deleteGameButtonTapped(game.id))
        }
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button("Delete", systemImage: "trash", role: .destructive) {
          store.send(.deleteGameButtonTapped(game.id))
        }
      }
    }
    .listRowSpacing(8)
  }

  package init(
    proAccess: SubscriptionEntitlement, store: StoreOf<GamesFeature>,
    isPresentingPaywall: Bool = false
  ) {
    self.proAccess = proAccess
    self.store = store
    self.isPresentingPaywall = isPresentingPaywall
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
