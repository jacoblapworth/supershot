import AlarmClient
import AppSettings
import ComposableArchitecture
import Database
import FeatureFlagsClient
import Foundation
import GameCore
import GameServices
import GamesFeature
import PaywallFeature
import PermissionsFeature
import SQLiteData
import SettingsFeature
import SharedModels
import Sharing
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamsFeature

@Reducer
package struct AppFeature {
  package enum Tab: Equatable, Hashable, Sendable {
    case games
    case settings
    case teams
  }

  @ObservableState
  package struct State: Equatable {
    @Presents package var destination: AppDestination.State?
    package var games = GamesFeature.State()
    package var teams = TeamsFeature.State()
    package var settings = SettingsFeature.State()
    @Shared(.hasCompletedWelcome) package var hasCompletedWelcome
    package var pendingDeepLink: URL?
    package var hasLoadedAccess = false
    package var hasStartedSubscriptionObservation = false
    package var proAccess = SubscriptionEntitlement.unknown
    package var paywallFromSettings = false
    package var selectedTab = Tab.games

    package init() {
      if !hasCompletedWelcome {
        destination = .welcome(WelcomeFeature.State())
      }
    }
  }

  package enum Action {
    case deepLinkOpened(URL)
    case destination(PresentationAction<AppDestination.Action>)
    case games(GamesFeature.Action)
    case proAccessLoaded(SubscriptionEntitlement)
    case proAccessUpdated(SubscriptionEntitlement)
    case proPromotionTapped
    case sceneBecameActive
    case selectedTabChanged(Tab)
    case settings(SettingsFeature.Action)
    case task
    case teams(TeamsFeature.Action)
  }

  @Dependency(\.alarmAuthorization) package var alarmAuthorization
  @Dependency(\.alarmClient) package var alarmClient
  @Dependency(\.defaultDatabase) package var database
  @Dependency(\.gameTimer) package var gameTimer
  @Dependency(\.featureFlags) package var featureFlags
  @Dependency(\.proSubscription) package var proSubscription

  package var body: some Reducer<State, Action> {
    CombineReducers {
      Scope(state: \.games, action: \.games) {
        GamesFeature()
      }
      Scope(state: \.settings, action: \.settings) {
        SettingsFeature()
      }
      Scope(state: \.teams, action: \.teams) {
        TeamsFeature()
      }
      Reduce { state, action in
        switch action {
        case .deepLinkOpened(let url):
          guard let gameID = gameID(from: url) else { return .none }
          guard state.hasCompletedWelcome else {
            state.pendingDeepLink = url
            return .none
          }

          if state.games.hasGameRoute(for: gameID) {
            state.selectedTab = .games
            return .send(.games(.gameDeepLinkOpened(gameID)))
          }
          if state.teams.hasGameRoute(for: gameID) {
            state.selectedTab = .teams
            return .send(.teams(.gameDeepLinkOpened(gameID)))
          }

          state.selectedTab = .games
          return .send(.games(.gameDeepLinkOpened(gameID)))

        case .settings(.delegate(.proPromotionTapped)):
          #if os(macOS)
            state.paywallFromSettings = true
          #endif
          return .send(.proPromotionTapped)

        case .games(.delegate(.proPromotionTapped)), .teams(.delegate(.proPromotionTapped)):
          state.paywallFromSettings = false
          return .send(.proPromotionTapped)

        case .settings(.delegate(.proAccessChanged(let access))):
          return .send(.proAccessUpdated(access))

        case .games, .settings, .teams:
          return .none

        case .destination(.presented(.welcome(.delegate(.completed)))):
          state.$hasCompletedWelcome.withLock { $0 = true }
          state.destination = nil
          state.selectedTab = .games
          guard let url = state.pendingDeepLink else { return .none }
          state.pendingDeepLink = nil
          return .send(.deepLinkOpened(url))

        case .proAccessLoaded(let access):
          state.hasLoadedAccess = true
          return applyProAccess(access, state: &state)

        case .proAccessUpdated(let access):
          return applyProAccess(access, state: &state)

        case .destination(.presented(.proPaywall(.delegate(.accessChanged(let access))))):
          return applyProAccess(access, state: &state)

        case .destination:
          return .none

        case .proPromotionTapped:
          guard state.proAccess != .pro, state.destination == nil else { return .none }
          state.destination = .proPaywall(PaywallFeature.State())
          return .none

        case .sceneBecameActive:
          guard state.hasStartedSubscriptionObservation else { return .none }
          let proSubscription = self.proSubscription
          return .run { send in
            guard let access = try? await proSubscription.currentAccess() else { return }
            await send(.proAccessUpdated(access))
          }

        case .selectedTabChanged(let tab):
          state.selectedTab = tab
          return .none

        case .task:
          guard !state.hasStartedSubscriptionObservation else { return .none }
          state.hasStartedSubscriptionObservation = true
          let proSubscription = self.proSubscription
          return .run { send in
            let initialAccess: SubscriptionEntitlement
            do {
              initialAccess = try await proSubscription.currentAccess()
            } catch {
              initialAccess = .free
            }
            await send(.proAccessLoaded(initialAccess))

            for await access in proSubscription.accessUpdates() {
              await send(.proAccessUpdated(access))
            }
          }
        }
      }
    }
    .ifLet(\.$destination, action: \.destination) {
      AppDestination.body
    }
  }

  private func applyProAccess(
    _ access: SubscriptionEntitlement,
    state: inout State
  ) -> Effect<Action> {
    state.proAccess = access

    switch access {
    case .free:
      return synchronizePremiumPresentations(access)

    case .pro:
      if state.destination?.proPaywall != nil {
        state.destination = nil
      }
      return synchronizePremiumPresentations(access)

    case .unknown:
      return .none
    }
  }

  private func cleanUpPremiumPresentations() -> Effect<Action> {
    .run { _ in
      let gameIDs = try await unfinishedGameIDs()
      await alarmClient.reconcileAlarms([])
      for gameID in gameIDs {
        await gameTimer.endPresentation(gameID)
      }
    }
  }

  private func synchronizePremiumPresentations(_ access: SubscriptionEntitlement) -> Effect<Action>
  {
    let showsActivity = featureFlags.isEnabled(.liveActivities, access)
    let allowsAlerts = featureFlags.isEnabled(.timerAlerts, access)
    guard showsActivity || allowsAlerts else { return cleanUpPremiumPresentations() }
    return .run { _ in
      let authorization = allowsAlerts ? await alarmAuthorization.status() : .notDetermined
      let schedulesAlerts = allowsAlerts && authorization == .authorized
      let gameIDs = try await unfinishedGameIDs()
      await alarmClient.reconcileAlarms(schedulesAlerts ? Set(gameIDs) : [])
      for gameID in gameIDs {
        if showsActivity {
          await gameTimer.refreshActivity(gameID)
        } else {
          await alarmClient.endActivity(gameID)
        }
        if schedulesAlerts {
          _ = await gameTimer.scheduleAlarm(gameID)
        }
      }
    }
  }

  private func unfinishedGameIDs() async throws -> [Game.ID] {
    try await database.read { db in
      try Game.fetchAll(db)
        .filter(\.isInProgress)
        .map(\.id)
    }
  }

  private func gameID(from url: URL) -> Game.ID? {
    guard
      [
        "supershot",
        Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String ?? "supershot-dev",
      ].contains(url.scheme ?? ""), url.host == "game"
    else { return nil }
    return UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }

  package init() {

  }
}

@Reducer
package enum AppDestination {
  case welcome(WelcomeFeature)
  case proPaywall(PaywallFeature)
}

extension AppDestination.State: Equatable {}
