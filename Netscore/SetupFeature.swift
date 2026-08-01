import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct SetupFeature {
  @ObservableState
  struct State: Equatable {
    var errorMessage: String?
    var isSaving = false
    var teamAName = "Team A"
    var teamBName = "Team B"

    var canStartGame: Bool {
      !trimmedTeamAName.isEmpty
        && !trimmedTeamBName.isEmpty
        && trimmedTeamAName.localizedCaseInsensitiveCompare(trimmedTeamBName) != .orderedSame
        && !isSaving
    }

    var trimmedTeamAName: String {
      teamAName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTeamBName: String {
      teamBName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case startGameButtonTapped
    case startGameResponse(Result<ScoringFeature.State, any Error>)

    enum Delegate {
      case gameStarted(ScoringFeature.State)
    }
  }

  @Dependency(\.date.now) var now
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.errorMessage = nil
        return .none

      case .delegate:
        return .none

      case .startGameButtonTapped:
        guard state.canStartGame else {
          state.errorMessage = "Enter two different team names."
          return .none
        }

        state.errorMessage = nil
        state.isSaving = true
        return startGameEffect(
          teamAName: state.trimmedTeamAName,
          teamBName: state.trimmedTeamBName
        )

      case let .startGameResponse(.success(scoring)):
        state.isSaving = false
        return .send(.delegate(.gameStarted(scoring)))

      case .startGameResponse(.failure):
        state.errorMessage = "Could not start the game."
        state.isSaving = false
        return .none
      }
    }
  }

  private func startGameEffect(
    teamAName: String,
    teamBName: String
  ) -> Effect<Action> {
    let gameID = uuid()
    let startedAt = now
    let teamAID = uuid()
    let teamBID = uuid()
    let teamA = Team(id: teamAID, name: teamAName)
    let teamB = Team(id: teamBID, name: teamBName)
    let periodDurationSeconds = ScoringFeature.State.defaultPeriodDurationSeconds
    let game = Game(
      id: gameID,
      startedAt: startedAt,
      endedAt: nil,
      teamAID: teamAID,
      teamBID: teamBID,
      periodDurationSeconds: periodDurationSeconds,
      currentPeriod: 1,
      elapsedSeconds: 0,
      hasTimerStartedCurrentPeriod: false
    )

    return .run { send in
      let result = await Result {
        try await database.write { db in
          try Team.insert {
            teamA
            teamB
          }
          .execute(db)

          try Game.insert {
            game
          }
          .execute(db)
        }

        return ScoringFeature.State(
          gameID: gameID,
          periodDurationSeconds: periodDurationSeconds,
          startedAt: startedAt,
          teamA: ScoringFeature.Team(id: teamAID, name: teamAName),
          teamB: ScoringFeature.Team(id: teamBID, name: teamBName)
        )
      }
      await send(.startGameResponse(result))
    }
  }
}
