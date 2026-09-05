import ComposableArchitecture
import Combine
import Dependencies
import SQLiteData
import SwiftUI

struct AppView: View {
  @Environment(\.scenePhase) private var scenePhase
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
        GamesHomeView(
          proAccess: store.proAccess,
          store: store.scope(state: \.games, action: \.games)
        )
      }
      Tab("Teams", systemImage: "person.2", value: AppFeature.Tab.teams) {
        TeamsHomeView(
          proAccess: store.proAccess,
          store: store.scope(state: \.teams, action: \.teams)
        )
      }
      Tab("Settings", systemImage: "gearshape", value: AppFeature.Tab.settings) {
        SettingsView(
          proAccess: store.proAccess,
          store: store.scope(state: \.settings, action: \.settings)
        )
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
