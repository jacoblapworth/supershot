import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct ScoringFeature {
  nonisolated enum ClockPhase: Equatable, Sendable {
    case breakTime
    case quarter
  }

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

  struct LastCentrePassSnapshot: Equatable, Sendable {
    var advancesToNextQuarter: Bool
    var centrePassTeamID: Team.ID
  }

  struct Team: Equatable, Identifiable, Sendable {
    let id: UUID
    var colorHex = TeamColorPalette.blue
    var name: String
  }

  @ObservableState
  struct State: Equatable {
    static let defaultPeriodDurationSeconds = 15 * 60
    static let maximumPeriod = 4

    var canUndo = false
    var centrePassTeamID: Team.ID
    var clockPhase = ClockPhase.quarter
    @Presents var confirmationDialog: ConfirmationDialogState<ConfirmationDialogAction>?
    var elapsedSeconds = 0
    var firstBreakDurationSeconds = 0
    let gameID: Game.ID
    var halfTimeDurationSeconds = 0
    var hasTimerStartedThisPeriod = false
    var isShowingLastCentrePassBanner = false
    var isTimerRunning = false
    var isTransitioningPeriod = false
    var pendingPausedGoalTeamID: Team.ID?
    var period = 1
    var periodDurationSeconds = defaultPeriodDurationSeconds
    var secondBreakDurationSeconds = 0
    let startedAt: Date
    var teamA: Team
    var teamAScore = 0
    var teamB: Team
    var teamBScore = 0

    var canFinishGame: Bool {
      clockPhase == .quarter
        && period == Self.maximumPeriod
        && !isTimerRunning
        && !isShowingLastCentrePassBanner
        && hasTimerStartedThisPeriod
    }

    var centrePassTeam: Team {
      centrePassTeamID == teamB.id ? teamB : teamA
    }

    var canContinueToNextQuarter: Bool {
      clockPhase == .breakTime
        && !isTimerRunning
        && !isShowingLastCentrePassBanner
        && !isTransitioningPeriod
        && isPeriodComplete
    }

    var canMoveToNextQuarter: Bool {
      clockPhase == .quarter
        && period < Self.maximumPeriod
        && !isTimerRunning
        && !isShowingLastCentrePassBanner
        && hasTimerStartedThisPeriod
    }

    var currentDurationSeconds: Int {
      clockPhase == .breakTime ? breakDuration(after: period) : periodDurationSeconds
    }

    var isPeriodComplete: Bool {
      elapsedSeconds >= currentDurationSeconds
    }

    var isShowingOriginalTeamOrder: Bool {
      !period.isMultiple(of: 2)
    }

    var timeRemainingSeconds: Int {
      max(currentDurationSeconds - elapsedSeconds, 0)
    }

    func breakDuration(after period: Int) -> Int {
      switch period {
      case 1:
        firstBreakDurationSeconds
      case 2:
        halfTimeDurationSeconds
      case 3:
        secondBreakDurationSeconds
      default:
        0
      }
    }
  }

  enum Action {
    case centrePassTeamButtonTapped(Team.ID)
    case centrePassTeamResponse(Result<Team.ID, any Error>)
    case closeButtonTapped
    case confirmationDialog(PresentationAction<ConfirmationDialogAction>)
    case continueToNextQuarterButtonTapped
    case delegate(Delegate)
    case endQuarterButtonTapped
    case finishGameButtonTapped
    case finishGameResponse(Result<Game.ID, any Error>)
    case goalButtonTapped(Team.ID)
    case goalResponse(Result<ScoreSnapshot, any Error>)
    case lastCentrePassNotTakenButtonTapped
    case lastCentrePassResponse(Result<LastCentrePassSnapshot, any Error>)
    case lastCentrePassTakenButtonTapped
    case nextQuarterResponse(Result<QuarterSnapshot, any Error>)
    case pauseTimerButtonTapped
    case resumeTimerButtonTapped
    case sceneBecameInactive
    case skipBreakButtonTapped
    case startTimerButtonTapped
    case timerTick
    case undoButtonTapped
    case undoResponse(Result<ScoreSnapshot, any Error>)

    enum Delegate {
      case gameFinished(Game.ID)
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
  @Dependency(\.dismiss) var dismiss
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .centrePassTeamButtonTapped(teamID):
        guard state.clockPhase == .quarter, !state.isShowingLastCentrePassBanner else {
          return .none
        }
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

      case .confirmationDialog(.presented(.recordGoalButtonTapped)):
        guard let teamID = state.pendingPausedGoalTeamID else { return .none }
        state.confirmationDialog = nil
        state.pendingPausedGoalTeamID = nil
        return insertGoalEffect(state: state, teamID: teamID)

      case .continueToNextQuarterButtonTapped:
        guard state.canContinueToNextQuarter else { return .none }
        state.isTransitioningPeriod = true
        return nextQuarterEffect(state: state)

      case .delegate:
        return .none

      case .endQuarterButtonTapped:
        guard state.canMoveToNextQuarter else { return .none }
        return requestQuarterEnd(state: &state, timerEffectIsRunning: false)

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
        guard state.clockPhase == .quarter, !state.isShowingLastCentrePassBanner else {
          return .none
        }
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

      case .lastCentrePassNotTakenButtonTapped:
        guard state.isShowingLastCentrePassBanner, !state.isTransitioningPeriod else {
          return .none
        }
        state.isTransitioningPeriod = true
        return resolveLastCentrePassEffect(state: state, wasLastCentrePassTaken: false)

      case .lastCentrePassTakenButtonTapped:
        guard state.isShowingLastCentrePassBanner, !state.isTransitioningPeriod else {
          return .none
        }
        state.isTransitioningPeriod = true
        return resolveLastCentrePassEffect(state: state, wasLastCentrePassTaken: true)

      case let .lastCentrePassResponse(.success(snapshot)):
        state.centrePassTeamID = snapshot.centrePassTeamID
        state.isShowingLastCentrePassBanner = false
        state.isTransitioningPeriod = false
        guard snapshot.advancesToNextQuarter else { return .none }
        state.clockPhase = .quarter
        state.elapsedSeconds = 0
        state.hasTimerStartedThisPeriod = false
        state.isTimerRunning = false
        state.period += 1
        return .cancel(id: CancelID.timer)

      case .lastCentrePassResponse(.failure):
        state.isTransitioningPeriod = false
        return .none

      case let .nextQuarterResponse(.success(snapshot)):
        state.centrePassTeamID = snapshot.centrePassTeamID
        state.clockPhase = .quarter
        state.elapsedSeconds = snapshot.elapsedSeconds
        state.hasTimerStartedThisPeriod = snapshot.hasTimerStartedThisPeriod
        state.isTimerRunning = false
        state.isTransitioningPeriod = false
        state.period = snapshot.period
        return .cancel(id: CancelID.timer)

      case .nextQuarterResponse(.failure):
        state.isTransitioningPeriod = false
        return .none

      case .pauseTimerButtonTapped:
        state.isTimerRunning = false
        return .merge(
          .cancel(id: CancelID.timer),
          saveProgressEffect(state: state)
        )

      case .resumeTimerButtonTapped:
        guard
          !state.isTimerRunning,
          !state.isPeriodComplete,
          (!state.isShowingLastCentrePassBanner || state.clockPhase == .breakTime)
        else { return .none }
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

      case .skipBreakButtonTapped:
        guard
          state.clockPhase == .breakTime,
          !state.isShowingLastCentrePassBanner,
          !state.isTransitioningPeriod
        else { return .none }
        state.elapsedSeconds = state.currentDurationSeconds
        state.isTimerRunning = false
        state.isTransitioningPeriod = true
        return .concatenate(
          .cancel(id: CancelID.timer),
          nextQuarterEffect(state: state)
        )

      case .startTimerButtonTapped:
        guard
          !state.isTimerRunning,
          state.elapsedSeconds == 0,
          (!state.isShowingLastCentrePassBanner || state.clockPhase == .breakTime)
        else { return .none }
        state.hasTimerStartedThisPeriod = true
        state.isTimerRunning = true
        return .merge(
          saveProgressEffect(state: state),
          timerEffect()
        )

      case .timerTick:
        guard state.isTimerRunning else { return .none }
        state.elapsedSeconds += 1
        guard state.elapsedSeconds < state.currentDurationSeconds else {
          state.elapsedSeconds = state.currentDurationSeconds
          if state.clockPhase == .quarter, state.period < State.maximumPeriod {
            return requestQuarterEnd(state: &state, timerEffectIsRunning: true)
          }
          state.isTimerRunning = false
          return .merge(
            .cancel(id: CancelID.timer),
            saveProgressEffect(state: state)
          )
        }
        return saveProgressEffect(state: state)

      case .undoButtonTapped:
        guard state.canUndo, !state.isShowingLastCentrePassBanner else { return .none }
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

  private func requestQuarterEnd(
    state: inout State,
    timerEffectIsRunning: Bool
  ) -> Effect<Action> {
    state.isShowingLastCentrePassBanner = true
    let hasBreak = state.breakDuration(after: state.period) > 0
    guard hasBreak else {
      state.isTimerRunning = false
      return .merge(
        .cancel(id: CancelID.timer),
        saveProgressEffect(state: state)
      )
    }

    state.clockPhase = .breakTime
    state.elapsedSeconds = 0
    state.hasTimerStartedThisPeriod = true
    state.isTimerRunning = true
    if timerEffectIsRunning {
      return saveProgressEffect(state: state)
    }
    return .merge(
      saveProgressEffect(state: state),
      timerEffect()
    )
  }

  private func resolveLastCentrePassEffect(
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
    let advancesToNextQuarter = state.clockPhase == .quarter
    let gameID = state.gameID
    let nextPeriod = state.period + 1
    let snapshot = LastCentrePassSnapshot(
      advancesToNextQuarter: advancesToNextQuarter,
      centrePassTeamID: centrePassTeamID
    )

    return .run { send in
      let result = await Result {
        try await database.write { db in
          guard try Game.find(gameID).fetchOne(db) != nil else {
            throw ScoringPersistenceError.gameNotFound
          }
          if advancesToNextQuarter {
            try Game.find(gameID).update {
              $0.centrePassTeamID = #bind(snapshot.centrePassTeamID)
              $0.currentPeriod = nextPeriod
              $0.elapsedSeconds = 0
              $0.hasTimerStartedCurrentPeriod = false
              $0.isAwaitingCentrePassConfirmation = false
              $0.isInBreak = false
            }
            .execute(db)
          } else {
            try Game.find(gameID).update {
              $0.centrePassTeamID = #bind(snapshot.centrePassTeamID)
              $0.isAwaitingCentrePassConfirmation = false
            }
            .execute(db)
          }
        }
        return snapshot
      }
      await send(.lastCentrePassResponse(result))
    }
  }

  private func finishGameEffect(state: State) -> Effect<Action> {
    let endedAt = now
    let gameID = state.gameID
    let currentPeriod = state.period
    let elapsedSeconds = state.elapsedSeconds
    let hasTimerStartedCurrentPeriod = state.hasTimerStartedThisPeriod
    let isAwaitingCentrePassConfirmation = state.isShowingLastCentrePassBanner
    let isInBreak = state.clockPhase == .breakTime

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
            $0.isAwaitingCentrePassConfirmation = isAwaitingCentrePassConfirmation
            $0.isInBreak = isInBreak
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
    let isAwaitingCentrePassConfirmation = state.isShowingLastCentrePassBanner
    let isInBreak = state.clockPhase == .breakTime

    return .run { _ in
      try? await database.write { db in
        try Game.find(gameID).update {
          $0.currentPeriod = currentPeriod
          $0.elapsedSeconds = elapsedSeconds
          $0.hasTimerStartedCurrentPeriod = hasTimerStartedCurrentPeriod
          $0.isAwaitingCentrePassConfirmation = isAwaitingCentrePassConfirmation
          $0.isInBreak = isInBreak
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

  private func nextQuarterEffect(state: State) -> Effect<Action> {
    let gameID = state.gameID
    let snapshot = QuarterSnapshot(
      centrePassTeamID: state.centrePassTeamID,
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
            $0.isAwaitingCentrePassConfirmation = false
            $0.isInBreak = false
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
