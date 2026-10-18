import AlarmClient
import AppSettings
import ApplicationDependency
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
import Styleguide
import SubscriptionClient
import SwiftUI
import WidgetSupport

@Reducer
package struct ScoringFeature {
  nonisolated package enum ControlsPresentation: Equatable, Sendable {
    case shown
    case dismissingForTimeInput
    case hiddenForTimeInput
    case dismissingForPaywall
    case hiddenForPaywall
  }

  nonisolated package enum ClockPhase: Equatable, Sendable {
    case breakTime
    case quarter
  }

  nonisolated package struct Team: Equatable, Identifiable, Sendable {
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

    package var id: Team.ID { team.id }

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
    package var isTimerOperationPending = false
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
    package var isTransitioningPeriod = false
    package var lateScoringPeriodNumber: Int?
    package var periods: [GamePeriod]
    package let startedAt: Date
    package var teamA: Team
    package var teamAScore = 0
    package var teamB: Team
    package var teamBScore = 0
    package var timerEndsAt: Date?
    package var presentationDetent: PresentationDetent = .height(112)
    package var detents: Set<PresentationDetent> = [.height(112), .height(200)]

    package var timeline: GameTimeline { GameTimeline(periods: periods)! }
    package var currentPhase: GamePhase { timeline.phase(at: currentPhaseIndex)! }
    package var activePlayingPeriod: GamePeriod? {
      timeline.activePlayingPeriod(at: currentPhaseIndex)
    }
    package var precedingPeriod: GamePeriod? { timeline.precedingPeriod(at: currentPhaseIndex) }
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

    package var clockPhase: ClockPhase {
      currentPhase.isBreak ? .breakTime : .quarter
    }

    package var period: Int { currentPhase.associatedPeriod.number }
    package var isTimerRunning: Bool { countdown.isRunning }
    package var currentDurationSeconds: Int { currentPhase.durationSeconds }
    package var timerProjection: GameCountdown.Projection {
      countdown.projection(durationSeconds: currentDurationSeconds)
    }
    package var isPeriodComplete: Bool { timerProjection.status == .complete }
    package var scoringContext: GameScoringContext? {
      GameScoringContext.resolve(
        phase: currentPhase, countdown: countdown,
        isAwaitingCentrePassConfirmation: isShowingLastCentrePassBanner,
        lateScoringPeriodNumber: lateScoringPeriodNumber)
    }

    package var canEditTime: Bool {
      !isTimerRunning && !isPeriodComplete && !isTransitioningPeriod
        && !isTimerOperationPending && !isShowingLastCentrePassBanner
    }

    package var canScoreGoal: Bool { scoringContext != nil && !isTransitioningPeriod }
    package var canUndoGoal: Bool {
      canUndo && (!isShowingLastCentrePassBanner || canUndoDuringConfirmation)
    }

    package var canFinishGame: Bool {
      GameProgress(
        phaseIndex: currentPhaseIndex, countdown: countdown,
        isAwaitingCentrePassConfirmation: isShowingLastCentrePassBanner
      )
      .isFinalPeriodComplete(in: timeline) && !isShowingLastCentrePassBanner
    }

    package var canMoveToNextQuarter: Bool {
      currentPhase.isPlayingPeriod
        && !isPeriodComplete
        && !isShowingLastCentrePassBanner
        && !isTransitioningPeriod
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
      isTimerOperationPending: Bool = false, alert: AlertState<Alert>? = nil,
      alarms: AlarmPermissionFeature.State = AlarmPermissionFeature.State(),
      controlsPresentation: ControlsPresentation = ControlsPresentation.shown,
      canUndo: Bool = false, canUndoDuringConfirmation: Bool = false, centrePassTeamID: Team.ID,
      currentPhaseIndex: Int = 0, elapsedSeconds: Int = 0, swapSides: Bool = false, gameID: Game.ID,
      goalFeedbackTrigger: Int = 0, hasShownAlarmSchedulingFailureAlert: Bool = false,
      isSavingCourtOrientation: Bool = false, isShowingLastCentrePassBanner: Bool = false,
      isTransitioningPeriod: Bool = false, lateScoringPeriodNumber: Int? = nil,
      periods: [GamePeriod], startedAt: Date, teamA: Team, teamAScore: Int = 0, teamB: Team,
      teamBScore: Int = 0, timerEndsAt: Date? = nil,
      presentationDetent: PresentationDetent = .height(112),
      detents: Set<PresentationDetent> = [.height(112), .height(200)]
    ) {
      self.timeInput = timeInput
      self.editedPhaseIndex = editedPhaseIndex
      self.isTimerOperationPending = isTimerOperationPending
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
      self.isTransitioningPeriod = isTransitioningPeriod
      self.lateScoringPeriodNumber = lateScoringPeriodNumber
      self.periods = periods
      self.startedAt = startedAt
      self.teamA = teamA
      self.teamAScore = teamAScore
      self.teamB = teamB
      self.teamBScore = teamBScore
      self.timerEndsAt = timerEndsAt
      self.presentationDetent = presentationDetent
      self.detents = detents
    }
  }

  package enum Action: BindableAction {
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
      case .alarms(.delegate(.proPromotionTapped)):
        guard state.controlsPresentation == .shown else { return .none }
        state.controlsPresentation = .dismissingForPaywall
        return .none

      case .editTimeButtonTapped:
        guard state.canEditTime, state.controlsPresentation == .shown else { return .none }
        state.editedPhaseIndex = state.currentPhaseIndex
        state.controlsPresentation = .dismissingForTimeInput
        return .none

      case .timeInput(.presented(.delegate(.committed(let seconds)))):
        guard let phaseIndex = state.editedPhaseIndex, state.canEditTime,
          phaseIndex == state.currentPhaseIndex,
          (1...state.currentDurationSeconds).contains(seconds)
        else {
          state.timeInput?.errorMessage = "The clock has changed. Close the editor and try again."
          return .none
        }
        state.timeInput?.isSaving = true
        let gameID = state.gameID
        return .run { send in
          await send(
            .timeCorrectionResponse(
              await Result {
                try await gameTimer.setRemainingTime(gameID, phaseIndex, seconds)
              }))
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

      case .timeCorrectionResponse(.success(let snapshot)):
        applyTimer(snapshot.game, to: &state)
        state.timeInput = nil
        return .none

      case .timeCorrectionResponse(.failure(let error)):
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
            allowedSeconds: 1...state.currentDurationSeconds, selectedUnit: .seconds)
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
          await send(.alarmScheduleResponse(await gameTimer.scheduleAlarm(gameID)))
        }

      case .alarmScheduleResponse(let failed):
        if failed, !state.hasShownAlarmSchedulingFailureAlert {
          state.alert = .alarmSchedulingFailed
          state.hasShownAlarmSchedulingFailureAlert = true
        }
        return .none

      case .alarms, .alert, .delegate:
        return .none

      case .swapSidesButtonTapped:
        guard !state.isSavingCourtOrientation else { return .none }
        state.isSavingCourtOrientation = true
        let gameID = state.gameID
        return .run { send in
          let result = await Result {
            try await gameSession.execute(gameID, .swapSides, now).acceptedSnapshot().game.swapSides
          }
          await send(.swapSidesResponse(result))
        }

      case .swapSidesResponse(.success(let swapSides)):
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
        state.centrePassTeamID =
          state.teamA.id == state.centrePassTeamID ? state.teamB.id : state.teamA.id
        return updateCentrePassEffect(gameID: state.gameID, teamID: state.centrePassTeamID)

      case .centrePassTeamButtonTapped(let teamID):
        guard
          state.currentPhase.isPlayingPeriod,
          !state.isShowingLastCentrePassBanner,
          teamID == state.teamA.id || teamID == state.teamB.id,
          teamID != state.centrePassTeamID
        else { return .none }
        return updateCentrePassEffect(gameID: state.gameID, teamID: teamID)

      case .centrePassTeamResponse(.success(let teamID)):
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
        return .merge(
          .cancel(id: CancelID.timer),
          finishGameEffect(state: state)
        )

      case .finishGameResponse(.success(let gameID)):
        return .send(.delegate(.gameFinished(gameID)))

      case .finishGameResponse(.failure):
        return .none

      case .goalButtonTapped(let teamID):
        guard teamID == state.teamA.id || teamID == state.teamB.id else { return .none }
        synchronizeTimer(state: &state, now: now)
        guard state.canScoreGoal else {
          if state.isPeriodComplete {
            return reconcileTimerEffect(gameID: state.gameID)
          }
          return .none
        }
        return insertGoalEffect(state: state, teamID: teamID)

      case .goalResponse(.success(let snapshot)):
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

      case .lastCentrePassResponse(.success(let snapshot)):
        state.centrePassTeamID = snapshot.centrePassTeamID
        state.isShowingLastCentrePassBanner = false
        state.isTransitioningPeriod = false
        return refreshActivityEffect(gameID: state.gameID)

      case .lastCentrePassResponse(.failure):
        state.isTransitioningPeriod = false
        return .none

      case .pauseTimerButtonTapped:
        guard state.isTimerRunning, !state.isTransitioningPeriod, state.timeInput == nil else {
          return .none
        }
        synchronizeTimer(state: &state, now: now)
        state.timerEndsAt = nil
        state.isTimerOperationPending = true
        return .merge(
          .cancel(id: CancelID.timer),
          pauseTimerEffect(gameID: state.gameID, expectedPhaseIndex: state.currentPhaseIndex)
        )

      case .timerPauseResponse(.success(let snapshot)):
        state.isTimerOperationPending = false
        applyTimer(snapshot.game, to: &state)
        return .none

      case .timerPauseResponse(.failure):
        state.isTimerOperationPending = false
        return reconcileTimerEffect(gameID: state.gameID)

      case .sceneBecameActive:
        guard !state.isTransitioningPeriod else { return .none }
        return reconcileTimerEffect(gameID: state.gameID)

      case .sceneBecameInactive:
        return .cancel(id: CancelID.timer)

      case .skipBreakButtonTapped:
        guard state.currentPhase.isBreak, !state.isTransitioningPeriod else { return .none }
        return skipCurrentPhase(state: &state)

      case .skipPhaseResponse(.success(let snapshot)):
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
          !state.isTimerOperationPending,
          state.timeInput == nil,
          state.controlsPresentation == .shown,
          !state.isTransitioningPeriod,
          !state.isPeriodComplete,
          state.currentPhase.isBreak || !state.isShowingLastCentrePassBanner
        else { return .none }
        state.timerEndsAt = GameTimerClient.endDate(
          durationSeconds: state.currentDurationSeconds,
          elapsedSeconds: state.elapsedSeconds,
          now: now
        )
        return .merge(
          startTimerEffect(
            gameID: state.gameID,
            expectedPhaseIndex: state.currentPhaseIndex
          ),
          timerEffect()
        )

      case .timerTick:
        guard state.isTimerRunning, !state.isTransitioningPeriod else { return .none }
        synchronizeTimer(state: &state, now: now)
        guard state.isPeriodComplete else { return .none }
        state.timerEndsAt = nil
        return .merge(
          .cancel(id: CancelID.timer),
          reconcileTimerEffect(gameID: state.gameID)
        )

      case .timerReconcileResponse(.success(let snapshot)):
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

      case .timerStartResponse(.success(let update)):
        state.isTimerOperationPending = false
        applyTimer(update.snapshot.game, to: &state)
        if update.alarmSchedulingFailed, !state.hasShownAlarmSchedulingFailureAlert {
          state.alert = .alarmSchedulingFailed
          state.hasShownAlarmSchedulingFailureAlert = true
        }
        return .none

      case .timerStartResponse(.failure):
        state.isTimerOperationPending = false
        return reconcileTimerEffect(gameID: state.gameID)

      case .undoButtonTapped:
        guard state.canUndoGoal else { return .none }
        return undoGoalEffect(state: state)

      case .undoResponse(.success(let snapshot)):
        apply(snapshot, to: &state)
        return refreshActivityEffect(gameID: state.gameID)

      case .undoResponse(.failure):
        return .none
      case .binding(_):
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
      .cancellable(id: CancelID.timerOperation, cancelInFlight: true)
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
    let gameID = state.gameID
    let completedPeriod = state.lastCompletedQuarterNumber
    return .run { send in
      await send(
        .lastCentrePassResponse(
          await Result {
            try await gameScoring.resolveCentrePass(gameID, completedPeriod, wasLastCentrePassTaken)
          }))
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
            goalID: goalID, createdAt: createdAt, points: points, scoringContext: scoringContext))
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
    .cancellable(id: CancelID.timerOperation, cancelInFlight: true)
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
    .cancellable(id: CancelID.timerOperation, cancelInFlight: true)
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
          await Result {
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
      await send(.undoResponse(await Result { try await gameScoring.undo(gameID) }))
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
    return .run { send in
      await send(
        .centrePassTeamResponse(
          await Result { try await gameScoring.selectCentrePass(gameID, teamID) }))
    }
  }

  package init() {

  }
}

extension AlertState where Action == ScoringFeature.Alert {
  static package var alarmSchedulingFailed: Self {
    Self {
      TextState("Quarter alerts unavailable")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      TextState(
        "The game timer will keep running, but Supershot couldn’t schedule its alarms. Try pausing and resuming the timer."
      )
    }
  }
}
