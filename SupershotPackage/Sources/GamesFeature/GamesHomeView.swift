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
import SQLiteData
import ScoringFeature
import SharedModels
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
      case .gameDetail(let gameDetailStore):
        GameDetailView(
          store: gameDetailStore,
          showsProPromotion: proAccess == .free,
          proPromotionTapped: { store.send(.proPromotionTapped) }
        )
      case .scoring(let scoringStore):
        ScoringView(
          store: scoringStore, proAccess: proAccess, isPresentingPaywall: isPresentingPaywall
        )
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
