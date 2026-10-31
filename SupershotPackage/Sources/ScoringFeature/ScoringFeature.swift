import AlarmClient
import ApplicationDependency
import AppSettings
import AppUI
import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import Sharing
import SoundEffectsClient
import SubscriptionClient
import SwiftUI
import UI

@Reducer
package struct ScoringFeature {
  package nonisolated enum ControlsPresentation: Equatable, Sendable {
    case shown
    case dismissingForTimeInput
    case hiddenForTimeInput
    case dismissingForPaywall
    case hiddenForPaywall
  }

  /// One mutually exclusive operation owns progression at a time.
  package nonisolated enum Operation: Equatable, Sendable {
    case starting(phaseIndex: Int)
    case pausing(phaseIndex: Int)
    case skipping(phaseIndex: Int)
    case confirmingCentrePass(period: Int)
    case finishing
  }

  package nonisolated struct Team: Equatable, Identifiable, Sendable {
    package let id: UUID
    package var bibColor = ColorPalette.blue
    package var name: String

    package nonisolated init(id: UUID, bibColor: Color = ColorPalette.blue, name: String) {
      self.id = id
      self.bibColor = bibColor
      self.name = name
    }
  }

  package struct CourtTeam: Equatable, Identifiable, Sendable {
    package var team: Team
    package var score: Int
    package var hasCentrePass: Bool

    package var id: Team.ID {
      team.id
    }

    package init(team: Team, score: Int, hasCentrePass: Bool) {
      self.team = team
      self.score = score
      self.hasCentrePass = hasCentrePass
    }
  }

  package struct CourtLayout: Equatable, Sendable {
    package var left: CourtTeam
    package var right: CourtTeam

    package init(left: CourtTeam, right: CourtTeam) {
      self.left = left
      self.right = right
    }
  }

  @ObservableState
  package struct State: Equatable {
    @Presents package var timeInput: TimeInputFeature.State?
    package var editedPhaseIndex: Int?
    package var operation: Operation?
    @Presents package var alert: AlertState<Alert>?
    package var alarms = AlarmPermissionFeature.State()
    package var controlsPresentation = ControlsPresentation.shown
    @Shared(.hapticsEnabled) package var hapticsEnabled
    @Shared(.soundEffectsEnabled) package var soundEffectsEnabled
    package var canUndo = false
    package var canUndoDuringConfirmation = false
    package var centrePassTeamID: Team.ID
    package var currentPhaseIndex = 0
    package var elapsedSeconds = 0
    package var swapSides = false
    package let gameID: Game.ID
    package var goalFeedbackTrigger = 0
    package var hasShownAlarmSchedulingFailureAlert = false
    package var isSavingCourtOrientation = false
    package var isShowingLastCentrePassBanner = false
    package var lateScoringPeriodNumber: Int?
    package var scheduledAt: Date?
    package var court: String?
    package var startedAt: Date?
    package var teamA: Team
    package var teamAScore = 0
    package var teamB: Team
    package var teamBScore = 0
    package var timerEndsAt: Date?
    private var validatedTimeline: GameTimeline

    package var periods: [GamePeriod] {
      get { validatedTimeline.periods }
      set {
        guard let timeline = GameTimeline(periods: newValue),
              timeline.phase(at: currentPhaseIndex) != nil
        else {
          preconditionFailure("Scoring requires a valid timeline and phase")
        }
        validatedTimeline = timeline
      }
    }

    package var timeline: GameTimeline {
      validatedTimeline
    }

    package var currentPhase: GamePhase {
      guard let phase = timeline.phase(at: currentPhaseIndex) else {
        preconditionFailure("Scoring phase must belong to its timeline")
      }
      return phase
    }

    package var activePlayingPeriod: GamePeriod? {
      timeline.activePlayingPeriod(at: currentPhaseIndex)
    }

    package var precedingPeriod: GamePeriod? {
      timeline.precedingPeriod(at: currentPhaseIndex)
    }

    package var scoringPeriod: GamePeriod? {
      scoringContext.flatMap { timeline.scoringPeriod(for: $0) }
    }

    package var countdown: GameCountdown {
      get { GameCountdown(elapsedSeconds: elapsedSeconds, endsAt: timerEndsAt) }
      set {
        elapsedSeconds = newValue.elapsedSeconds
        timerEndsAt = newValue.endsAt
      }
    }

    package var period: Int {
      currentPhase.associatedPeriod.number
    }

    package var isTimerRunning: Bool {
      countdown.isRunning
    }

    package var currentDurationSeconds: Int {
      currentPhase.durationSeconds
    }

    package var timerProjection: GameCountdown.Projection {
      countdown.projection(durationSeconds: currentDurationSeconds)
    }

    package var isPeriodComplete: Bool {
      timerProjection.status == .complete
    }

    package var scoringContext: GameScoringContext? {
      GameScoringContext.resolve(
        phase: currentPhase, countdown: countdown,
        isAwaitingCentrePassConfirmation: isShowingLastCentrePassBanner,
        lateScoringPeriodNumber: lateScoringPeriodNumber
      )
    }

    package var controlsAreAvailable: Bool {
      controlsPresentation == .shown && timeInput == nil && alert == nil
    }

    package var canOperate: Bool {
      controlsAreAvailable && operation == nil
    }

    package var canEditTime: Bool {
      !isTimerRunning && !isPeriodComplete && operation == nil
        && !isShowingLastCentrePassBanner
    }

    package var canStartOrResume: Bool {
      canOperate && !isTimerRunning && !isPeriodComplete
        && (currentPhase.isBreak || !isShowingLastCentrePassBanner)
    }

    package var canPause: Bool {
      canOperate && isTimerRunning
    }

    package var canSkipBreak: Bool {
      canOperate && currentPhase.isBreak
    }

    package var canScoreGoal: Bool {
      startedAt != nil && scoringContext != nil && canOperate
    }

    package var canUndoGoal: Bool {
      canOperate && canUndo && (!isShowingLastCentrePassBanner || canUndoDuringConfirmation)
    }

    package var canFinishGame: Bool {
      startedAt != nil && canOperate
        && GameProgress(
          phaseIndex: currentPhaseIndex, countdown: countdown,
          isAwaitingCentrePassConfirmation: isShowingLastCentrePassBanner
        ).isFinalPeriodComplete(in: timeline) && !isShowingLastCentrePassBanner
    }

    package var canMoveToNextQuarter: Bool {
      startedAt != nil && canOperate && currentPhase.isPlayingPeriod
        && !isPeriodComplete && !isShowingLastCentrePassBanner
    }

    package var centrePassTeam: Team {
      centrePassTeamID == teamB.id ? teamB : teamA
    }

    package var courtLayout: CourtLayout {
      let a = CourtTeam(
        team: teamA,
        score: teamAScore,
        hasCentrePass: centrePassTeamID == teamA.id
      )
      let b = CourtTeam(
        team: teamB,
        score: teamBScore,
        hasCentrePass: centrePassTeamID == teamB.id
      )
      return period.isMultiple(of: 2) == swapSides
        ? CourtLayout(left: a, right: b)
        : CourtLayout(left: b, right: a)
    }

    package var lastCompletedQuarterNumber: Int {
      precedingPeriod?.number ?? period
    }

    package var timeRemainingSeconds: Int {
      timerProjection.remainingSeconds
    }

    package init(
      timeInput: TimeInputFeature.State? = nil, editedPhaseIndex: Int? = nil,
      operation: Operation? = nil, alert: AlertState<Alert>? = nil,
      alarms: AlarmPermissionFeature.State = AlarmPermissionFeature.State(),
      controlsPresentation: ControlsPresentation = ControlsPresentation.shown,
      canUndo: Bool = false, canUndoDuringConfirmation: Bool = false, centrePassTeamID: Team.ID,
      currentPhaseIndex: Int = 0, elapsedSeconds: Int = 0, swapSides: Bool = false, gameID: Game.ID,
      goalFeedbackTrigger: Int = 0, hasShownAlarmSchedulingFailureAlert: Bool = false,
      isSavingCourtOrientation: Bool = false, isShowingLastCentrePassBanner: Bool = false,
      lateScoringPeriodNumber: Int? = nil,
      periods: [GamePeriod], startedAt: Date?, teamA: Team, teamAScore: Int = 0, teamB: Team,
      teamBScore: Int = 0, timerEndsAt: Date? = nil
    ) {
      self.timeInput = timeInput
      self.editedPhaseIndex = editedPhaseIndex
      self.operation = operation
      self.alert = alert
      self.alarms = alarms
      self.controlsPresentation = controlsPresentation
      self.canUndo = canUndo
      self.canUndoDuringConfirmation = canUndoDuringConfirmation
      self.centrePassTeamID = centrePassTeamID
      self.currentPhaseIndex = currentPhaseIndex
      self.elapsedSeconds = elapsedSeconds
      self.swapSides = swapSides
      self.gameID = gameID
      self.goalFeedbackTrigger = goalFeedbackTrigger
      self.hasShownAlarmSchedulingFailureAlert = hasShownAlarmSchedulingFailureAlert
      self.isSavingCourtOrientation = isSavingCourtOrientation
      self.isShowingLastCentrePassBanner = isShowingLastCentrePassBanner
      self.lateScoringPeriodNumber = lateScoringPeriodNumber
      guard let timeline = GameTimeline(periods: periods),
            timeline.phase(at: currentPhaseIndex) != nil
      else {
        preconditionFailure("Scoring requires a valid timeline and phase")
      }
      validatedTimeline = timeline
      self.startedAt = startedAt
      self.teamA = teamA
      self.teamAScore = teamAScore
      self.teamB = teamB
      self.teamBScore = teamBScore
      self.timerEndsAt = timerEndsAt
    }
  }

  package enum Action: BindableAction {
    case controlTapped(ScoringControlAction)
    case alarms(AlarmPermissionFeature.Action)
    case alarmScheduleResponse(Bool)
    case alert(PresentationAction<Alert>)
    case editTimeButtonTapped
    case timeInput(PresentationAction<TimeInputFeature.Action>)
    case timeInputSheetDidDismiss
    case timeCorrectionResponse(Result<GameSnapshot, any Error>)
    case controlsSheetDidDismiss
    case proPaywallDidDismiss
    case centrePassTeamButtonTapped(Team.ID)
    case centrePassTeamResponse(Result<Team.ID, any Error>)
    case delegate(Delegate)
    case endQuarterButtonTapped
    case finishGameButtonTapped
    case finishGameResponse(Result<Game.ID, any Error>)
    case goalButtonTapped(Team.ID)
    case goalResponse(Result<GameScoreSnapshot, any Error>)
    case keepScreenAwakeTask
    case lastCentrePassNotTakenButtonTapped
    case lastCentrePassResponse(Result<LastCentrePassSnapshot, any Error>)
    case lastCentrePassTakenButtonTapped
    case pauseTimerButtonTapped
    case sceneBecameActive
    case sceneBecameInactive
    case skipBreakButtonTapped
    case skipPhaseResponse(Result<GameSnapshot, any Error>)
    case startTimerButtonTapped
    case swapCentrePass
    case swapSidesButtonTapped
    case swapSidesResponse(Result<Bool, any Error>)
    case timerTick
    case timerPauseResponse(Result<GameSnapshot, any Error>)
    case timerReconcileResponse(Result<GameSnapshot, any Error>)
    case timerStartResponse(Result<GameTimerUpdate, any Error>)
    case undoButtonTapped
    case undoResponse(Result<GameScoreSnapshot, any Error>)

    case binding(BindingAction<State>)

    package enum Delegate {
      case gameFinished(Game.ID)
      case proPromotionTapped
    }
  }

  package enum Alert: Equatable {
    case dismissButtonTapped
  }

  private nonisolated enum CancelID: Hashable, Sendable {
    case timer
    case timerOperation
    case reconcile
  }

  #if os(iOS)
    @Dependency(\.application) package var application
  #endif
  @Dependency(\.continuousClock) package var clock
  @Dependency(\.date.now) package var now
  @Dependency(\.gameSession) package var gameSession
  @Dependency(\.gameTimer) package var gameTimer
  @Dependency(\.gameScoring) package var gameScoring
  @Dependency(\.soundEffects) package var soundEffects
  @Dependency(\.uuid) package var uuid

  package var body: some Reducer<State, Action> {
    Scope(state: \.alarms, action: \.alarms) { AlarmPermissionFeature() }
    BindingReducer()
    Reduce { state, action in
      switch action {
      case let .controlTapped(action):
        switch action {
        case .startOrResume: return .send(.startTimerButtonTapped)
        case .pause: return .send(.pauseTimerButtonTapped)
        case .skipBreak: return .send(.skipBreakButtonTapped)
        case .finishGame: return .send(.finishGameButtonTapped)
        case .editTime: return .send(.editTimeButtonTapped)
        case let .goal(teamID): return .send(.goalButtonTapped(teamID))
        case .confirmCentrePass(true): return .send(.lastCentrePassTakenButtonTapped)
        case .confirmCentrePass(false): return .send(.lastCentrePassNotTakenButtonTapped)
        }

      case .alarms(.delegate(.proPromotionTapped)):
        guard state.controlsPresentation == .shown else { return .none }
        #if os(macOS)
          state.controlsPresentation = .hiddenForPaywall
          return .send(.delegate(.proPromotionTapped))
        #else
          state.controlsPresentation = .dismissingForPaywall
          return .none
        #endif

      case .editTimeButtonTapped:
        guard state.canEditTime, state.controlsAreAvailable else { return .none }
        state.editedPhaseIndex = state.currentPhaseIndex
        #if os(macOS)
          state.controlsPresentation = .hiddenForTimeInput
          state.timeInput = .init(
            title: "Edit remaining time", totalSeconds: state.timeRemainingSeconds,
            allowedSeconds: 1 ... state.currentDurationSeconds, selectedUnit: .seconds
          )
        #else
          state.controlsPresentation = .dismissingForTimeInput
        #endif
        return .none

      case let .timeInput(.presented(.delegate(.committed(seconds)))):
        guard state.timeInput?.isSaving == false,
              let phaseIndex = state.editedPhaseIndex, state.canEditTime,
              phaseIndex == state.currentPhaseIndex,
              (1 ... state.currentDurationSeconds).contains(seconds)
        else {
          state.timeInput?.errorMessage = "The clock has changed. Close the editor and try again."
          return .none
        }
        state.timeInput?.isSaving = true
        let gameID = state.gameID
        return .run { send in
          await send(
            .timeCorrectionResponse(
              Result {
                try await gameTimer.setRemainingTime(gameID, phaseIndex, seconds)
              }
            )
          )
        }

      case .timeInput(.presented(.delegate(.cancelled))):
        state.timeInput = nil
        return .none

      case .timeInput:
        return .none

      case .timeInputSheetDidDismiss:
        guard state.controlsPresentation == .hiddenForTimeInput else { return .none }
        state.editedPhaseIndex = nil
        state.controlsPresentation = .shown
        return .none

      case let .timeCorrectionResponse(.success(snapshot)):
        applyTimer(snapshot.game, to: &state)
        state.timeInput = nil
        return .none

      case let .timeCorrectionResponse(.failure(error)):
        state.timeInput?.isSaving = false
        state.timeInput?.errorMessage = error.localizedDescription
        return .none

      case .controlsSheetDidDismiss:
        if state.controlsPresentation == .dismissingForTimeInput {
          state.controlsPresentation = .hiddenForTimeInput
          guard state.canEditTime, state.editedPhaseIndex == state.currentPhaseIndex else {
            state.editedPhaseIndex = nil
            state.controlsPresentation = .shown
            return .none
          }
          state.timeInput = .init(
            title: "Edit remaining time", totalSeconds: state.timeRemainingSeconds,
            allowedSeconds: 1 ... state.currentDurationSeconds, selectedUnit: .seconds
          )
          return .none
        }
        guard state.controlsPresentation == .dismissingForPaywall else { return .none }
        state.controlsPresentation = .hiddenForPaywall
        return .send(.delegate(.proPromotionTapped))

      case .proPaywallDidDismiss:
        guard state.timeInput == nil, state.controlsPresentation != .dismissingForTimeInput,
              state.controlsPresentation != .hiddenForTimeInput
        else { return .none }
        state.controlsPresentation = .shown
        return .none

      case .alarms(.delegate(.authorized)):
        let gameID = state.gameID
        return .run { send in
          await send(.alarmScheduleResponse(gameTimer.scheduleAlarm(gameID)))
        }

      case let .alarmScheduleResponse(failed):
        if failed, !state.hasShownAlarmSchedulingFailureAlert {
          state.alert = .alarmSchedulingFailed
          state.hasShownAlarmSchedulingFailureAlert = true
        }
        return .none

      case .alarms, .alert, .delegate:
        return .none

      case .swapSidesButtonTapped:
        guard state.canOperate, !state.isSavingCourtOrientation else { return .none }
        state.isSavingCourtOrientation = true
        let gameID = state.gameID
        return .run { send in
          let result = await Result {
            try await gameSession.execute(gameID, .swapSides, now).acceptedSnapshot().game.swapSides
          }
          await send(.swapSidesResponse(result))
        }

      case let .swapSidesResponse(.success(swapSides)):
        state.isSavingCourtOrientation = false
        state.swapSides = swapSides
        return .none

      case .swapSidesResponse(.failure):
        state.isSavingCourtOrientation = false
        state.alert = AlertState {
          TextState("Couldn’t swap sides")
        } actions: {
          ButtonState(role: .cancel, action: .dismissButtonTapped) {
            TextState("OK")
          }
        } message: {
          TextState("Please try again.")
        }
        return .none

      case .swapCentrePass:
        guard state.canOperate else { return .none }
        state.centrePassTeamID =
          state.teamA.id == state.centrePassTeamID ? state.teamB.id : state.teamA.id
        return updateCentrePassEffect(gameID: state.gameID, teamID: state.centrePassTeamID)

      case let .centrePassTeamButtonTapped(teamID):
        guard
          state.canOperate, state.currentPhase.isPlayingPeriod,
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

      case .endQuarterButtonTapped:
        guard state.canMoveToNextQuarter else { return .none }
        return skipCurrentPhase(state: &state)

      case .finishGameButtonTapped:
        guard state.canFinishGame else { return .none }
        state.operation = .finishing
        return .merge(
          .cancel(id: CancelID.timer),
          .cancel(id: CancelID.reconcile),
          finishGameEffect(state: state)
        )

      case let .finishGameResponse(.success(gameID)):
        guard state.operation == .finishing else { return .none }
        state.operation = nil
        return .send(.delegate(.gameFinished(gameID)))

      case .finishGameResponse(.failure):
        guard state.operation == .finishing else { return .none }
        state.operation = nil
        state.alert = .operationFailed("Couldn’t end game")
        return reconcileTimerEffect(gameID: state.gameID)

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
        let soundEffect: Effect<Action> =
          state.soundEffectsEnabled
            ? .run { _ in await soundEffects.playGoal() }
            : .none
        return .merge(
          soundEffect,
          refreshActivityEffect(gameID: state.gameID)
        )

      case .goalResponse(.failure):
        return reconcileTimerEffect(gameID: state.gameID)

      case .keepScreenAwakeTask:
        #if os(iOS)
          return .run { @MainActor _ in
            application.isIdleTimerDisabled = true
            defer { application.isIdleTimerDisabled = false }
            try await Task.never()
          }
        #else
          return .none
        #endif

      case .lastCentrePassNotTakenButtonTapped:
        return resolveLastCentrePass(state: &state, wasLastCentrePassTaken: false)

      case .lastCentrePassTakenButtonTapped:
        return resolveLastCentrePass(state: &state, wasLastCentrePassTaken: true)

      case let .lastCentrePassResponse(.success(snapshot)):
        guard case .confirmingCentrePass = state.operation else { return .none }
        state.centrePassTeamID = snapshot.centrePassTeamID
        state.isShowingLastCentrePassBanner = false
        state.operation = nil
        return reconcileTimerEffect(gameID: state.gameID)

      case .lastCentrePassResponse(.failure):
        guard case .confirmingCentrePass = state.operation else { return .none }
        state.operation = nil
        state.alert = .operationFailed("Couldn’t save centre pass")
        return .none

      case .pauseTimerButtonTapped:
        guard state.canPause else {
          return .none
        }
        synchronizeTimer(state: &state, now: now)
        state.timerEndsAt = nil
        state.operation = .pausing(phaseIndex: state.currentPhaseIndex)
        return .merge(
          .cancel(id: CancelID.timer),
          .cancel(id: CancelID.reconcile),
          pauseTimerEffect(gameID: state.gameID, expectedPhaseIndex: state.currentPhaseIndex)
        )

      case let .timerPauseResponse(.success(snapshot)):
        guard state.operation == .pausing(phaseIndex: state.currentPhaseIndex) else { return .none }
        state.operation = nil
        applyTimer(snapshot.game, to: &state)
        return state.isTimerRunning ? timerEffect() : .cancel(id: CancelID.timer)

      case .timerPauseResponse(.failure):
        guard case .pausing = state.operation else { return .none }
        state.operation = nil
        state.alert = .operationFailed("Couldn’t pause clock")
        return reconcileTimerEffect(gameID: state.gameID)

      case .sceneBecameActive:
        guard state.operation == nil else { return .none }
        return reconcileTimerEffect(gameID: state.gameID)

      case .sceneBecameInactive:
        return .cancel(id: CancelID.timer)

      case .skipBreakButtonTapped:
        guard state.canSkipBreak else { return .none }
        return skipCurrentPhase(state: &state)

      case let .skipPhaseResponse(.success(snapshot)):
        guard state.operation == .skipping(phaseIndex: state.currentPhaseIndex) else { return .none }
        applyTimer(snapshot.game, to: &state)
        state.operation = nil
        guard state.isTimerRunning else { return .cancel(id: CancelID.timer) }
        return timerEffect()

      case .skipPhaseResponse(.failure):
        guard case .skipping = state.operation else { return .none }
        state.operation = nil
        state.alert = .operationFailed("Couldn’t advance game")
        return reconcileTimerEffect(gameID: state.gameID)

      case .startTimerButtonTapped:
        guard state.canStartOrResume else { return .none }
        state.operation = .starting(phaseIndex: state.currentPhaseIndex)
        return .merge(
          .cancel(id: CancelID.reconcile),
          startTimerEffect(gameID: state.gameID, expectedPhaseIndex: state.currentPhaseIndex)
        )

      case .timerTick:
        guard state.isTimerRunning else { return .none }
        synchronizeTimer(state: &state, now: now)
        guard state.isPeriodComplete, state.operation == nil else { return .none }
        state.timerEndsAt = nil
        return .merge(
          .cancel(id: CancelID.timer),
          reconcileTimerEffect(gameID: state.gameID)
        )

      case let .timerReconcileResponse(.success(snapshot)):
        guard state.operation == nil else { return .none }
        state.teamAScore = snapshot.teamAScore
        state.teamBScore = snapshot.teamBScore
        state.canUndo = !snapshot.goals.isEmpty
        state.canUndoDuringConfirmation = snapshot.canUndoDuringConfirmation
        state.centrePassTeamID = snapshot.game.centrePassTeamID ?? snapshot.teamA.id
        applyTimer(snapshot.game, to: &state)
        guard state.isTimerRunning else { return .cancel(id: CancelID.timer) }
        return timerEffect()

      case .timerReconcileResponse(.failure):
        return .none

      case let .timerStartResponse(.success(update)):
        guard state.operation == .starting(phaseIndex: state.currentPhaseIndex) else { return .none }
        state.operation = nil
        applyTimer(update.snapshot.game, to: &state)
        if update.alarmSchedulingFailed, !state.hasShownAlarmSchedulingFailureAlert {
          state.alert = .alarmSchedulingFailed
          state.hasShownAlarmSchedulingFailureAlert = true
        }
        return state.isTimerRunning ? timerEffect() : .cancel(id: CancelID.timer)

      case .timerStartResponse(.failure):
        guard case .starting = state.operation else { return .none }
        state.operation = nil
        state.alert = .operationFailed("Couldn’t start clock")
        return reconcileTimerEffect(gameID: state.gameID)

      case .undoButtonTapped:
        guard state.canUndoGoal else { return .none }
        return undoGoalEffect(state: state)

      case let .undoResponse(.success(snapshot)):
        apply(snapshot, to: &state)
        return refreshActivityEffect(gameID: state.gameID)

      case .undoResponse(.failure):
        return .none

      case .binding:
        return .none
      }
    }
    .ifLet(\.$timeInput, action: \.timeInput) { TimeInputFeature() }
    .ifLet(\.$alert, action: \.alert)
  }

  private func apply(_ snapshot: GameScoreSnapshot, to state: inout State) {
    state.canUndo = snapshot.canUndo
    state.canUndoDuringConfirmation = snapshot.canUndoDuringConfirmation
    state.centrePassTeamID = snapshot.centrePassTeamID
    state.teamAScore = snapshot.teamAScore
    state.teamBScore = snapshot.teamBScore
  }

  private func applyTimer(_ game: Game, to state: inout State) {
    state.startedAt = game.startedAt
    state.swapSides = game.swapSides
    state.lateScoringPeriodNumber = game.lateScoringPeriodNumber
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
    state.operation = .skipping(phaseIndex: phaseIndex)
    return .merge(
      .cancel(id: CancelID.timer),
      .cancel(id: CancelID.reconcile),
      .run { send in
        await send(
          .skipPhaseResponse(
            Result {
              try await gameTimer.skip(gameID, phaseIndex)
            }
          )
        )
      }
      .cancellable(id: CancelID.timerOperation, cancelInFlight: true)
    )
  }

  private func resolveLastCentrePass(
    state: inout State,
    wasLastCentrePassTaken: Bool
  ) -> Effect<Action> {
    guard state.isShowingLastCentrePassBanner, state.canOperate else {
      return .none
    }
    state.operation = .confirmingCentrePass(period: state.lastCompletedQuarterNumber)
    return .merge(
      .cancel(id: CancelID.reconcile),
      resolveLastCentrePassEffect(state: state, wasLastCentrePassTaken: wasLastCentrePassTaken)
    )
  }

  private func resolveLastCentrePassEffect(
    state: State,
    wasLastCentrePassTaken: Bool
  ) -> Effect<Action> {
    let gameID = state.gameID
    let completedPeriod = state.lastCompletedQuarterNumber
    return .run { send in
      await send(
        .lastCentrePassResponse(
          Result {
            try await gameScoring.resolveCentrePass(gameID, completedPeriod, wasLastCentrePassTaken)
          }
        )
      )
    }
  }

  private func finishGameEffect(state: State) -> Effect<Action> {
    let endedAt = now
    let gameID = state.gameID

    return .run { send in
      let result = await Result {
        _ = try await gameSession.execute(gameID, .finish, endedAt).acceptedSnapshot()
        await gameTimer.endPresentation(gameID)
        return gameID
      }
      await send(.finishGameResponse(result))
    }
  }

  private func insertGoalEffect(state: State, teamID: Team.ID, points: Int = 1) -> Effect<Action> {
    let createdAt = now
    let expectedPhaseIndex = state.currentPhaseIndex
    let gameID = state.gameID
    let goalID = uuid()
    let scoringContext = state.scoringContext
    return .run { send in
      let result = await Result {
        try await gameScoring.recordGoal(
          RecordGoalCommand(
            gameID: gameID, teamID: teamID, expectedPhaseIndex: expectedPhaseIndex,
            goalID: goalID, createdAt: createdAt, points: points, scoringContext: scoringContext
          )
        )
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
          Result {
            try await gameTimer.pause(gameID, expectedPhaseIndex)
          }
        )
      )
    }
    .cancellable(id: CancelID.timerOperation, cancelInFlight: true)
  }

  private func reconcileTimerEffect(gameID: Game.ID) -> Effect<Action> {
    .run { send in
      await send(
        .timerReconcileResponse(
          Result {
            try await gameTimer.reconcile(gameID)
          }
        )
      )
    }
    .cancellable(id: CancelID.reconcile, cancelInFlight: true)
  }

  private func refreshActivityEffect(gameID: Game.ID) -> Effect<Action> {
    .run { _ in await gameTimer.refreshActivity(gameID) }
  }

  private func startTimerEffect(
    gameID: Game.ID,
    expectedPhaseIndex: Int
  ) -> Effect<Action> {
    .run { send in
      await send(
        .timerStartResponse(
          Result {
            try await gameTimer.startOrResume(
              gameID,
              expectedPhaseIndex
            )
          }
        )
      )
    }
    .cancellable(id: CancelID.timerOperation, cancelInFlight: true)
  }

  private func undoGoalEffect(state: State) -> Effect<Action> {
    let gameID = state.gameID
    return .run { send in
      await send(.undoResponse(Result { try await gameScoring.undo(gameID) }))
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
      await send(
        .centrePassTeamResponse(
          Result { try await gameScoring.selectCentrePass(gameID, teamID) }
        )
      )
    }
  }

  package init() {}
}

package extension AlertState where Action == ScoringFeature.Alert {
  static func operationFailed(_ title: String) -> Self {
    Self { TextState(title) } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) { TextState("OK") }
    } message: { TextState("Please try again.") }
  }

  static var alarmSchedulingFailed: Self {
    Self {
      TextState("Quarter alerts unavailable")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      #if os(macOS)
        TextState(
          "The game timer will keep running, but Supershot couldn’t schedule its notifications. Try pausing and resuming the timer."
        )
      #else
        TextState(
          "The game timer will keep running, but Supershot couldn’t schedule its alarms. Try pausing and resuming the timer."
        )
      #endif
    }
  }
}
