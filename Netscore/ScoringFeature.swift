import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct ScoringFeature {
  struct ScoreSnapshot: Equatable, Sendable {
    var canUndo = false
    var teamAScore = 0
    var teamBScore = 0
  }

  struct Team: Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
  }

  @ObservableState
  struct State: Equatable {
    static let defaultPeriodDurationSeconds = 15 * 60
    static let maximumPeriod = 4

    var canUndo = false
    @Presents var confirmationDialog: ConfirmationDialogState<ConfirmationDialogAction>?
    var elapsedSeconds = 0
    let gameID: Game.ID
    var hasTimerStartedThisPeriod = false
    var isTimerRunning = false
    var pendingPausedGoalTeamID: Team.ID?
    var period = 1
    var periodDurationSeconds = defaultPeriodDurationSeconds
    let startedAt: Date
    var teamA: Team
    var teamAScore = 0
    var teamB: Team
    var teamBScore = 0

    var canFinishGame: Bool {
      period == Self.maximumPeriod && !isTimerRunning && hasTimerStartedThisPeriod
    }

    var canMoveToNextQuarter: Bool {
      period < Self.maximumPeriod && !isTimerRunning && hasTimerStartedThisPeriod
    }

    var isPeriodComplete: Bool {
      elapsedSeconds >= periodDurationSeconds
    }

    var timeRemainingSeconds: Int {
      max(periodDurationSeconds - elapsedSeconds, 0)
    }
  }

  enum Action {
    case confirmationDialog(PresentationAction<ConfirmationDialogAction>)
    case delegate(Delegate)
    case finishGameButtonTapped
    case finishGameResponse(Result<SummaryFeature.State, any Error>)
    case goalButtonTapped(Team.ID)
    case goalResponse(Result<ScoreSnapshot, any Error>)
    case nextQuarterButtonTapped
    case pauseTimerButtonTapped
    case resumeTimerButtonTapped
    case startTimerButtonTapped
    case timerTick
    case undoButtonTapped
    case undoResponse(Result<ScoreSnapshot, any Error>)

    enum Delegate {
      case gameFinished(SummaryFeature.State)
    }
  }

  enum ConfirmationDialogAction: Equatable {
    case recordGoalButtonTapped
  }

  private nonisolated enum CancelID: Hashable, Sendable {
    case timer
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .confirmationDialog(.dismiss):
        state.pendingPausedGoalTeamID = nil
        return .none

      case .confirmationDialog(.presented(.recordGoalButtonTapped)):
        guard let teamID = state.pendingPausedGoalTeamID else { return .none }
        state.confirmationDialog = nil
        state.pendingPausedGoalTeamID = nil
        return insertGoalEffect(state: state, teamID: teamID)

      case .delegate:
        return .none

      case .finishGameButtonTapped:
        guard state.canFinishGame else { return .none }
        state.isTimerRunning = false
        return .merge(
          .cancel(id: CancelID.timer),
          finishGameEffect(state: state)
        )

      case let .finishGameResponse(.success(summary)):
        return .send(.delegate(.gameFinished(summary)))

      case .finishGameResponse(.failure):
        return .none

      case let .goalButtonTapped(teamID):
        guard teamID == state.teamA.id || teamID == state.teamB.id else { return .none }
        guard state.isTimerRunning else {
          state.confirmationDialog = .pausedGoalConfirmation
          state.pendingPausedGoalTeamID = teamID
          return .none
        }
        return insertGoalEffect(state: state, teamID: teamID)

      case let .goalResponse(.success(snapshot)):
        apply(snapshot, to: &state)
        return .none

      case .goalResponse(.failure):
        return .none

      case .nextQuarterButtonTapped:
        guard state.canMoveToNextQuarter else { return .none }
        state.elapsedSeconds = 0
        state.hasTimerStartedThisPeriod = false
        state.isTimerRunning = false
        state.period += 1
        return .cancel(id: CancelID.timer)

      case .pauseTimerButtonTapped:
        state.isTimerRunning = false
        return .cancel(id: CancelID.timer)

      case .resumeTimerButtonTapped:
        guard !state.isTimerRunning, !state.isPeriodComplete else { return .none }
        state.hasTimerStartedThisPeriod = true
        state.isTimerRunning = true
        return timerEffect()

      case .startTimerButtonTapped:
        guard !state.isTimerRunning, state.elapsedSeconds == 0 else { return .none }
        state.hasTimerStartedThisPeriod = true
        state.isTimerRunning = true
        return timerEffect()

      case .timerTick:
        guard state.isTimerRunning else { return .none }
        state.elapsedSeconds += 1
        guard state.elapsedSeconds < state.periodDurationSeconds else {
          state.elapsedSeconds = state.periodDurationSeconds
          state.isTimerRunning = false
          return .cancel(id: CancelID.timer)
        }
        return .none

      case .undoButtonTapped:
        guard state.canUndo else { return .none }
        return undoGoalEffect(state: state)

      case let .undoResponse(.success(snapshot)):
        apply(snapshot, to: &state)
        return .none

      case .undoResponse(.failure):
        return .none
      }
    }
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }

  private func apply(_ snapshot: ScoreSnapshot, to state: inout State) {
    state.canUndo = snapshot.canUndo
    state.teamAScore = snapshot.teamAScore
    state.teamBScore = snapshot.teamBScore
  }

  private func finishGameEffect(state: State) -> Effect<Action> {
    let endedAt = now
    let gameID = state.gameID
    let summary = SummaryFeature.State(
      endedAt: endedAt,
      startedAt: state.startedAt,
      teamAName: state.teamA.name,
      teamAScore: state.teamAScore,
      teamBName: state.teamB.name,
      teamBScore: state.teamBScore
    )

    return .run { send in
      let result = await Result {
        try await database.write { db in
          try Game.find(gameID).update {
            $0.endedAt = #bind(endedAt)
          }
          .execute(db)
        }
        return summary
      }
      await send(.finishGameResponse(result))
    }
  }

  private func insertGoalEffect(state: State, teamID: Team.ID) -> Effect<Action> {
    let goal = Goal(
      id: uuid(),
      gameID: state.gameID,
      teamID: teamID,
      period: state.period,
      elapsedSeconds: state.elapsedSeconds,
      points: 1,
      createdAt: now
    )
    let gameID = state.gameID
    let teamAID = state.teamA.id
    let teamBID = state.teamB.id

    return .run { send in
      let result = await Result {
        try await database.write { db in
          try Goal.insert {
            goal
          }
          .execute(db)

          return try ScoreSnapshot.fetch(
            db,
            gameID: gameID,
            teamAID: teamAID,
            teamBID: teamBID
          )
        }
      }
      await send(.goalResponse(result))
    }
  }

  private func timerEffect() -> Effect<Action> {
    .run { send in
      while !Task.isCancelled {
        try await clock.sleep(for: .seconds(1))
        await send(.timerTick)
      }
    }
    .cancellable(id: CancelID.timer, cancelInFlight: true)
  }

  private func undoGoalEffect(state: State) -> Effect<Action> {
    let gameID = state.gameID
    let teamAID = state.teamA.id
    let teamBID = state.teamB.id

    return .run { send in
      let result = await Result {
        try await database.write { db in
          let latestGoal = try Goal
            .where { goals in goals.gameID.eq(gameID) }
            .order { goals in (goals.createdAt.desc(), goals.id.desc()) }
            .fetchOne(db)

          if let latestGoal {
            try Goal.find(latestGoal.id)
              .delete()
              .execute(db)
          }

          return try ScoreSnapshot.fetch(
            db,
            gameID: gameID,
            teamAID: teamAID,
            teamBID: teamBID
          )
        }
      }
      await send(.undoResponse(result))
    }
  }
}

extension ConfirmationDialogState where Action == ScoringFeature.ConfirmationDialogAction {
  static var pausedGoalConfirmation: Self {
    Self {
      TextState("Timer paused")
    } actions: {
      ButtonState(action: .recordGoalButtonTapped) {
        TextState("Record goal")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Record goal while timer is paused?")
    }
  }
}

extension ScoringFeature.ScoreSnapshot {
  nonisolated static func fetch(
    _ db: Database,
    gameID: Game.ID,
    teamAID: Team.ID,
    teamBID: Team.ID
  ) throws -> Self {
    let goals = try Goal
      .where { $0.gameID.eq(gameID) }
      .fetchAll(db)

    return Self(
      canUndo: !goals.isEmpty,
      teamAScore: goals
        .filter { $0.teamID == teamAID }
        .reduce(0) { $0 + $1.points },
      teamBScore: goals
        .filter { $0.teamID == teamBID }
        .reduce(0) { $0 + $1.points }
    )
  }
}
