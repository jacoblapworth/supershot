import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
enum AppPath {
  case gameDetail(GameDetailFeature)
  case scoring(ScoringFeature)
  case setup(SetupFeature)
}

extension AppPath.State: Equatable {}

@Reducer
struct AppFeature {
  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Alert>?
    var loadingGameID: Game.ID?
    var path = StackState<AppPath.State>()
  }

  enum Action {
    case alert(PresentationAction<Alert>)
    case gameRowTapped(GameListItem)
    case newGameButtonTapped
    case path(StackActionOf<AppPath>)
    case resumeGameResponse(Game.ID, Result<GameSnapshot, any Error>)
  }

  enum Alert: Equatable {
    case dismissButtonTapped
  }

  @Dependency(\.defaultDatabase) var database

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .alert:
        return .none

      case let .gameRowTapped(game):
        guard !game.isCompleted else {
          state.path.append(
            .gameDetail(GameDetailFeature.State(gameID: game.id))
          )
          return .none
        }

        state.alert = nil
        state.loadingGameID = game.id
        return resumeGameEffect(gameID: game.id)

      case .newGameButtonTapped:
        state.path.append(.setup(SetupFeature.State()))
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

      case .path:
        return .none

      case let .resumeGameResponse(gameID, .success(snapshot)):
        guard state.loadingGameID == gameID else { return .none }
        state.loadingGameID = nil

        guard snapshot.game.endedAt == nil else {
          state.path.append(
            .gameDetail(GameDetailFeature.State(gameID: gameID))
          )
          return .none
        }

        state.path.append(.scoring(ScoringFeature.State(snapshot: snapshot)))
        return .none

      case let .resumeGameResponse(gameID, .failure):
        guard state.loadingGameID == gameID else { return .none }
        state.loadingGameID = nil
        state.alert = .gameUnavailable
        return .none
      }
    }
    .forEach(\.path, action: \.path) {
      AppPath.body
    }
    .ifLet(\.$alert, action: \.alert)
  }

  private func resumeGameEffect(gameID: Game.ID) -> Effect<Action> {
    .run { send in
      let result = await Result {
        try await database.read { db in
          try GameSnapshot.fetch(db, gameID: gameID)
        }
      }
      await send(.resumeGameResponse(gameID, result))
    }
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
}

extension ScoringFeature.State {
  init(snapshot: GameSnapshot) {
    self.init(
      canUndo: !snapshot.goals.isEmpty,
      centrePassTeamID: snapshot.game.centrePassTeamID == snapshot.teamB.id
        ? snapshot.teamB.id
        : snapshot.teamA.id,
      elapsedSeconds: min(
        max(snapshot.game.elapsedSeconds, 0),
        snapshot.game.periodDurationSeconds
      ),
      gameID: snapshot.game.id,
      hasTimerStartedThisPeriod: snapshot.game.hasTimerStartedCurrentPeriod,
      period: min(
        max(snapshot.game.currentPeriod, 1),
        Self.maximumPeriod
      ),
      periodDurationSeconds: snapshot.game.periodDurationSeconds,
      startedAt: snapshot.game.startedAt,
      teamA: ScoringFeature.Team(
        id: snapshot.teamA.id,
        name: snapshot.teamA.name
      ),
      teamAScore: snapshot.teamAScore,
      teamB: ScoringFeature.Team(
        id: snapshot.teamB.id,
        name: snapshot.teamB.name
      ),
      teamBScore: snapshot.teamBScore
    )
  }
}
