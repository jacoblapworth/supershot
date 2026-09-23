import ComposableArchitecture
import Foundation
import IssueReporting
import SQLiteData

@Reducer
enum GamesPath {
  case gameDetail(GameDetailFeature)
  case scoring(ScoringFeature)
  case setup(NewGameFeature)
}

extension GamesPath.State: Equatable {}

@Reducer
struct GamesFeature {
  struct PendingGameResume: Equatable, Sendable {
    let gameID: Game.ID
    let requestID: UUID
  }

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Alert>?
    var path = StackState<GamesPath.State>()
    var pendingGameResume: PendingGameResume?

    func hasScoringRoute(for gameID: Game.ID) -> Bool {
      path.contains {
        guard case let .scoring(scoring) = $0 else { return false }
        return scoring.gameID == gameID
      }
    }
  }

  enum Action {
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)
    case deleteGameButtonTapped(Game.ID)
    case gameDeepLinkOpened(Game.ID)
    case gameRowTapped(GameListItem)
    case newGameButtonTapped
    case path(StackActionOf<GamesPath>)
    case proPromotionTapped
    case resumeGameResponse(PendingGameResume, Result<GameSnapshot, any Error>)

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
    Reduce { state, action in
      switch action {
      case .alert, .delegate:
        return .none

      case let .deleteGameButtonTapped(gameID):
        return deleteGameEffect(gameID: gameID)

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
        state.alert = nil
        return resumeGame(gameID: gameID, state: &state)

      case let .gameRowTapped(game):
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

extension AlertState where Action == GamesFeature.Alert {
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
