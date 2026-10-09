import SwiftUI
import ComposableArchitecture
import Foundation
import SQLiteData
import Sharing

@Reducer
struct AppFeature {
  enum Tab: Equatable, Hashable, Sendable {
    case games
    case settings
    case teams
  }

  @ObservableState
  struct State: Equatable {
    @Presents var destination: AppDestination.State?
    var games = GamesFeature.State()
    var teams = TeamsFeature.State()
    var settings = SettingsFeature.State()
    @Shared(.hasCompletedWelcome) var hasCompletedWelcome
    var pendingDeepLink: URL?
    var hasLoadedAccess = false
    var hasStartedSubscriptionObservation = false
    var proAccess = SubscriptionEntitlement.unknown
    var selectedTab = Tab.games

    init() {
      if !hasCompletedWelcome {
        destination = .welcome(WelcomeFeature.State())
      }
    }
  }

  enum Action {
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

  @Dependency(\.alarmAuthorization) var alarmAuthorization
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.gameTimer) var gameTimer
  @Dependency(\.proSubscription) var proSubscription

  var body: some Reducer<State, Action> {
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
        case let .deepLinkOpened(url):
          guard let gameID = gameID(from: url) else { return .none }
          guard state.hasCompletedWelcome else {
            state.pendingDeepLink = url
            return .none
          }

          if state.games.hasScoringRoute(for: gameID) {
            state.selectedTab = .games
            return .send(.games(.gameDeepLinkOpened(gameID)))
          }
          if state.teams.hasScoringRoute(for: gameID) {
            state.selectedTab = .teams
            return .send(.teams(.gameDeepLinkOpened(gameID)))
          }

          state.selectedTab = .games
          return .send(.games(.gameDeepLinkOpened(gameID)))

        case .games(.delegate(.proPromotionTapped)),
          .settings(.delegate(.proPromotionTapped)),
          .teams(.delegate(.proPromotionTapped)):
          return .send(.proPromotionTapped)

        case let .settings(.delegate(.proAccessChanged(access))):
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

        case let .proAccessLoaded(access):
          state.hasLoadedAccess = true
          return applyProAccess(access, state: &state)

        case let .proAccessUpdated(access):
          return applyProAccess(access, state: &state)

        case let .destination(.presented(.proPaywall(.delegate(.accessChanged(access))))):
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

        case let .selectedTabChanged(tab):
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
      return cleanUpPremiumPresentations()

    case .pro:
      let alarmAuthorization = alarmAuthorization.status()
      if state.destination?.proPaywall != nil {
        state.destination = nil
      }
      return synchronizePremiumPresentations(
        schedulesAlerts: alarmAuthorization == .authorized
      )

    case .unknown:
      return .none
    }
  }

  private func cleanUpPremiumPresentations() -> Effect<Action> {
    .run { _ in
      let gameIDs = try await unfinishedGameIDs()
      for gameID in gameIDs {
        await gameTimer.endPresentation(gameID)
      }
    }
  }

  private func synchronizePremiumPresentations(
    schedulesAlerts: Bool
  ) -> Effect<Action> {
    .run { _ in
      let gameIDs = try await unfinishedGameIDs()
      for gameID in gameIDs {
        await gameTimer.refreshActivity(gameID)
        if schedulesAlerts {
          _ = await gameTimer.scheduleAlarm(gameID)
        }
      }
    }
  }

  private func unfinishedGameIDs() async throws -> [Game.ID] {
    try await database.read { db in
      try Game.fetchAll(db)
        .filter { $0.endedAt == nil }
        .map(\.id)
    }
  }

  private func gameID(from url: URL) -> Game.ID? {
    guard url.scheme == "supershot", url.host == "game" else { return nil }
    return UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }
}

@Reducer
enum AppDestination {
  case welcome(WelcomeFeature)
  case proPaywall(PaywallFeature)
}

extension AppDestination.State: Equatable {}

extension ScoringFeature.State {
  init(snapshot: GameSnapshot) {
    let currentPhaseIndex = snapshot.game.currentPhaseIndex
    let currentDuration = snapshot.currentPhase.durationSeconds

    self.init(
      canUndo: !snapshot.goals.isEmpty,
      canUndoDuringConfirmation: snapshot.canUndoDuringConfirmation,
      centrePassTeamID: snapshot.game.centrePassTeamID == snapshot.teamB.id
        ? snapshot.teamB.id
        : snapshot.teamA.id,
      currentPhaseIndex: currentPhaseIndex,
      elapsedSeconds: min(
        max(snapshot.game.elapsedSeconds, 0),
        max(currentDuration, 0)
      ),
      swapSides: snapshot.game.swapSides,
      gameID: snapshot.game.id,
      isShowingLastCentrePassBanner: snapshot.game.isAwaitingCentrePassConfirmation,
      lateScoringPeriodNumber: snapshot.game.lateScoringPeriodNumber,
      periods: snapshot.periods,
      startedAt: snapshot.game.startedAt,
      teamA: ScoringFeature.Team(
        id: snapshot.teamA.id,
        bibColor: snapshot.game.teamABibColor,
        name: snapshot.teamA.name
      ),
      teamAScore: snapshot.teamAScore,
      teamB: ScoringFeature.Team(
        id: snapshot.teamB.id,
        bibColor: snapshot.game.teamBBibColor,
        name: snapshot.teamB.name
      ),
      teamBScore: snapshot.teamBScore,
      timerEndsAt: snapshot.game.timerEndsAt
    )
  }
}
