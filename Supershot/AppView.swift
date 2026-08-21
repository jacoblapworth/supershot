import ComposableArchitecture
import Combine
import Dependencies
import SQLiteData
import SwiftUI

struct AppView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Fetch(GamesRequest(), animation: .default)
  private var gamesResponse = GamesRequest.Value()
  @Fetch(TeamsRequest(), animation: .default)
  private var teamsResponse = TeamsRequest.Value()
  @Bindable var store: StoreOf<AppFeature>

  var body: some View {
    Group {
      if !store.hasCheckedPermissions {
        ProgressView()
          .controlSize(.large)
          .accessibilityLabel("Preparing Supershot")
      } else if let onboardingStore = store.scope(
        state: \.permissionsOnboarding,
        action: \.permissionsOnboarding.presented
      ) {
        PermissionsOnboardingView(store: onboardingStore)
      } else {
        tabs
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
    .sheet(item: $store.scope(state: \.proPaywall, action: \.proPaywall)) { paywallStore in
      ProPaywallView(store: paywallStore)
    }
    .task { store.send(.task) }
    .onChange(of: scenePhase) { _, scenePhase in
      if scenePhase == .active {
        store.send(.sceneBecameActive)
      }
    }
    .onOpenURL { store.send(.deepLinkOpened($0)) }
#if os(iOS)
    .onReceive(NotificationCenter.default.publisher(for: .openSupershotGame)) {
      guard let gameURL = $0.object as? URL else { return }
      store.send(.deepLinkOpened(gameURL))
    }
#endif
  }

  private var tabs: some View {
    TabView(selection: $store.selectedTab.sending(\.selectedTabChanged)) {
      Tab("Games", systemImage: "sportscourt", value: AppFeature.Tab.games) {
        gamesNavigation
      }
      Tab("Teams", systemImage: "person.2", value: AppFeature.Tab.teams) {
        teamsNavigation
      }
    }
  }

  private var gamesNavigation: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      GamesHomeView(
        deletingGameID: store.deletingGameID,
        games: gamesResponse.games,
        loadingGameID: store.loadingGameTab == .games ? store.loadingGameID : nil,
        showsProPromotion: store.proAccess == .free,
        deleteGameTapped: { store.send(.deleteGameButtonTapped($0)) },
        gameTapped: { store.send(.gameRowTapped($0)) },
        newGameTapped: { store.send(.newGameButtonTapped) },
        proPromotionTapped: { store.send(.proPromotionTapped) }
      )
    } destination: { pathStore in
      switch pathStore.case {
      case .gameDetail(let gameDetailStore):
        GameDetailView(
          store: gameDetailStore,
          showsProPromotion: store.proAccess == .free,
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
      case .teamDetail(let teamDetailStore):
        TeamDetailView(
          store: teamDetailStore,
          deletingGameID: store.deletingGameID,
          loadingGameID: store.loadingGameTab == .games ? store.loadingGameID : nil
        )
      }
    }
  }

  private var teamsNavigation: some View {
    NavigationStack(path: $store.scope(state: \.teamsPath, action: \.teamsPath)) {
      TeamsHomeView(
        deleteTeamTapped: { store.send(.deleteTeamButtonTapped($0)) },
        deletingTeamID: store.deletingTeamID,
        newTeamTapped: { store.send(.newTeamButtonTapped) },
        teamTapped: { store.send(.teamRowTapped($0)) },
        teams: teamsResponse.teams
      )
    } destination: { pathStore in
      switch pathStore.case {
      case .gameDetail(let gameDetailStore):
        GameDetailView(
          store: gameDetailStore,
          showsProPromotion: store.proAccess == .free,
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
      case .teamDetail(let teamDetailStore):
        TeamDetailView(
          store: teamDetailStore,
          deletingGameID: store.deletingGameID,
          loadingGameID: store.loadingGameTab == .teams ? store.loadingGameID : nil
        )
      }
    }
    .sheet(item: $store.scope(state: \.teamEditor, action: \.teamEditor)) { editorStore in
      NavigationStack {
        TeamEditorView(store: editorStore)
      }
    }
  }
}

#Preview("Games") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
