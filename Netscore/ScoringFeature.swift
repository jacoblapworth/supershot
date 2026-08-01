import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct ScoringFeature {
  struct ScoreSnapshot: Equatable, Sendable {
    var canUndo = false
    var centrePassTeamID: Team.ID
    var teamAScore = 0
    var teamBScore = 0
  }

  struct QuarterSnapshot: Equatable, Sendable {
    var centrePassTeamID: Team.ID
    var elapsedSeconds: Int
    var hasTimerStartedThisPeriod: Bool
    var period: Int
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
    var centrePassTeamID: Team.ID
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

    var centrePassTeam: Team {
      centrePassTeamID == teamB.id ? teamB : teamA
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
    case centrePassTeamButtonTapped(Team.ID)
    case centrePassTeamResponse(Result<Team.ID, any Error>)
    case closeButtonTapped
    case confirmationDialog(PresentationAction<ConfirmationDialogAction>)
    case delegate(Delegate)
    case finishGameButtonTapped
    case finishGameResponse(Result<Game.ID, any Error>)
    case goalButtonTapped(Team.ID)
    case goalResponse(Result<ScoreSnapshot, any Error>)
    case nextQuarterButtonTapped
    case nextQuarterResponse(Result<QuarterSnapshot, any Error>)
    case pauseTimerButtonTapped
    case resumeTimerButtonTapped
    case sceneBecameInactive
    case startTimerButtonTapped
    case timerTick
    case undoButtonTapped
    case undoResponse(Result<ScoreSnapshot, any Error>)

    enum Delegate {
      case gameFinished(Game.ID)
    }
  }

  enum ConfirmationDialogAction: Equatable {
    case lastCentrePassNotTakenButtonTapped
    case lastCentrePassTakenButtonTapped
    case recordGoalButtonTapped
  }

  private nonisolated enum CancelID: Hashable, Sendable {
    case timer
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.dismiss) var dismiss
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .centrePassTeamButtonTapped(teamID):
        guard teamID == state.teamA.id || teamID == state.teamB.id else { return .none }
        guard teamID != state.centrePassTeamID else { return .none }
        return updateCentrePassEffect(gameID: state.gameID, teamID: teamID)

      case let .centrePassTeamResponse(.success(teamID)):
        guard teamID == state.teamA.id || teamID == state.teamB.id else { return .none }
        state.centrePassTeamID = teamID
        return .none

      case .centrePassTeamResponse(.failure):
        return .none

      case .closeButtonTapped:
        state.isTimerRunning = false
        return .concatenate(
          .cancel(id: CancelID.timer),
          saveProgressEffect(state: state),
          .run { _ in await dismiss() }
        )

      case .confirmationDialog(.dismiss):
        state.pendingPausedGoalTeamID = nil
        return .none

      case .confirmationDialog(.presented(.lastCentrePassNotTakenButtonTapped)):
        state.confirmationDialog = nil
        return nextQuarterEffect(state: state, wasLastCentrePassTaken: false)

      case .confirmationDialog(.presented(.lastCentrePassTakenButtonTapped)):
        state.confirmationDialog = nil
        return nextQuarterEffect(state: state, wasLastCentrePassTaken: true)

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

      case let .finishGameResponse(.success(gameID)):
        return .send(.delegate(.gameFinished(gameID)))

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
        state.confirmationDialog = .lastCentrePassConfirmation(
          teamName: state.centrePassTeam.name
        )
        return .none

      case let .nextQuarterResponse(.success(snapshot)):
        state.centrePassTeamID = snapshot.centrePassTeamID
        state.elapsedSeconds = snapshot.elapsedSeconds
        state.hasTimerStartedThisPeriod = snapshot.hasTimerStartedThisPeriod
        state.isTimerRunning = false
        state.period = snapshot.period
        return .cancel(id: CancelID.timer)

      case .nextQuarterResponse(.failure):
        return .none

      case .pauseTimerButtonTapped:
        state.isTimerRunning = false
        return .merge(
          .cancel(id: CancelID.timer),
          saveProgressEffect(state: state)
        )

      case .resumeTimerButtonTapped:
        guard !state.isTimerRunning, !state.isPeriodComplete else { return .none }
        state.hasTimerStartedThisPeriod = true
        state.isTimerRunning = true
        return .merge(
          saveProgressEffect(state: state),
          timerEffect()
        )

      case .sceneBecameInactive:
        guard state.isTimerRunning else { return .none }
        state.isTimerRunning = false
        return .merge(
          .cancel(id: CancelID.timer),
          saveProgressEffect(state: state)
        )

      case .startTimerButtonTapped:
        guard !state.isTimerRunning, state.elapsedSeconds == 0 else { return .none }
        state.hasTimerStartedThisPeriod = true
        state.isTimerRunning = true
        return .merge(
          saveProgressEffect(state: state),
          timerEffect()
        )

      case .timerTick:
        guard state.isTimerRunning else { return .none }
        state.elapsedSeconds += 1
        guard state.elapsedSeconds < state.periodDurationSeconds else {
          state.elapsedSeconds = state.periodDurationSeconds
          state.isTimerRunning = false
          return .merge(
            .cancel(id: CancelID.timer),
            saveProgressEffect(state: state)
          )
        }
        return saveProgressEffect(state: state)

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
    state.centrePassTeamID = snapshot.centrePassTeamID
    state.teamAScore = snapshot.teamAScore
    state.teamBScore = snapshot.teamBScore
  }

  private func finishGameEffect(state: State) -> Effect<Action> {
    let endedAt = now
    let gameID = state.gameID
    let currentPeriod = state.period
    let elapsedSeconds = state.elapsedSeconds
    let hasTimerStartedCurrentPeriod = state.hasTimerStartedThisPeriod

    return .run { send in
      let result = await Result {
        try await database.write { db in
          guard try Game.find(gameID).fetchOne(db) != nil else {
            throw ScoringPersistenceError.gameNotFound
          }
          try Game.find(gameID).update {
            $0.currentPeriod = currentPeriod
            $0.elapsedSeconds = elapsedSeconds
            $0.endedAt = #bind(endedAt)
            $0.hasTimerStartedCurrentPeriod = hasTimerStartedCurrentPeriod
          }
          .execute(db)
        }
        return gameID
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
          guard let game = try Game.find(gameID).fetchOne(db) else {
            throw ScoringPersistenceError.gameNotFound
          }
          let centrePassTeamID = resolvedCentrePassTeamID(
            game.centrePassTeamID,
            teamAID: teamAID,
            teamBID: teamBID
          )
          let nextCentrePassTeamID = opposingTeamID(
            centrePassTeamID,
            teamAID: teamAID,
            teamBID: teamBID
          )

          try Goal.insert {
            goal
          }
          .execute(db)

          try Game.find(gameID).update {
            $0.centrePassTeamID = #bind(nextCentrePassTeamID)
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

  private func saveProgressEffect(state: State) -> Effect<Action> {
    let currentPeriod = state.period
    let elapsedSeconds = state.elapsedSeconds
    let gameID = state.gameID
    let hasTimerStartedCurrentPeriod = state.hasTimerStartedThisPeriod

    return .run { _ in
      try? await database.write { db in
        try Game.find(gameID).update {
          $0.currentPeriod = currentPeriod
          $0.elapsedSeconds = elapsedSeconds
          $0.hasTimerStartedCurrentPeriod = hasTimerStartedCurrentPeriod
        }
        .execute(db)
      }
    }
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

            guard let game = try Game.find(gameID).fetchOne(db) else {
              throw ScoringPersistenceError.gameNotFound
            }
            let centrePassTeamID = resolvedCentrePassTeamID(
              game.centrePassTeamID,
              teamAID: teamAID,
              teamBID: teamBID
            )
            let nextCentrePassTeamID = opposingTeamID(
              centrePassTeamID,
              teamAID: teamAID,
              teamBID: teamBID
            )
            try Game.find(gameID).update {
              $0.centrePassTeamID = #bind(nextCentrePassTeamID)
            }
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

  private func nextQuarterEffect(
    state: State,
    wasLastCentrePassTaken: Bool
  ) -> Effect<Action> {
    let centrePassTeamID = wasLastCentrePassTaken
      ? opposingTeamID(
        state.centrePassTeamID,
        teamAID: state.teamA.id,
        teamBID: state.teamB.id
      )
      : state.centrePassTeamID
    let gameID = state.gameID
    let snapshot = QuarterSnapshot(
      centrePassTeamID: centrePassTeamID,
      elapsedSeconds: 0,
      hasTimerStartedThisPeriod: false,
      period: state.period + 1
    )

    return .run { send in
      let result = await Result {
        try await database.write { db in
          guard try Game.find(gameID).fetchOne(db) != nil else {
            throw ScoringPersistenceError.gameNotFound
          }
          try Game.find(gameID).update {
            $0.centrePassTeamID = #bind(snapshot.centrePassTeamID)
            $0.currentPeriod = snapshot.period
            $0.elapsedSeconds = snapshot.elapsedSeconds
            $0.hasTimerStartedCurrentPeriod = snapshot.hasTimerStartedThisPeriod
          }
          .execute(db)
        }
        return snapshot
      }
      await send(.nextQuarterResponse(result))
    }
  }

  private func updateCentrePassEffect(
    gameID: Game.ID,
    teamID: Team.ID
  ) -> Effect<Action> {
    .run { send in
      let result = await Result {
        try await database.write { db in
          guard try Game.find(gameID).fetchOne(db) != nil else {
            throw ScoringPersistenceError.gameNotFound
          }
          try Game.find(gameID).update {
            $0.centrePassTeamID = #bind(teamID)
          }
          .execute(db)
        }
        return teamID
      }
      await send(.centrePassTeamResponse(result))
    }
  }
}

extension ConfirmationDialogState where Action == ScoringFeature.ConfirmationDialogAction {
  static func lastCentrePassConfirmation(teamName: String) -> Self {
    Self {
      TextState("Last centre pass")
    } actions: {
      ButtonState(action: .lastCentrePassTakenButtonTapped) {
        TextState("Yes, pass taken")
      }
      ButtonState(action: .lastCentrePassNotTakenButtonTapped) {
        TextState("No, not taken")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Did \(teamName) take the last centre pass?")
    }
  }

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
    guard let game = try Game.find(gameID).fetchOne(db) else {
      throw ScoringPersistenceError.gameNotFound
    }
    let goals = try Goal
      .where { $0.gameID.eq(gameID) }
      .fetchAll(db)

    return Self(
      canUndo: !goals.isEmpty,
      centrePassTeamID: resolvedCentrePassTeamID(
        game.centrePassTeamID,
        teamAID: teamAID,
        teamBID: teamBID
      ),
      teamAScore: goals
        .filter { $0.teamID == teamAID }
        .reduce(0) { $0 + $1.points },
      teamBScore: goals
        .filter { $0.teamID == teamBID }
        .reduce(0) { $0 + $1.points }
    )
  }
}

private nonisolated enum ScoringPersistenceError: Error {
  case gameNotFound
}

private nonisolated func opposingTeamID(
  _ teamID: Team.ID,
  teamAID: Team.ID,
  teamBID: Team.ID
) -> Team.ID {
  teamID == teamAID ? teamBID : teamAID
}

private nonisolated func resolvedCentrePassTeamID(
  _ teamID: Team.ID?,
  teamAID: Team.ID,
  teamBID: Team.ID
) -> Team.ID {
  teamID == teamBID ? teamBID : teamAID
}
