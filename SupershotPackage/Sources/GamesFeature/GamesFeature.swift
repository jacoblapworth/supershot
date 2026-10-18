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
import SQLiteData
import ScoringFeature
import SharedModels
import Styleguide
import SubscriptionClient

@Reducer
package enum GamesPath {
  case gameDetail(GameDetailFeature)
  case scoring(ScoringFeature)
  case setup(NewGameFeature)
}

extension GamesPath.State: Equatable {}

@Reducer
package struct GamesFeature {
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
    @Presents package var alert: AlertState<Alert>?
    package var path = StackState<GamesPath.State>()
    package var pendingGameResume: PendingGameResume?

    package func hasScoringRoute(for gameID: Game.ID) -> Bool {
      path.contains {
        guard case .scoring(let scoring) = $0 else { return false }
        return scoring.gameID == gameID
      }
    }

    package init(
      alert: AlertState<Alert>? = nil,
      path: StackState<GamesPath.State> = StackState<GamesPath.State>(),
      pendingGameResume: PendingGameResume? = nil
    ) {
      self.alert = alert
      self.path = path
      self.pendingGameResume = pendingGameResume
    }
  }

  package enum Action {
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)
    case deleteGameButtonTapped(Game.ID)
    case gameDeepLinkOpened(Game.ID)
    case gameRowTapped(GameListItem)
    case newGameButtonTapped
    case path(StackActionOf<GamesPath>)
    case proPromotionTapped
    case resumeGameResponse(PendingGameResume, Result<GameSnapshot, any Error>)

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
    Reduce { state, action in
      switch action {
      case .alert, .delegate:
        return .none

      case .deleteGameButtonTapped(let gameID):
        return deleteGameEffect(gameID: gameID)

      case .gameDeepLinkOpened(let gameID):
        for (id, destination) in zip(state.path.ids, state.path) {
          guard case .scoring(let scoring) = destination, scoring.gameID == gameID else {
            continue
          }
          state.path.pop(to: id)
          return .send(
            .path(.element(id: id, action: .scoring(.sceneBecameActive)))
          )
        }
        state.alert = nil
        return resumeGame(gameID: gameID, state: &state)

      case .gameRowTapped(let game):
        guard !game.isCompleted else {
          state.path.append(
            .gameDetail(GameDetailFeature.State(gameID: game.id))
          )
          return .none
        }

        state.alert = nil
        return resumeGame(gameID: game.id, state: &state)

      case .newGameButtonTapped:
        state.path.append(.setup(NewGameFeature.State()))
        return .none

      case .path(.element(id: let id, action: .scoring(.delegate(.gameFinished(let gameID))))):
        state.path.pop(from: id)
        state.path.append(
          .gameDetail(GameDetailFeature.State(gameID: gameID))
        )
        return .none

      case .path(.element(id: let id, action: .setup(.delegate(.gameStarted(let scoring))))):
        state.path.pop(from: id)
        state.path.append(.scoring(scoring))
        return .none

      case .path(.element(id: let id, action: .gameDetail(.delegate(.deleteGameButtonTapped)))):
        guard case .gameDetail(let gameDetail) = state.path[id: id] else {
          return .none
        }
        let gameID = gameDetail.gameID
        state.path.pop(from: id)
        return .send(.deleteGameButtonTapped(gameID))

      case .path(.element(id: _, action: .setup(.delegate(.proPromotionTapped)))),
        .path(.element(id: _, action: .scoring(.delegate(.proPromotionTapped)))):
        return .send(.delegate(.proPromotionTapped))

      case .path:
        return .none

      case .proPromotionTapped:
        return .send(.delegate(.proPromotionTapped))

      case .resumeGameResponse(let request, .success(let snapshot)):
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

      case .resumeGameResponse(let request, .failure):
        guard state.pendingGameResume == request else { return .none }
        state.pendingGameResume = nil
        state.alert = .gameUnavailable
        return .none
      }
    }
    .forEach(\.path, action: \.path) {
      GamesPath.body
    }
    .ifLet(\.$alert, action: \.alert)
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

  package init() {

  }
}

extension AlertState where Action == GamesFeature.Alert {
  static package var gameUnavailable: Self {
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
