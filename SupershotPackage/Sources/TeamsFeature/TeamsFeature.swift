import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameDetailFeature
import GameServices
import IssueReporting
import NewGameFeature
import PaywallFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import SQLiteData
import Styleguide
import SubscriptionClient
import TeamEditingFeature
import WidgetSupport

@Reducer
package enum TeamsPath {
  case gameDetail(GameDetailFeature)
  case scoring(ScoringFeature)
  case teamDetail(TeamDetailFeature)
}

extension TeamsPath.State: Equatable {}

@Reducer
package struct TeamsFeature {
  package struct PendingGameResume: Equatable, Sendable {
    package let gameID: Game.ID
    package let requestID: UUID

    package init(gameID: Game.ID, requestID: UUID) {
      self.gameID = gameID
      self.requestID = requestID
    }
  }

  @ObservableState
  package struct State: Equatable {
    @Presents package var destination: TeamsDestination.State?
    @Presents package var newGame: NewGameFeature.State?
    package var path = StackState<TeamsPath.State>()
    package var pendingGameResume: PendingGameResume?
    package var searchText = ""

    package mutating func clearResumeAlert() {
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

    package func filteredTeams(in teams: [TeamListItem]) -> [TeamListItem] {
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else { return teams }
      return teams.filter {
        $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }

    package func hasGameRoute(for gameID: Game.ID) -> Bool {
      newGame?.gameID == gameID || path.contains {
        switch $0 {
        case let .scoring(scoring): scoring.gameID == gameID
        case let .gameDetail(detail): detail.gameID == gameID
        default: false
        }
      }
    }

    package init(
      destination: TeamsDestination.State? = nil,
      path: StackState<TeamsPath.State> = StackState<TeamsPath.State>(),
      pendingGameResume: PendingGameResume? = nil, searchText: String = ""
    ) {
      self.destination = destination
      self.path = path
      self.pendingGameResume = pendingGameResume
      self.searchText = searchText
    }
  }

  package enum Action: BindableAction {
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case destination(PresentationAction<TeamsDestination.Action>)
    case deleteGameButtonTapped(Game.ID)
    case deleteTeamButtonTapped(Team.ID)
    case gameDeepLinkOpened(Game.ID)
    case newTeamButtonTapped
    case newGame(PresentationAction<NewGameFeature.Action>)
    case path(StackActionOf<TeamsPath>)
    case proPromotionTapped
    case setupExitSaveFailed(NewGameFeature.State)
    case resumeGameResponse(PendingGameResume, Result<GameSnapshot, any Error>)
    case teamGameRowTapped(GameListItem)
    case teamRowTapped(TeamListItem)

    package enum Delegate {
      case proPromotionTapped
    }
  }

  package enum Alert: Equatable {
    case dismissButtonTapped
  }

  private nonisolated enum CancelID: Hashable, Sendable {
    case resumeGame
  }

  @Dependency(\.defaultDatabase) package var database
  @Dependency(\.gameTimer) package var gameTimer
  @Dependency(\.uuid) package var uuid

  package var body: some Reducer<State, Action> {
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
        state.clearResumeAlert()
        return resumeGame(gameID: gameID, state: &state)

      case .newTeamButtonTapped:
        state.destination = .teamEditor(TeamsEditorFeature.State())
        return .none

      case .path(
        .element(id: let id, action: .gameDetail(.delegate(.deleteGameButtonTapped)))
      ):
        guard case let .gameDetail(gameDetail) = state.path[id: id] else {
          return .none
        }
        let gameID = gameDetail.gameID
        state.path.pop(from: id)
        return .send(.deleteGameButtonTapped(gameID))

      case .path(
        .element(id: let id, action: .teamDetail(.delegate(.deleteTeamButtonTapped)))
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

      case .path(
        .element(id: _, action: .teamDetail(.delegate(.gameRowTapped(let game))))
      ):
        return .send(.teamGameRowTapped(game))

      case .path(
        .element(id: _, action: .teamDetail(.delegate(.newGameButtonTapped(let team))))
      ):
        var setup = NewGameFeature.State()
        setup.leftTeam.team = team
        setup.leftTeam.bibColor = team.color
        state.newGame = setup
        return .none

      case let .newGame(.presented(.delegate(.scoringPrepared(scoring)))):
        state.newGame = nil
        state.path.append(.scoring(scoring))
        return .none

      case .newGame(.presented(.delegate(.gameSaved))):
        state.newGame = nil
        return .none

      case .newGame(.presented(.delegate(.proPromotionTapped))):
        return .send(.delegate(.proPromotionTapped))

      case .path(.element(id: _, action: .scoring(.delegate(.proPromotionTapped)))):
        return .send(.delegate(.proPromotionTapped))

      case var .setupExitSaveFailed(setup):
        setup.isSaving = false
        setup.inFlightDraft = nil
        setup.pendingSaveIntent = nil
        setup.closesAfterSave = true
        setup.failedSaveIntent = .close
        setup.errorMessage = "Could not save the game. Your changes are still here. Try again."
        state.newGame = setup
        return .none

      case .newGame(.dismiss):
        guard let setup = state.newGame, !setup.hasEnteredScoring, setup.describeGame.source.isEmpty,
              let draft = setup.draft, draft != setup.lastSavedDraft
        else { return .none }
        let requiresExistingGame = setup.requiresExistingGame
        // This parent-owned effect survives dismissal of the setup sheet and its effects.
        return .run { send in
          do {
            _ = try await database.write { db in
              try draft.save(db, requiresExistingGame: requiresExistingGame)
            }
          } catch {
            await send(.setupExitSaveFailed(setup))
          }
        }

      case .newGame:
        return .none

      case .path:
        return .none

      case .proPromotionTapped:
        return .send(.delegate(.proPromotionTapped))

      case let .resumeGameResponse(request, .success(snapshot)):
        guard state.pendingGameResume == request else { return .none }
        state.pendingGameResume = nil

        // Resolve the persisted status before reusing a route left open in a warm app.
        if state.newGame?.gameID == request.gameID {
          if snapshot.game.isPlanned { return .none }
          state.newGame = nil
        }
        for (id, destination) in zip(state.path.ids, state.path) {
          switch destination {
          case let .scoring(scoring) where scoring.gameID == request.gameID:
            if snapshot.game.isInProgress {
              state.path.pop(to: id)
              return .send(.path(.element(id: id, action: .scoring(.sceneBecameActive))))
            }
            state.path.pop(from: id)
          case let .gameDetail(detail) where detail.gameID == request.gameID:
            if (snapshot.game.endedAt != nil) {
              state.path.pop(to: id)
              return .none
            }
            state.path.pop(from: id)
          default:
            continue
          }
          break
        }

        if snapshot.game.isPlanned {
          state.newGame = NewGameFeature.State(snapshot: snapshot)
        } else if snapshot.game.isInProgress {
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
        if state.newGame?.gameID == request.gameID { state.newGame = nil }
        for (id, destination) in zip(state.path.ids, state.path) {
          let matches: Bool
          switch destination {
          case let .scoring(scoring): matches = scoring.gameID == request.gameID
          case let .gameDetail(detail): matches = detail.gameID == request.gameID
          default: matches = false
          }
          if matches {
            state.path.pop(from: id)
            break
          }
        }
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
    .ifLet(\.$newGame, action: \.newGame) {
      NewGameFeature()
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
      let didDelete =
        await withErrorReporting {
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
          let gameIDs =
            try Game
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
        let snapshot = try await database.read {
          try GameSnapshot.fetch($0, gameID: request.gameID)
        }
        if snapshot.game.isPlanned || (snapshot.game.endedAt != nil) {
          return snapshot
        }
        return try await gameTimer.reconcile(request.gameID)
      }
      await send(.resumeGameResponse(request, result))
    }
    .cancellable(id: CancelID.resumeGame, cancelInFlight: true)
  }

  package init() {}
}

package extension AlertState where Action == TeamsFeature.Alert {
  static var gameUnavailable: Self {
    Self {
      TextState("Game unavailable")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      TextState("This game could not be opened. It may have been deleted.")
    }
  }
}
