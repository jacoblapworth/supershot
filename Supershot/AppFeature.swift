import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
enum AppPath {
  case gameDetail(GameDetailFeature)
  case scoring(ScoringFeature)
  case setup(NewGameFeature)
  case teamDetail(TeamDetailFeature)
}

extension AppPath.State: Equatable {}

@Reducer
struct AppFeature {
  enum Tab: Equatable, Hashable, Sendable {
    case games
    case settings
    case teams
  }

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Alert>?
    var deletingGameID: Game.ID?
    var deletingTeamID: Team.ID?
    var hasCheckedPermissions = false
    var hasStartedSubscriptionObservation = false
    var loadingGameID: Game.ID?
    var loadingGameTab: Tab?
    var path = StackState<AppPath.State>()
    @Presents var permissionsOnboarding: PermissionsOnboardingFeature.State?
    var proAccess = SubscriptionEntitlement.unknown
    @Presents var proPaywall: ProPaywallFeature.State?
    var selectedTab = Tab.games
    @Presents var teamEditor: TeamEditorFeature.State?
    var teamsPath = StackState<AppPath.State>()
  }

  enum Action {
    case alert(PresentationAction<Alert>)
    case deepLinkOpened(URL)
    case deleteGameButtonTapped(Game.ID)
    case deleteGameResponse(Game.ID, Result<Void, any Error>)
    case deleteTeamButtonTapped(Team.ID)
    case deleteTeamResponse(Team.ID, Result<Void, any Error>)
    case gameRowTapped(GameListItem)
    case newGameButtonTapped
    case newTeamButtonTapped
    case path(StackActionOf<AppPath>)
    case permissionsOnboarding(PresentationAction<PermissionsOnboardingFeature.Action>)
    case proAccessLoaded(SubscriptionEntitlement)
    case proAccessUpdated(SubscriptionEntitlement)
    case proPaywall(PresentationAction<ProPaywallFeature.Action>)
    case proPromotionTapped
    case resumeGameResponse(Game.ID, Result<GameSnapshot, any Error>)
    case sceneBecameActive
    case selectedTabChanged(Tab)
    case task
    case teamEditor(PresentationAction<TeamEditorFeature.Action>)
    case teamGameRowTapped(GameListItem)
    case teamRowTapped(TeamListItem)
    case teamsPath(StackActionOf<AppPath>)
  }

  enum Alert: Equatable {
    case dismissButtonTapped
  }

  @Dependency(\.alarmAuthorization) var alarmAuthorization
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.gameTimer) var gameTimer
  @Dependency(\.locationClient) var locationClient
  @Dependency(\.proSubscription) var proSubscription

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .permissionsOnboarding(.presented(.delegate(.completed))):
        state.permissionsOnboarding = nil
        guard
          state.proAccess == .pro,
          alarmAuthorization.status() == .authorized
        else { return .none }
        return synchronizePremiumPresentations(schedulesAlerts: true)

      case .permissionsOnboarding:
        return .none

      case .alert:
        return .none

      case let .deepLinkOpened(url):
        guard let gameID = gameID(from: url) else { return .none }
        for (id, destination) in zip(state.path.ids, state.path) {
          guard case let .scoring(scoring) = destination, scoring.gameID == gameID else {
            continue
          }
          state.selectedTab = .games
          state.path.pop(to: id)
          return .send(
            .path(.element(id: id, action: .scoring(.sceneBecameActive)))
          )
        }
        for (id, destination) in zip(state.teamsPath.ids, state.teamsPath) {
          guard case let .scoring(scoring) = destination, scoring.gameID == gameID else {
            continue
          }
          state.selectedTab = .teams
          state.teamsPath.pop(to: id)
          return .send(
            .teamsPath(.element(id: id, action: .scoring(.sceneBecameActive)))
          )
        }
        state.alert = nil
        state.loadingGameID = gameID
        state.loadingGameTab = .games
        state.selectedTab = .games
        return resumeGameEffect(gameID: gameID)

      case let .deleteGameButtonTapped(gameID):
        guard
          state.deletingGameID == nil,
          state.deletingTeamID == nil,
          state.loadingGameID == nil
        else {
          return .none
        }
        state.alert = nil
        state.deletingGameID = gameID
        return deleteGameEffect(gameID: gameID)

      case let .deleteGameResponse(gameID, .success):
        guard state.deletingGameID == gameID else { return .none }
        state.deletingGameID = nil
        return .none

      case let .deleteGameResponse(gameID, .failure):
        guard state.deletingGameID == gameID else { return .none }
        state.deletingGameID = nil
        state.alert = .gameDeletionFailed
        return .none

      case let .deleteTeamButtonTapped(teamID):
        guard
          state.deletingGameID == nil,
          state.deletingTeamID == nil,
          state.loadingGameID == nil
        else {
          return .none
        }
        state.alert = nil
        state.deletingTeamID = teamID
        return deleteTeamEffect(teamID: teamID)

      case let .deleteTeamResponse(teamID, .success):
        guard state.deletingTeamID == teamID else { return .none }
        state.deletingTeamID = nil
        return .none

      case let .deleteTeamResponse(teamID, .failure):
        guard state.deletingTeamID == teamID else { return .none }
        state.deletingTeamID = nil
        state.alert = .teamDeletionFailed
        return .none

      case let .gameRowTapped(game):
        guard state.deletingGameID == nil, state.deletingTeamID == nil else { return .none }
        guard !game.isCompleted else {
          state.path.append(
            .gameDetail(GameDetailFeature.State(gameID: game.id))
          )
          return .none
        }

        state.alert = nil
        state.loadingGameID = game.id
        state.loadingGameTab = .games
        return resumeGameEffect(gameID: game.id)

      case .newGameButtonTapped:
        state.path.append(.setup(NewGameFeature.State()))
        return .none

      case .newTeamButtonTapped:
        state.teamEditor = TeamEditorFeature.State()
        return .none

      case let .path(.element(id: id, action: .scoring(.delegate(.gameFinished(gameID))))):
        state.path.pop(from: id)
        state.path.append(
          .gameDetail(GameDetailFeature.State(gameID: gameID))
        )
        return .none

      case let .path(.element(id: id, action: .setup(.delegate(.gameStarted(scoring))))):
        state.path.pop(from: id)
        state.path.append(.scoring(scoring))
        return .none

      case let .path(.element(id: id, action: .gameDetail(.delegate(.deleteGameButtonTapped)))):
        guard case let .gameDetail(gameDetail) = state.path[id: id] else {
          return .none
        }
        let gameID = gameDetail.gameID
        state.path.pop(from: id)
        return .send(.deleteGameButtonTapped(gameID))

      case .path:
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

      case let .resumeGameResponse(gameID, .success(snapshot)):
        guard state.loadingGameID == gameID else { return .none }
        let tab = state.loadingGameTab ?? .games
        state.loadingGameID = nil
        state.loadingGameTab = nil

        guard snapshot.game.endedAt == nil else {
          append(
            .gameDetail(GameDetailFeature.State(gameID: gameID)),
            to: tab,
            state: &state
          )
          return .none
        }

        append(.scoring(ScoringFeature.State(snapshot: snapshot)), to: tab, state: &state)
        return .none

      case let .resumeGameResponse(gameID, .failure):
        guard state.loadingGameID == gameID else { return .none }
        state.loadingGameID = nil
        state.loadingGameTab = nil
        state.alert = .gameUnavailable
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

      case .teamEditor(.presented(.delegate(.cancelled))),
        .teamEditor(.presented(.delegate(.saved(_)))):
        state.teamEditor = nil
        return .none

      case .teamEditor:
        return .none

      case let .teamGameRowTapped(game):
        guard state.deletingGameID == nil, state.deletingTeamID == nil else { return .none }
        guard !game.isCompleted else {
          state.teamsPath.append(
            .gameDetail(GameDetailFeature.State(gameID: game.id))
          )
          return .none
        }

        state.alert = nil
        state.loadingGameID = game.id
        state.loadingGameTab = .teams
        return resumeGameEffect(gameID: game.id)

      case let .teamRowTapped(team):
        state.teamsPath.append(
          .teamDetail(TeamDetailFeature.State(teamID: team.id))
        )
        return .none

      case let .teamsPath(
        .element(id: id, action: .gameDetail(.delegate(.deleteGameButtonTapped)))
      ):
        guard case let .gameDetail(gameDetail) = state.teamsPath[id: id] else {
          return .none
        }
        let gameID = gameDetail.gameID
        state.teamsPath.pop(from: id)
        return .send(.deleteGameButtonTapped(gameID))

      case let .teamsPath(
        .element(id: id, action: .teamDetail(.delegate(.deleteTeamButtonTapped)))
      ):
        guard
          state.deletingGameID == nil,
          state.deletingTeamID == nil,
          state.loadingGameID == nil
        else {
          return .none
        }
        guard case let .teamDetail(teamDetail) = state.teamsPath[id: id] else {
          return .none
        }
        let teamID = teamDetail.teamID
        state.teamsPath.pop(from: id)
        return .send(.deleteTeamButtonTapped(teamID))

      case let .teamsPath(
        .element(id: id, action: .scoring(.delegate(.gameFinished(gameID))))
      ):
        state.teamsPath.pop(from: id)
        state.teamsPath.append(
          .gameDetail(GameDetailFeature.State(gameID: gameID))
        )
        return .none

      case let .teamsPath(
        .element(id: _, action: .teamDetail(.delegate(.gameRowTapped(game))))
      ):
        return .send(.teamGameRowTapped(game))

      case .teamsPath:
        return .none
      }
    }
    .forEach(\.path, action: \.path) {
      AppPath.body
    }
    .forEach(\.teamsPath, action: \.teamsPath) {
      AppPath.body
    }
    .ifLet(\.$permissionsOnboarding, action: \.permissionsOnboarding) {
      PermissionsOnboardingFeature()
    }
    .ifLet(\.$proPaywall, action: \.proPaywall) {
      ProPaywallFeature()
    }
    .ifLet(\.$teamEditor, action: \.teamEditor) {
      TeamEditorFeature()
    }
    .ifLet(\.$alert, action: \.alert)
  }

  private func resumeGameEffect(gameID: Game.ID) -> Effect<Action> {
    .run { send in
      let result = await Result {
        try await gameTimer.reconcile(gameID)
      }
      await send(.resumeGameResponse(gameID, result))
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

  private func append(
    _ destination: AppPath.State,
    to tab: Tab,
    state: inout State
  ) {
    switch tab {
    case .games:
      state.path.append(destination)
    case .settings:
      state.selectedTab = .games
      state.path.append(destination)
    case .teams:
      state.teamsPath.append(destination)
    }
  }

  private func deleteGameEffect(gameID: Game.ID) -> Effect<Action> {
    .run { send in
      await gameTimer.endPresentation(gameID)
      let result = await Result {
        try await database.write { db in
          try Game.find(gameID).delete().execute(db)
        }
      }
      await send(.deleteGameResponse(gameID, result))
    }
  }

  private func deleteTeamEffect(teamID: Team.ID) -> Effect<Action> {
    .run { send in
      let result = await Result {
        let gameIDs = try await database.read { db in
          try Game
            .where { $0.teamAID.eq(teamID) || $0.teamBID.eq(teamID) }
            .fetchAll(db)
            .map(\.id)
        }
        for gameID in gameIDs {
          await gameTimer.endPresentation(gameID)
        }
        try await database.write { db in
          try Team.find(teamID).delete().execute(db)
        }
      }
      await send(.deleteTeamResponse(teamID, result))
    }
  }

  private func gameID(from url: URL) -> Game.ID? {
    guard url.scheme == "supershot", url.host == "game" else { return nil }
    return UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }
}

extension AlertState where Action == AppFeature.Alert {
  static var gameUnavailable: Self {
    Self {
      TextState("Game unavailable")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      TextState("This unfinished game could not be opened.")
    }
  }

  static var gameDeletionFailed: Self {
    Self {
      TextState("Couldn’t delete game")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      TextState("Try again.")
    }
  }

  static var teamDeletionFailed: Self {
    Self {
      TextState("Couldn’t delete team")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      TextState("Try again.")
    }
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
