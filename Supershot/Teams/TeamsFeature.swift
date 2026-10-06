import ComposableArchitecture
import Foundation
import IssueReporting
import SQLiteData

@Reducer
enum TeamsPath {
  case gameDetail(GameDetailFeature)
  case scoring(ScoringFeature)
  case setup(NewGameFeature)
  case teamDetail(TeamDetailFeature)
}

extension TeamsPath.State: Equatable {}

@Reducer
struct TeamsFeature {
  struct PendingGameResume: Equatable, Sendable {
    let gameID: Game.ID
    let requestID: UUID
  }

  @ObservableState
  struct State: Equatable {
    @Presents var destination: TeamsDestination.State?
    var path = StackState<TeamsPath.State>()
    var pendingGameResume: PendingGameResume?
    var searchText = ""

    mutating func clearResumeAlert() {
      switch destination {
      case .alert:
        destination = nil
      case var .teamEditor(editor):
        editor.alert = nil
        destination = .teamEditor(editor)
      case nil:
        break
      }
    }

    func filteredTeams(in teams: [TeamListItem]) -> [TeamListItem] {
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else { return teams }
      return teams.filter {
        $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }

    func hasScoringRoute(for gameID: Game.ID) -> Bool {
      path.contains {
        guard case let .scoring(scoring) = $0 else { return false }
        return scoring.gameID == gameID
      }
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case destination(PresentationAction<TeamsDestination.Action>)
    case deleteGameButtonTapped(Game.ID)
    case deleteTeamButtonTapped(Team.ID)
    case gameDeepLinkOpened(Game.ID)
    case newTeamButtonTapped
    case path(StackActionOf<TeamsPath>)
    case proPromotionTapped
    case resumeGameResponse(PendingGameResume, Result<GameSnapshot, any Error>)
    case teamGameRowTapped(GameListItem)
    case teamRowTapped(TeamListItem)

    enum Delegate {
      case proPromotionTapped
    }
  }

  enum Alert: Equatable {
    case dismissButtonTapped
  }

  private nonisolated enum CancelID: Hashable, Sendable {
    case resumeGame
  }

  @Dependency(\.defaultDatabase) var database
  @Dependency(\.gameTimer) var gameTimer
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding, .delegate:
        return .none

      case let .deleteGameButtonTapped(gameID):
        return deleteGameEffect(gameID: gameID)

      case let .deleteTeamButtonTapped(teamID):
        return deleteTeamEffect(teamID: teamID)

      case let .gameDeepLinkOpened(gameID):
        for (id, destination) in zip(state.path.ids, state.path) {
          guard case let .scoring(scoring) = destination, scoring.gameID == gameID else {
            continue
          }
          state.path.pop(to: id)
          return .send(
            .path(.element(id: id, action: .scoring(.sceneBecameActive)))
          )
        }
        state.clearResumeAlert()
        return resumeGame(gameID: gameID, state: &state)

      case .newTeamButtonTapped:
        state.destination = .teamEditor(TeamsEditorFeature.State())
        return .none

      case let .path(
        .element(id: id, action: .gameDetail(.delegate(.deleteGameButtonTapped)))
      ):
        guard case let .gameDetail(gameDetail) = state.path[id: id] else {
          return .none
        }
        let gameID = gameDetail.gameID
        state.path.pop(from: id)
        return .send(.deleteGameButtonTapped(gameID))

      case let .path(
        .element(id: id, action: .teamDetail(.delegate(.deleteTeamButtonTapped)))
      ):
        guard case let .teamDetail(teamDetail) = state.path[id: id] else {
          return .none
        }
        let teamID = teamDetail.teamID
        state.path.pop(from: id)
        return .send(.deleteTeamButtonTapped(teamID))

      case let .path(
        .element(id: id, action: .scoring(.delegate(.gameFinished(gameID))))
      ):
        state.path.pop(from: id)
        state.path.append(
          .gameDetail(GameDetailFeature.State(gameID: gameID))
        )
        return .none

      case let .path(
        .element(id: _, action: .teamDetail(.delegate(.gameRowTapped(game))))
      ):
        return .send(.teamGameRowTapped(game))

      case let .path(
        .element(id: _, action: .teamDetail(.delegate(.newGameButtonTapped(team))))
      ):
        var setup = NewGameFeature.State()
        setup.leftTeam.team = team
        setup.leftTeam.bibColor = team.color
        state.path.append(.setup(setup))
        return .none

      case let .path(.element(id: id, action: .setup(.delegate(.gameStarted(scoring))))):
        state.path.pop(from: id)
        state.path.append(.scoring(scoring))
        return .none

      case .path:
        return .none

      case .proPromotionTapped:
        return .send(.delegate(.proPromotionTapped))

      case let .resumeGameResponse(request, .success(snapshot)):
        guard state.pendingGameResume == request else { return .none }
        state.pendingGameResume = nil

        if snapshot.game.endedAt == nil {
          state.path.append(.scoring(ScoringFeature.State(snapshot: snapshot)))
        } else {
          state.path.append(
            .gameDetail(GameDetailFeature.State(gameID: request.gameID))
          )
        }
        return .none

      case let .resumeGameResponse(request, .failure):
        guard state.pendingGameResume == request else { return .none }
        state.pendingGameResume = nil
        if case var .teamEditor(editor) = state.destination {
          editor.alert = .gameUnavailable
          state.destination = .teamEditor(editor)
        } else {
          state.destination = .alert(.gameUnavailable)
        }
        return .none

      case .destination(.presented(.teamEditor(.editor(.delegate(.cancelled))))),
        .destination(.presented(.teamEditor(.editor(.delegate(.saved(_)))))):
        state.destination = nil
        return .none

      case .destination:
        return .none

      case let .teamGameRowTapped(game):
        guard !game.isCompleted else {
          state.path.append(
            .gameDetail(GameDetailFeature.State(gameID: game.id))
          )
          return .none
        }

        state.clearResumeAlert()
        return resumeGame(gameID: game.id, state: &state)

      case let .teamRowTapped(team):
        state.path.append(
          .teamDetail(TeamDetailFeature.State(teamID: team.id))
        )
        return .none
      }
    }
    .forEach(\.path, action: \.path) {
      TeamsPath.body
    }
    .ifLet(\.$destination, action: \.destination) {
      TeamsDestination.body
    }
  }

  private func deleteGameEffect(gameID: Game.ID) -> Effect<Action> {
    .run { _ in
      let didDelete = await withErrorReporting {
        try await database.write { db in
          try Game.find(gameID).delete().execute(db)
        }
        return true
      } ?? false
      if didDelete {
        await gameTimer.endPresentation(gameID)
      }
    }
  }

  private func deleteTeamEffect(teamID: Team.ID) -> Effect<Action> {
    .run { _ in
      let gameIDs = await withErrorReporting {
        try await database.write { db in
          let gameIDs = try Game
            .where { $0.teamAID.eq(teamID) || $0.teamBID.eq(teamID) }
            .fetchAll(db)
            .map(\.id)
          try Team.find(teamID).delete().execute(db)
          return gameIDs
        }
      }
      for gameID in gameIDs ?? [] {
        await gameTimer.endPresentation(gameID)
      }
    }
  }

  private func resumeGame(
    gameID: Game.ID,
    state: inout State
  ) -> Effect<Action> {
    let request = PendingGameResume(
      gameID: gameID,
      requestID: uuid()
    )
    state.pendingGameResume = request
    return .run { send in
      let result = await Result {
        try await gameTimer.reconcile(request.gameID)
      }
      await send(.resumeGameResponse(request, result))
    }
    .cancellable(id: CancelID.resumeGame, cancelInFlight: true)
  }
}

extension AlertState where Action == TeamsFeature.Alert {
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
}
