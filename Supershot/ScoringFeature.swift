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
    var bibColorHex = TeamColorPalette.blue
    var name: String
  }

  @ObservableState
  struct State: Equatable {
    nonisolated static let defaultPeriodDurationSeconds = 15 * 60
    nonisolated static let maximumPeriod = 4

    @Presents var alert: AlertState<Alert>?
    var canUndo = false
    var centrePassTeamID: Team.ID
    var clockPhase = ClockPhase.quarter
    @Presents var confirmationDialog: ConfirmationDialogState<ConfirmationDialogAction>?
    var elapsedSeconds = 0
    var firstBreakDurationSeconds = 0
    let gameID: Game.ID
    var goalFeedbackTrigger = 0
    var halfTimeDurationSeconds = 0
    var hasTimerStartedThisPeriod = false
    var hasShownAlarmUnavailableAlert = false
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
    var timerEndsAt: Date?

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
    case alert(PresentationAction<Alert>)
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
    case sceneBecameActive
    case sceneBecameInactive
    case skipBreakButtonTapped
    case startTimerButtonTapped
    case timerTick
    case timerPauseResponse(Result<GameSnapshot, any Error>)
    case timerReconcileResponse(Result<GameSnapshot, any Error>)
    case timerStartResponse(Result<GameTimerUpdate, any Error>)
    case undoButtonTapped
    case undoResponse(Result<ScoreSnapshot, any Error>)

    enum Delegate {
      case gameFinished(Game.ID)
    }
  }

  enum Alert: Equatable {
    case dismissButtonTapped
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
  @Dependency(\.gameTimer) var gameTimer
  @Dependency(\.soundEffects) var soundEffects
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .alert:
        return .none

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
        synchronizeTimer(state: &state, now: now)
        return .concatenate(
          .cancel(id: CancelID.timer),
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
        synchronizeTimer(state: &state, now: now)
        state.isTimerRunning = false
        state.timerEndsAt = nil
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
        synchronizeTimer(state: &state, now: now)
        if state.isPeriodComplete, state.timerEndsAt == nil {
          return reconcileTimerEffect(gameID: state.gameID)
        }
        guard state.isTimerRunning else {
          state.confirmationDialog = .pausedGoalConfirmation
          state.pendingPausedGoalTeamID = teamID
          return .none
        }
        return insertGoalEffect(state: state, teamID: teamID)

      case let .goalResponse(.success(snapshot)):
        apply(snapshot, to: &state)
        state.goalFeedbackTrigger += 1
        return .merge(
          .run { _ in await soundEffects.playGoal() },
          refreshActivityEffect(gameID: state.gameID)
        )

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
        state.timerEndsAt = nil
        return .merge(
          .cancel(id: CancelID.timer),
          refreshActivityEffect(gameID: state.gameID)
        )

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
        state.timerEndsAt = nil
        return .merge(
          .cancel(id: CancelID.timer),
          refreshActivityEffect(gameID: state.gameID)
        )

      case .nextQuarterResponse(.failure):
        state.isTransitioningPeriod = false
        return .none

      case .pauseTimerButtonTapped:
        guard state.isTimerRunning else { return .none }
        synchronizeTimer(state: &state, now: now)
        state.isTimerRunning = false
        state.timerEndsAt = nil
        return .merge(
          .cancel(id: CancelID.timer),
          pauseTimerEffect(gameID: state.gameID, expectedPeriod: state.period)
        )

      case let .timerPauseResponse(.success(snapshot)):
        applyTimer(snapshot.game, to: &state)
        return .none

      case .timerPauseResponse(.failure):
        return .none

      case .sceneBecameActive:
        return reconcileTimerEffect(gameID: state.gameID)

      case .sceneBecameInactive:
        return .cancel(id: CancelID.timer)

      case .skipBreakButtonTapped:
        guard
          state.clockPhase == .breakTime,
          !state.isShowingLastCentrePassBanner,
          !state.isTransitioningPeriod
        else { return .none }
        synchronizeTimer(state: &state, now: now)
        state.elapsedSeconds = state.currentDurationSeconds
        state.isTimerRunning = false
        state.isTransitioningPeriod = true
        state.timerEndsAt = nil
        return .concatenate(
          .cancel(id: CancelID.timer),
          nextQuarterEffect(state: state)
        )

      case .startTimerButtonTapped:
        guard
          !state.isTimerRunning,
          !state.isPeriodComplete,
          (!state.isShowingLastCentrePassBanner || state.clockPhase == .breakTime)
        else { return .none }
        let requestsAuthorization = !state.hasTimerStartedThisPeriod
        state.hasTimerStartedThisPeriod = true
        state.isTimerRunning = true
        state.timerEndsAt = GameTimerMath.endDate(
          durationSeconds: state.currentDurationSeconds,
          elapsedSeconds: state.elapsedSeconds,
          now: now
        )
        return .merge(
          startTimerEffect(
            gameID: state.gameID,
            expectedPeriod: state.period,
            requestsAuthorization: requestsAuthorization
          ),
          timerEffect()
        )

      case .timerTick:
        guard state.isTimerRunning else { return .none }
        synchronizeTimer(state: &state, now: now)
        guard state.isPeriodComplete else { return .none }
        state.isTimerRunning = false
        state.timerEndsAt = nil
        return .merge(
          .cancel(id: CancelID.timer),
          reconcileTimerEffect(gameID: state.gameID)
        )

      case let .timerReconcileResponse(.success(snapshot)):
        applyTimer(snapshot.game, to: &state)
        guard state.isTimerRunning else { return .cancel(id: CancelID.timer) }
        return timerEffect()

      case .timerReconcileResponse(.failure):
        return .none

      case let .timerStartResponse(.success(update)):
        applyTimer(update.snapshot.game, to: &state)
        if update.alarmAuthorizationDenied, !state.hasShownAlarmUnavailableAlert {
          state.alert = .alarmUnavailable
          state.hasShownAlarmUnavailableAlert = true
        }
        return .none

      case .timerStartResponse(.failure):
        return .none

      case .undoButtonTapped:
        guard state.canUndo, !state.isShowingLastCentrePassBanner else { return .none }
        return undoGoalEffect(state: state)

      case let .undoResponse(.success(snapshot)):
        apply(snapshot, to: &state)
        return refreshActivityEffect(gameID: state.gameID)

      case .undoResponse(.failure):
        return .none

      }
    }
    .ifLet(\.$alert, action: \.alert)
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }

  private func apply(_ snapshot: ScoreSnapshot, to state: inout State) {
    state.canUndo = snapshot.canUndo
    state.centrePassTeamID = snapshot.centrePassTeamID
    state.teamAScore = snapshot.teamAScore
    state.teamBScore = snapshot.teamBScore
  }

  private func applyTimer(_ game: Game, to state: inout State) {
    state.clockPhase = game.isInBreak ? .breakTime : .quarter
    state.elapsedSeconds = game.elapsedSeconds
    state.hasTimerStartedThisPeriod = game.hasTimerStartedCurrentPeriod
    state.isShowingLastCentrePassBanner = game.isAwaitingCentrePassConfirmation
    state.isTimerRunning = game.timerEndsAt != nil
    state.period = game.currentPeriod
    state.timerEndsAt = game.timerEndsAt
  }

  private func requestQuarterEnd(
    state: inout State,
    timerEffectIsRunning: Bool
  ) -> Effect<Action> {
    state.isShowingLastCentrePassBanner = true
    let hasBreak = state.breakDuration(after: state.period) > 0
    guard hasBreak else {
      state.isTimerRunning = false
      state.timerEndsAt = nil
      return .merge(
        .cancel(id: CancelID.timer),
        saveProgressEffect(state: state)
      )
    }

    state.clockPhase = .breakTime
    state.elapsedSeconds = 0
    state.hasTimerStartedThisPeriod = true
    state.isTimerRunning = true
    state.timerEndsAt = GameTimerMath.endDate(
      durationSeconds: state.currentDurationSeconds,
      elapsedSeconds: state.elapsedSeconds,
      now: now
    )
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
              $0.timerEndsAt = #bind(nil as Date?)
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
        await gameTimer.refreshActivity(gameID)
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
            $0.timerEndsAt = #bind(nil as Date?)
          }
          .execute(db)
        }
        await gameTimer.endPresentation(gameID)
        return gameID
      }
      await send(.finishGameResponse(result))
    }
  }

  private func insertGoalEffect(state: State, teamID: Team.ID) -> Effect<Action> {
    let createdAt = now
    let elapsedSeconds = state.elapsedSeconds
    let gameID = state.gameID
    let goalID = uuid()
    let period = state.period
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
          let goal = Goal(
            id: goalID,
            gameID: gameID,
            centrePassTeamID: centrePassTeamID,
            teamID: teamID,
            period: period,
            elapsedSeconds: elapsedSeconds,
            points: 1,
            createdAt: createdAt
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
    let timerEndsAt = state.timerEndsAt

    return .run { _ in
      await gameTimer.cancelAlert(gameID)
      try? await database.write { db in
        try Game.find(gameID).update {
          $0.currentPeriod = currentPeriod
          $0.elapsedSeconds = elapsedSeconds
          $0.hasTimerStartedCurrentPeriod = hasTimerStartedCurrentPeriod
          $0.isAwaitingCentrePassConfirmation = isAwaitingCentrePassConfirmation
          $0.isInBreak = isInBreak
          $0.timerEndsAt = #bind(timerEndsAt)
        }
        .execute(db)
      }
      if timerEndsAt != nil {
        _ = try? await gameTimer.startOrResume(gameID, currentPeriod, false)
      } else {
        await gameTimer.refreshActivity(gameID)
      }
    }
  }

  private func pauseTimerEffect(
    gameID: Game.ID,
    expectedPeriod: Int
  ) -> Effect<Action> {
    .run { send in
      await send(
        .timerPauseResponse(
          await Result {
            try await gameTimer.pause(gameID, expectedPeriod)
          }
        )
      )
    }
  }

  private func reconcileTimerEffect(gameID: Game.ID) -> Effect<Action> {
    .run { send in
      await send(
        .timerReconcileResponse(
          await Result {
            try await gameTimer.reconcile(gameID)
          }
        )
      )
    }
  }

  private func refreshActivityEffect(gameID: Game.ID) -> Effect<Action> {
    .run { _ in
      await gameTimer.refreshActivity(gameID)
    }
  }

  private func startTimerEffect(
    gameID: Game.ID,
    expectedPeriod: Int,
    requestsAuthorization: Bool
  ) -> Effect<Action> {
    .run { send in
      await send(
        .timerStartResponse(
          await Result {
            try await gameTimer.startOrResume(
              gameID,
              expectedPeriod,
              requestsAuthorization
            )
          }
        )
      )
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
            $0.timerEndsAt = #bind(nil as Date?)
          }
          .execute(db)
        }
        await gameTimer.refreshActivity(gameID)
        return snapshot
      }
      await send(.nextQuarterResponse(result))
    }
  }

  private func synchronizeTimer(state: inout State, now: Date) {
    state.elapsedSeconds = GameTimerMath.elapsedSeconds(
      durationSeconds: state.currentDurationSeconds,
      persistedElapsedSeconds: state.elapsedSeconds,
      timerEndsAt: state.timerEndsAt,
      now: now
    )
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

extension AlertState where Action == ScoringFeature.Alert {
  static var alarmUnavailable: Self {
    Self {
      TextState("Quarter alerts unavailable")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      TextState(
        "The game timer will keep running, but Supershot cannot show a prominent quarter-end alert. You can allow alarms in Settings."
      )
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
