import AlarmClient
import AppSettings
import AppUI
import Combine
import ComposableArchitecture
import Database
import Dependencies
import GameCore
import GameServices
import GamesFeature
import PaywallFeature
import PermissionsFeature
import PreviewSupport
import SettingsFeature
import SharedModels
import SQLiteData
import SubscriptionClient
import SwiftUI
import TeamsFeature
import UI

package struct AppView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Bindable package var store: StoreOf<AppFeature>

  package var body: some View {
    Group {
      if let welcomeStore = store.scope(
        state: \.destination?.welcome,
        action: \.destination.welcome
      ) {
        WelcomeView(store: welcomeStore)
      } else {
        tabs
      }
    }
    .sheet(item: Binding(
      get: {
        #if os(macOS)
          guard !store.paywallFromSettings else { return nil as StoreOf<PaywallFeature>? }
        #endif
        return store.scope(state: \.destination?.proPaywall, action: \.destination.proPaywall)
      },
      set: {
        if $0 == nil {
          store.send(.destination(.dismiss))
        }
      }
    )) { paywallStore in
      PaywallView(store: paywallStore)
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
    #if os(macOS)
      MacNavigationView(store: store)
    #else
      TabView(selection: $store.selectedTab.sending(\.selectedTabChanged)) {
        Tab("Games", systemImage: "sportscourt", value: AppFeature.Tab.games) {
          GamesHomeView(
            proAccess: store.proAccess,
            store: store.scope(state: \.games, action: \.games),
            isPresentingPaywall: store.destination?.proPaywall != nil
          )
        }
        Tab("Teams", systemImage: "person.2", value: AppFeature.Tab.teams) {
          TeamsListView(
            proAccess: store.proAccess,
            store: store.scope(state: \.teams, action: \.teams),
            isPresentingPaywall: store.destination?.proPaywall != nil
          )
        }
        Tab("Settings", systemImage: "gearshape", value: AppFeature.Tab.settings) {
          SettingsView(
            proAccess: store.proAccess,
            store: store.scope(state: \.settings, action: \.settings)
          )
        }
      }
    #endif
  }

  package init(store: StoreOf<AppFeature>) {
    self.store = store
  }
}

#Preview("Games") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  AppView(store: Store(initialState: AppFeature.State()) {
    AppFeature()
  })
}
