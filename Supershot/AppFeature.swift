import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct AppFeature {
  enum Tab: Equatable, Hashable, Sendable {
    case games
    case settings
    case teams
  }

  @ObservableState
  struct State: Equatable {
    var games = GamesFeature.State()
    var hasCheckedPermissions = false
    var hasStartedSubscriptionObservation = false
    @Presents var permissionsOnboarding: PermissionsOnboardingFeature.State?
    var proAccess = SubscriptionEntitlement.unknown
    @Presents var proPaywall: ProPaywallFeature.State?
    var selectedTab = Tab.games
    var settings = SettingsFeature.State()
    var teams = TeamsFeature.State()
  }

  enum Action {
    case deepLinkOpened(URL)
    case games(GamesFeature.Action)
    case permissionsOnboarding(PresentationAction<PermissionsOnboardingFeature.Action>)
    case proAccessLoaded(SubscriptionEntitlement)
    case proAccessUpdated(SubscriptionEntitlement)
    case proPaywall(PresentationAction<ProPaywallFeature.Action>)
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
  @Dependency(\.locationClient) var locationClient
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

        case .permissionsOnboarding(.presented(.delegate(.completed))):
          state.permissionsOnboarding = nil
          guard
            state.proAccess == .pro,
            alarmAuthorization.status() == .authorized
          else { return .none }
          return synchronizePremiumPresentations(schedulesAlerts: true)

        case .permissionsOnboarding:
          return .none

        case let .proAccessLoaded(access):
          state.hasCheckedPermissions = true
          return applyProAccess(access, state: &state)

        case let .proAccessUpdated(access):
          return applyProAccess(access, state: &state)

        case let .proPaywall(.presented(.delegate(.accessChanged(access)))):
          return applyProAccess(access, state: &state)

        case .proPaywall:
          return .none

        case .proPromotionTapped:
          guard state.proAccess != .pro else { return .none }
          state.proPaywall = ProPaywallFeature.State()
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
    .ifLet(\.$permissionsOnboarding, action: \.permissionsOnboarding) {
      PermissionsOnboardingFeature()
    }
    .ifLet(\.$proPaywall, action: \.proPaywall) {
      ProPaywallFeature()
    }
  }

  private func applyProAccess(
    _ access: SubscriptionEntitlement,
    state: inout State
  ) -> Effect<Action> {
    state.proAccess = access

    switch access {
    case .free:
      state.permissionsOnboarding = locationClient.authorizationStatus() == .notDetermined
        ? PermissionsOnboardingFeature.State(step: .location)
        : nil
      return cleanUpPremiumPresentations()

    case .pro:
      state.proPaywall = nil
      let alarmAuthorization = alarmAuthorization.status()
      let needsLocation = locationClient.authorizationStatus() == .notDetermined
      if alarmAuthorization == .notDetermined {
        state.permissionsOnboarding = PermissionsOnboardingFeature.State(
          nextStep: needsLocation ? .location : nil
        )
      } else {
        state.permissionsOnboarding = needsLocation
          ? PermissionsOnboardingFeature.State(step: .location)
          : nil
      }
      return synchronizePremiumPresentations(
        schedulesAlerts: alarmAuthorization == .authorized
      )

    case .unknown:
      state.permissionsOnboarding = nil
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
          await gameTimer.scheduleAlarm(gameID)
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

extension ScoringFeature.State {
  init(snapshot: GameSnapshot) {
    let phases = snapshot.phases
    let currentPhaseIndex = min(
      max(snapshot.game.currentPhaseIndex, 0),
      phases.count - 1
    )
    let currentDuration = phases[currentPhaseIndex].durationSeconds

    self.init(
      canUndo: !snapshot.goals.isEmpty,
      centrePassTeamID: snapshot.game.centrePassTeamID == snapshot.teamB.id
        ? snapshot.teamB.id
        : snapshot.teamA.id,
      currentPhaseIndex: currentPhaseIndex,
      elapsedSeconds: min(
        max(snapshot.game.elapsedSeconds, 0),
        max(currentDuration, 0)
      ),
      gameID: snapshot.game.id,
      isShowingLastCentrePassBanner: snapshot.game.isAwaitingCentrePassConfirmation,
      periods: snapshot.periods,
      startedAt: snapshot.game.startedAt,
      teamA: ScoringFeature.Team(
        id: snapshot.teamA.id,
        bibColorHex: snapshot.game.teamABibColorHex,
        name: snapshot.teamA.name
      ),
      teamAScore: snapshot.teamAScore,
      teamB: ScoringFeature.Team(
        id: snapshot.teamB.id,
        bibColorHex: snapshot.game.teamBBibColorHex,
        name: snapshot.teamB.name
      ),
      teamBScore: snapshot.teamBScore,
      timerEndsAt: snapshot.game.timerEndsAt
    )
  }
}
