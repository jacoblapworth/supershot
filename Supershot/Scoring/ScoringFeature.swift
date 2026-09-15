import ComposableArchitecture
import Foundation
import Sharing
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

  struct LastCentrePassSnapshot: Equatable, Sendable {
    var centrePassTeamID: Team.ID
  }

  struct Team: Equatable, Identifiable, Sendable {
    let id: UUID
    var bibColorHex = TeamColorPalette.blue
    var name: String
  }

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Alert>?
    @Shared(.hapticsEnabled) var hapticsEnabled
    var canUndo = false
    var centrePassTeamID: Team.ID
    var currentPhaseIndex = 0
    var elapsedSeconds = 0
    let gameID: Game.ID
    var goalFeedbackTrigger = 0
    var hasShownAlarmUnavailableAlert = false
    var isShowingLastCentrePassBanner = false
    var isTransitioningPeriod = false
    var periods: [GamePeriod]
    @Shared(.soundEffectsEnabled) var soundEffectsEnabled
    let startedAt: Date
    var teamA: Team
    var teamAScore = 0
    var teamB: Team
    var teamBScore = 0
    var timerEndsAt: Date?

    var phases: [GamePhase] {
      gamePhases(for: periods)
    }

    var currentPhase: GamePhase {
      phases[Swift.min(Swift.max(currentPhaseIndex, 0), phases.count - 1)]
    }

    var countdown: GameCountdown {
      get { GameCountdown(elapsedSeconds: elapsedSeconds, endsAt: timerEndsAt) }
      set {
        elapsedSeconds = newValue.elapsedSeconds
        timerEndsAt = newValue.endsAt
      }
    }

    var clockPhase: ClockPhase {
      currentPhase.isBreak ? .breakTime : .quarter
    }

    var period: Int { currentPhase.periodNumber }
    var isTimerRunning: Bool { countdown.isRunning }
    var currentDurationSeconds: Int { currentPhase.durationSeconds }
    var isPeriodComplete: Bool { elapsedSeconds >= currentDurationSeconds }
    var canScoreGoal: Bool {
      currentPhase.isQuarter
        && isTimerRunning
        && !isPeriodComplete
        && !isShowingLastCentrePassBanner
    }

    var canFinishGame: Bool {
      currentPhaseIndex == phases.count - 1
        && currentPhase.isQuarter
        && isPeriodComplete
        && !isTimerRunning
        && !isShowingLastCentrePassBanner
    }

    var canMoveToNextQuarter: Bool {
      currentPhase.isQuarter
        && !isPeriodComplete
        && !isShowingLastCentrePassBanner
        && !isTransitioningPeriod
    }

    var centrePassTeam: Team {
      centrePassTeamID == teamB.id ? teamB : teamA
    }

    var isShowingOriginalTeamOrder: Bool {
      !period.isMultiple(of: 2)
    }

    var lastCompletedQuarterNumber: Int {
      currentPhase.isBreak ? period : max(period - 1, 1)
    }

    var timeRemainingSeconds: Int {
      max(currentDurationSeconds - elapsedSeconds, 0)
    }
  }

  enum Action {
    case alert(PresentationAction<Alert>)
    case centrePassTeamButtonTapped(Team.ID)
    case centrePassTeamResponse(Result<Team.ID, any Error>)
    case closeButtonTapped
    case delegate(Delegate)
    case endQuarterButtonTapped
    case finishGameButtonTapped
    case finishGameResponse(Result<Game.ID, any Error>)
    case goalButtonTapped(Team.ID)
    case goalResponse(Result<ScoreSnapshot, any Error>)
    case lastCentrePassNotTakenButtonTapped
    case lastCentrePassResponse(Result<LastCentrePassSnapshot, any Error>)
    case lastCentrePassTakenButtonTapped
    case pauseTimerButtonTapped
    case sceneBecameActive
    case sceneBecameInactive
    case skipBreakButtonTapped
    case skipPhaseResponse(Result<GameSnapshot, any Error>)
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
      case .alert, .delegate:
        return .none

      case let .centrePassTeamButtonTapped(teamID):
        guard
          state.currentPhase.isQuarter,
          !state.isShowingLastCentrePassBanner,
          teamID == state.teamA.id || teamID == state.teamB.id,
          teamID != state.centrePassTeamID
        else { return .none }
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

      case .endQuarterButtonTapped:
        guard state.canMoveToNextQuarter else { return .none }
        return skipCurrentPhase(state: &state)

      case .finishGameButtonTapped:
        guard state.canFinishGame else { return .none }
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
        synchronizeTimer(state: &state, now: now)
        guard state.canScoreGoal else {
          if state.isPeriodComplete {
            return reconcileTimerEffect(gameID: state.gameID)
          }
          return .none
        }
        return insertGoalEffect(state: state, teamID: teamID)

      case let .goalResponse(.success(snapshot)):
        apply(snapshot, to: &state)
        state.goalFeedbackTrigger += 1
        let soundEffect: Effect<Action> = state.soundEffectsEnabled
          ? .run { _ in await soundEffects.playGoal() }
          : .none
        return .merge(
          soundEffect,
          refreshActivityEffect(gameID: state.gameID)
        )

      case .goalResponse(.failure):
        return reconcileTimerEffect(gameID: state.gameID)

      case .lastCentrePassNotTakenButtonTapped:
        return resolveLastCentrePass(state: &state, wasLastCentrePassTaken: false)

      case .lastCentrePassTakenButtonTapped:
        return resolveLastCentrePass(state: &state, wasLastCentrePassTaken: true)

      case let .lastCentrePassResponse(.success(snapshot)):
        state.centrePassTeamID = snapshot.centrePassTeamID
        state.isShowingLastCentrePassBanner = false
        state.isTransitioningPeriod = false
        return refreshActivityEffect(gameID: state.gameID)

      case .lastCentrePassResponse(.failure):
        state.isTransitioningPeriod = false
        return .none

      case .pauseTimerButtonTapped:
        guard state.isTimerRunning else { return .none }
        synchronizeTimer(state: &state, now: now)
        state.timerEndsAt = nil
        return .merge(
          .cancel(id: CancelID.timer),
          pauseTimerEffect(gameID: state.gameID, expectedPhaseIndex: state.currentPhaseIndex)
        )

      case let .timerPauseResponse(.success(snapshot)):
        applyTimer(snapshot.game, to: &state)
        return .none

      case .timerPauseResponse(.failure):
        return reconcileTimerEffect(gameID: state.gameID)

      case .sceneBecameActive:
        return reconcileTimerEffect(gameID: state.gameID)

      case .sceneBecameInactive:
        return .cancel(id: CancelID.timer)

      case .skipBreakButtonTapped:
        guard state.currentPhase.isBreak, !state.isTransitioningPeriod else { return .none }
        return skipCurrentPhase(state: &state)

      case let .skipPhaseResponse(.success(snapshot)):
        applyTimer(snapshot.game, to: &state)
        state.isTransitioningPeriod = false
        guard state.isTimerRunning else { return .cancel(id: CancelID.timer) }
        return timerEffect()

      case .skipPhaseResponse(.failure):
        state.isTransitioningPeriod = false
        return reconcileTimerEffect(gameID: state.gameID)

      case .startTimerButtonTapped:
        guard
          !state.isTimerRunning,
          !state.isPeriodComplete,
          state.currentPhase.isBreak || !state.isShowingLastCentrePassBanner
        else { return .none }
        let requestsAuthorization = state.currentPhaseIndex == 0 && state.elapsedSeconds == 0
        state.timerEndsAt = GameTimerClient.endDate(
          durationSeconds: state.currentDurationSeconds,
          elapsedSeconds: state.elapsedSeconds,
          now: now
        )
        return .merge(
          startTimerEffect(
            gameID: state.gameID,
            expectedPhaseIndex: state.currentPhaseIndex,
            requestsAuthorization: requestsAuthorization
          ),
          timerEffect()
        )

      case .timerTick:
        guard state.isTimerRunning else { return .none }
        synchronizeTimer(state: &state, now: now)
        guard state.isPeriodComplete else { return .none }
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
        return reconcileTimerEffect(gameID: state.gameID)

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
  }

  private func apply(_ snapshot: ScoreSnapshot, to state: inout State) {
    state.canUndo = snapshot.canUndo
    state.centrePassTeamID = snapshot.centrePassTeamID
    state.teamAScore = snapshot.teamAScore
    state.teamBScore = snapshot.teamBScore
  }

  private func applyTimer(_ game: Game, to state: inout State) {
    state.currentPhaseIndex = game.currentPhaseIndex
    state.elapsedSeconds = game.elapsedSeconds
    state.isShowingLastCentrePassBanner = game.isAwaitingCentrePassConfirmation
    state.timerEndsAt = game.timerEndsAt
  }

  private func skipCurrentPhase(state: inout State) -> Effect<Action> {
    synchronizeTimer(state: &state, now: now)
    let gameID = state.gameID
    let phaseIndex = state.currentPhaseIndex
    state.timerEndsAt = nil
    state.isTransitioningPeriod = true
    return .merge(
      .cancel(id: CancelID.timer),
      .run { send in
        await send(
          .skipPhaseResponse(
            await Result {
              try await gameTimer.skip(gameID, phaseIndex)
            }
          )
        )
      }
    )
  }

  private func resolveLastCentrePass(
    state: inout State,
    wasLastCentrePassTaken: Bool
  ) -> Effect<Action> {
    guard state.isShowingLastCentrePassBanner, !state.isTransitioningPeriod else {
      return .none
    }
    state.isTransitioningPeriod = true
    return resolveLastCentrePassEffect(
      state: state,
      wasLastCentrePassTaken: wasLastCentrePassTaken
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
    let gameID = state.gameID
    let snapshot = LastCentrePassSnapshot(centrePassTeamID: centrePassTeamID)

    return .run { send in
      let result = await Result {
        try await database.write { db in
          guard try Game.find(gameID).fetchOne(db) != nil else {
            throw ScoringPersistenceError.gameNotFound
          }
          try Game.find(gameID).update {
            $0.centrePassTeamID = #bind(snapshot.centrePassTeamID)
            $0.isAwaitingCentrePassConfirmation = false
          }
          .execute(db)
        }
        return snapshot
      }
      await send(.lastCentrePassResponse(result))
    }
  }

  private func finishGameEffect(state: State) -> Effect<Action> {
    let endedAt = now
    let gameID = state.gameID
    let currentPhaseIndex = state.currentPhaseIndex
    let elapsedSeconds = state.elapsedSeconds

    return .run { send in
      let result = await Result {
        try await database.write { db in
          guard try Game.find(gameID).fetchOne(db) != nil else {
            throw ScoringPersistenceError.gameNotFound
          }
          try Game.find(gameID).update {
            $0.currentPhaseIndex = currentPhaseIndex
            $0.elapsedSeconds = elapsedSeconds
            $0.endedAt = #bind(endedAt)
            $0.isAwaitingCentrePassConfirmation = false
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
    let expectedPhaseIndex = state.currentPhaseIndex
    let gameID = state.gameID
    let goalID = uuid()
    let teamAID = state.teamA.id
    let teamBID = state.teamB.id

    return .run { send in
      let result = await Result {
        try await database.write { db in
          let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
          let game = snapshot.game
          guard
            game.currentPhaseIndex == expectedPhaseIndex,
            case let .period(_, durationSeconds) = snapshot.currentPhase,
            let gamePeriodID = snapshot.currentPeriod?.id,
            let timerEndsAt = game.timerEndsAt,
            timerEndsAt > createdAt
          else {
            throw ScoringPersistenceError.goalUnavailable
          }
          let elapsedSeconds = GameTimerClient.elapsedSeconds(
            durationSeconds: durationSeconds,
            persistedElapsedSeconds: game.elapsedSeconds,
            timerEndsAt: timerEndsAt,
            now: createdAt
          )
          guard elapsedSeconds < durationSeconds else {
            throw ScoringPersistenceError.goalUnavailable
          }

          let centrePassTeamID = resolvedCentrePassTeamID(
            game.centrePassTeamID,
            teamAID: teamAID,
            teamBID: teamBID
          )
          try Goal.insert {
            Goal(
              id: goalID,
              gameID: gameID,
              gamePeriodID: gamePeriodID,
              centrePassTeamID: centrePassTeamID,
              teamID: teamID,
              elapsedSeconds: elapsedSeconds,
              points: 1,
              createdAt: createdAt
            )
          }
          .execute(db)

          try Game.find(gameID).update {
            $0.centrePassTeamID = #bind(
              opposingTeamID(
                centrePassTeamID,
                teamAID: teamAID,
                teamBID: teamBID
              )
            )
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

  private func pauseTimerEffect(
    gameID: Game.ID,
    expectedPhaseIndex: Int
  ) -> Effect<Action> {
    .run { send in
      await send(
        .timerPauseResponse(
          await Result {
            try await gameTimer.pause(gameID, expectedPhaseIndex)
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
    .run { _ in await gameTimer.refreshActivity(gameID) }
  }

  private func startTimerEffect(
    gameID: Game.ID,
    expectedPhaseIndex: Int,
    requestsAuthorization: Bool
  ) -> Effect<Action> {
    .run { send in
      await send(
        .timerStartResponse(
          await Result {
            try await gameTimer.startOrResume(
              gameID,
              expectedPhaseIndex,
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
            .where { $0.gameID.eq(gameID) }
            .order { ($0.createdAt.desc(), $0.id.desc()) }
            .fetchOne(db)

          if let latestGoal {
            try Goal.find(latestGoal.id).delete().execute(db)
            guard let game = try Game.find(gameID).fetchOne(db) else {
              throw ScoringPersistenceError.gameNotFound
            }
            let centrePassTeamID = resolvedCentrePassTeamID(
              game.centrePassTeamID,
              teamAID: teamAID,
              teamBID: teamBID
            )
            try Game.find(gameID).update {
              $0.centrePassTeamID = #bind(
                opposingTeamID(
                  centrePassTeamID,
                  teamAID: teamAID,
                  teamBID: teamBID
                )
              )
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

  private func synchronizeTimer(state: inout State, now: Date) {
    state.elapsedSeconds = GameTimerClient.elapsedSeconds(
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
  case goalUnavailable
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
