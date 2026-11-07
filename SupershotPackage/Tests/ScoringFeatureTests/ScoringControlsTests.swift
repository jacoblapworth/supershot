import AppUI
import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import GameCore
@testable import GameServices
import PermissionsFeature
@testable import ScoringFeature
import SharedModels
import SQLiteData
import Testing
import TestSupport
import UI

extension SupershotTestSuite {
  @MainActor
  struct ScoringControlsTests {
    @Test func onlyStartingTheSamePhaseRequestsCollapse() {
      #expect(ScoringPreviewScenario.running.state.scoringToolbarState.shouldCollapse(
        after: ScoringPreviewScenario.paused.state.scoringToolbarState
      ))
      #expect(ScoringPreviewScenario.runningBreak.state.scoringToolbarState.shouldCollapse(
        after: ScoringPreviewScenario.pausedBreak.state.scoringToolbarState
      ))
      #expect(!ScoringPreviewScenario.runningBreak.state.scoringToolbarState.shouldCollapse(
        after: ScoringPreviewScenario.paused.state.scoringToolbarState
      ))
      #expect(!ScoringPreviewScenario.failed.state.scoringToolbarState.shouldCollapse(
        after: ScoringPreviewScenario.ready.state.scoringToolbarState
      ))
    }

    @Test(arguments: [ScoringPreviewScenario.running, .runningBreak])
    func skippingDoesNotTemporarilyRevealResume(_ scenario: ScoringPreviewScenario) {
      var state = scenario.state
      state.timerEndsAt = nil
      state.operation = .skipping(phaseIndex: state.currentPhaseIndex)
      #expect(state.scoringToolbarState.sheetPrimaryControl == nil)
      #expect(state.scoringToolbarState.sheetReveal == nil)
    }

    @Test func sheetRevealChangesWithPhaseButNotTicksOrAvailability() {
      var state = ScoringPreviewScenario.pausedBreak.state
      let reveal = state.scoringToolbarState.sheetReveal
      state.elapsedSeconds += 1
      expectNoDifference(state.scoringToolbarState.sheetReveal, reveal)
      state.operation = .starting(phaseIndex: state.currentPhaseIndex)
      expectNoDifference(state.scoringToolbarState.sheetReveal, reveal)
      state.operation = nil
      state.alert = .operationFailed("Couldn’t start clock")
      expectNoDifference(state.scoringToolbarState.sheetReveal, reveal)
      #expect(ScoringPreviewScenario.nextQuarter.state.scoringToolbarState.sheetReveal != reveal)
      #expect(ScoringPreviewScenario.runningBreak.state.scoringToolbarState.sheetReveal == nil)
    }

    @Test func sheetRevealsProgressionForQuartersAndBreaks() {
      let scenarios: [(ScoringPreviewScenario, String?)] = [
        (.ready, "Start game"),
        (.running, nil),
        (.paused, "Resume"),
        (.nextQuarter, "Start Quarter 2"),
        (.waiting, "Start Quarter 2"),
        (.manualBreak, "Start break"),
        (.runningBreak, nil),
        (.pausedBreak, "Resume"),
        (.confirmation, nil),
        (.savingConfirmation, nil),
        (.starting, "Start game"),
        (.complete, "End game"),
        (.finishing, "End game"),
        (.failed, "Start game"),
      ]
      for (scenario, title) in scenarios {
        expectNoDifference(scenario.state.scoringToolbarState.sheetPrimaryControl?.title, title)
      }
    }

    @Test(arguments: ScoringPreviewScenario.allCases)
    func sheetControlsAreUniqueAndMatchExistingAvailability(_ scenario: ScoringPreviewScenario) {
      let state = scenario.state
      let toolbar = state.scoringToolbarState
      let controls = toolbar.additionalControls + [toolbar.sheetPrimaryControl].compactMap(\.self)
      expectNoDifference(Set(controls.map(\.action)).count, controls.count)
      for control in state.timerViewState.controls {
        expectNoDifference(controls.first { $0.action == control.action }, control)
      }
      expectNoDifference(
        controls.first { $0.action == .changeCentrePass }?.availability,
        state.canOperate ? .enabled : .disabled
      )
      expectNoDifference(
        controls.contains { $0.action == .editTime },
        state.timerViewState.editTime != nil
      )
      expectNoDifference(
        controls.first { $0.action == .endQuarter }?.availability,
        state.currentPhase.isPlayingPeriod ? (state.canMoveToNextQuarter ? .enabled : .disabled) : nil
      )
    }

    @Test func swapSidesShowsPendingUntilPersistenceCompletes() {
      var state = ScoringPreviewScenario.running.state
      state.isSavingCourtOrientation = true
      expectNoDifference(
        state.scoringToolbarState.additionalControls.first { $0.action == .swapSides }?.availability,
        .pending
      )
    }

    @Test func sheetActionsUseExistingReducerEntryPoints() {
      guard case .endQuarterButtonTapped = ScoringFeature.Action(control: .endQuarter),
            case .changeCentrePassButtonTapped = ScoringFeature.Action(control: .changeCentrePass),
            case .swapSidesButtonTapped = ScoringFeature.Action(control: .swapSides)
      else {
        Issue.record("Sheet controls must use the existing reducer actions")
        return
      }
    }

    @Test(arguments: ScoringPreviewScenario.allCases)
    func everyScenarioKeepsBothGoalsAndUsesDomainAvailability(_ scenario: ScoringPreviewScenario) {
      let state = scenario.state
      let toolbar = state.scoringToolbarState
      expectNoDifference(toolbar.courtLayout, state.courtLayout)
      expectNoDifference(toolbar.canScore, state.canScoreGoal)
      #expect(toolbar.courtLayout.left.id != toolbar.courtLayout.right.id)
      if state.operation != nil {
        #expect(!toolbar.canScore)
        #expect(!state.canStartOrResume)
        #expect(!state.canPause)
        #expect(!state.canSkipBreak)
      }
      // Starting a playing period and ending the game are never timer controls.
      #expect(!state.timerViewState.controls.contains { $0.action == .finishGame })
      if state.currentPhase.isPlayingPeriod, state.phaseStatus == .ready {
        #expect(!state.timerViewState.controls.contains { $0.action == .startOrResume })
      }
    }

    @Test(arguments: [
      ScoringPreviewScenario.running,
      .runningBreak,
      .pausedBreak,
      .manualBreak,
      .pausing,
      .skipping,
    ])
    func noQuarterStatusAppearsAboveGoals(_ scenario: ScoringPreviewScenario) {
      expectNoDifference(scenario.state.scoringToolbarState.content, .none)
    }

    #if os(iOS)
      @Test func timeEditorWaitsForPersistentSheetDismissalAndThenRestoresIt() async {
        let state = ScoringPreviewScenario.ready.state
        let duration = state.currentDurationSeconds
        let store = TestStore(initialState: state) { ScoringFeature() }
        await store.send(.editTimeButtonTapped) {
          $0.editedPhaseIndex = 0
          $0.controlsPresentation = .dismissingForTimeInput
        }
        #expect(store.state.timeInput == nil)
        await store.send(.controlsSheetDidDismiss) {
          $0.controlsPresentation = .hiddenForTimeInput
          $0.timeInput = .init(
            title: "Edit remaining time",
            totalSeconds: duration,
            allowedSeconds: 1 ... duration,
            selectedUnit: .seconds
          )
        }
        await store.send(.timeInput(.presented(.cancelButtonTapped)))
        await store.receive(\.timeInput.presented.delegate.cancelled) { $0.timeInput = nil }
        await store.send(.timeInputSheetDidDismiss) {
          $0.editedPhaseIndex = nil
          $0.controlsPresentation = .shown
        }
        await store.finish()
      }

      @Test func paywallWaitsForPersistentSheetDismissal() async {
        let store = TestStore(initialState: ScoringPreviewScenario.ready.state) { ScoringFeature() }
        await store.send(.alarms(.delegate(.proPromotionTapped))) {
          $0.controlsPresentation = .dismissingForPaywall
        }
        await store.send(.controlsSheetDidDismiss) { $0.controlsPresentation = .hiddenForPaywall }
        await store.receive(\.delegate)
        await store.send(.proPaywallDidDismiss) { $0.controlsPresentation = .shown }
        await store.finish()
      }
    #endif

    @Test func primaryActionsFollowGameProgress() {
      let scenarios: [(ScoringPreviewScenario, String, ScoringControlAction)] = [
        (.ready, "Start game", .startOrResume),
        (.nextQuarter, "Start Quarter 2", .startOrResume),
        (.paused, "Resume", .startOrResume),
        (.complete, "End game", .finishGame),
      ]
      for (scenario, title, action) in scenarios {
        guard case let .primary(control) = scenario.state.scoringToolbarState.content else {
          Issue.record("Missing primary action for \(scenario.rawValue)")
          continue
        }
        expectNoDifference(control.title, title)
        expectNoDifference(control.action, action)
        expectNoDifference(control.availability, .enabled)
      }
    }

    @Test func resumeHasOneIntentInBothLocations() throws {
      let state = ScoringPreviewScenario.paused.state
      guard case let .primary(primary) = state.scoringToolbarState.content else {
        Issue.record("Expected Resume")
        return
      }
      let timer = try #require(state.timerViewState.controls.first)
      expectNoDifference(primary.title, "Resume")
      expectNoDifference(timer.title, "Resume")
      expectNoDifference(primary.action, timer.action)
    }

    @Test(arguments: [0, 2])
    func zeroElapsedPausedQuarterOffersStart(phaseIndex: Int) {
      var state = ScoringPreviewScenario.paused.state
      state.currentPhaseIndex = phaseIndex
      state.elapsedSeconds = 0
      expectNoDifference(state.phaseStatus, .ready)
      guard case let .primary(control) = state.scoringToolbarState.content else {
        Issue.record("Expected start action")
        return
      }
      expectNoDifference(control.title, phaseIndex == 0 ? "Start game" : "Start Quarter 2")
      #expect(state.timerViewState.controls.isEmpty)
    }

    @Test func confirmationDoesNotDisableLateScoringOrRunningBreakControls() {
      let state = ScoringPreviewScenario.confirmation.state
      #expect(state.canScoreGoal)
      #expect(state.canPause)
      #expect(state.canSkipBreak)
      #expect(!state.canMoveToNextQuarter)
      #expect(!state.canFinishGame)
      guard case let .confirmation(confirmation) = state.scoringToolbarState.content else {
        Issue.record("Expected centre-pass confirmation")
        return
      }
      expectNoDifference(confirmation.period, 1)
      expectNoDifference(confirmation.availability, .enabled)
      #expect(state.timerViewState.controls.contains { $0.action == .pause })
      #expect(state.timerViewState.controls.contains { $0.action == .skipBreak })
      var waiting = state
      waiting.currentPhaseIndex = 2
      waiting.timerEndsAt = nil
      waiting.elapsedSeconds = 0
      #expect(!waiting.canStartOrResume)
      #expect(waiting.canScoreGoal)
    }

    @Test(arguments: [true, false])
    func confirmationSendsSelectedAnswerAndAllowsRetryAfterFailure(wasTaken: Bool) async {
      let state = ScoringPreviewScenario.confirmation.state
      let gameID = state.gameID
      let store = TestStore(initialState: state) { ScoringFeature() } withDependencies: {
        $0.gameScoring.resolveCentrePass = { requestedGameID, period, answer in
          expectNoDifference(requestedGameID, gameID)
          expectNoDifference(period, 1)
          expectNoDifference(answer, wasTaken)
          throw CocoaError(.fileWriteNoPermission)
        }
      }
      await store.send(.init(control: .confirmCentrePass(wasTaken))) {
        $0.operation = .confirmingCentrePass(period: 1)
      }
      guard case let .confirmation(confirmation) = store.state.scoringToolbarState.content else {
        Issue.record("Expected pending confirmation")
        return
      }
      expectNoDifference(confirmation.availability, .pending)
      await store.receive(\.lastCentrePassResponse) {
        $0.operation = nil
        $0.alert = .operationFailed("Couldn’t save centre pass")
      }
      #expect(store.state.isAwaitingCentrePassConfirmation)
      await store.send(.alert(.dismiss)) { $0.alert = nil }
      guard case let .confirmation(retry) = store.state.scoringToolbarState.content else {
        Issue.record("Expected confirmation to remain available for retry")
        return
      }
      expectNoDifference(retry.availability, .enabled)
      await store.finish()
    }

    @Test func confirmationIsIgnoredWhileAnotherOperationIsPending() async {
      let store = TestStore(initialState: ScoringPreviewScenario.savingConfirmation.state) {
        ScoringFeature()
      }
      await store.send(.centrePassConfirmed(true))
      await store.send(.centrePassConfirmed(false))
      await store.finish()
    }

    @Test func timerShowsSkipDuringRunningAndPausedBreaks() {
      for scenario in [ScoringPreviewScenario.runningBreak, .pausedBreak, .manualBreak] {
        let state = scenario.state
        #expect(state.timerViewState.controls.contains {
          $0.action == .skipBreak && $0.availability == .enabled
        })
      }
    }

    @Test func staleClockResponsesCannotOverwriteAnotherOperation() async {
      let state = ScoringPreviewScenario.starting.state
      let store = TestStore(initialState: state) { ScoringFeature() }
      await store.send(.timerPauseResponse(.failure(CancellationError())))
      await store.send(.skipPhaseResponse(.failure(CancellationError())))
      await store.send(.lastCentrePassResponse(.failure(CancellationError())))
      expectNoDifference(store.state.operation, .starting(phaseIndex: 0))
    }

    @Test func failedStartKeepsGameUnstartedAndAllowsRetryAfterDismissingError() async {
      let ready = ScoringPreviewScenario.ready.state
      let a = Team(id: ready.teamA.id, name: ready.teamA.name)
      let b = Team(id: ready.teamB.id, name: ready.teamB.name)
      let snapshot = GameSnapshot(
        game: Game(
          id: ready.gameID,
          startedAt: nil,
          teamAID: a.id,
          teamBID: b.id,
          centrePassTeamID: ready.centrePassTeamID
        ),
        goals: [],
        periods: ready.periods,
        teamA: a,
        teamB: b
      )
      let store = TestStore(initialState: ready) { ScoringFeature() } withDependencies: {
        $0.gameTimer.startOrResume = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        $0.gameTimer.reconcile = { _ in snapshot }
      }
      await store.send(.startTimerButtonTapped) { $0.operation = .starting(phaseIndex: 0) }
      await store.receive(\.timerStartResponse) {
        $0.operation = nil
        $0.alert = .operationFailed("Couldn’t start clock")
      }
      await store.receive(\.timerReconcileResponse)
      #expect(store.state.startedAt == nil)
      #expect(!store.state.isTimerRunning)
      await store.send(.alert(.presented(.dismissButtonTapped))) { $0.alert = nil }
      #expect(store.state.canStartOrResume)
      await store.finish()
    }

    @Test func firstClockCommitsStartDateAndImmediatePauseReopensAsReady() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let ready = ScoringPreviewScenario.ready.state
      let gameID = ready.gameID
      let a = Team(id: ready.teamA.id, name: ready.teamA.name)
      let b = Team(id: ready.teamB.id, name: ready.teamB.name)
      let game = Game(
        id: gameID,
        startedAt: nil,
        teamAID: a.id,
        teamBID: b.id,
        centrePassTeamID: ready.centrePassTeamID
      )
      let periods = ready.periods
      try await database.write { db in
        try Team.insert { a; b }.execute(db)
        try Game.insert { game }.execute(db)
        try GamePeriod.insert { periods }.execute(db)
      }
      let clock = TestClock()
      let start = Date(timeIntervalSince1970: 5000)
      let store = TestStore(initialState: ready) { ScoringFeature() } withDependencies: {
        $0.date.now = start
        $0.continuousClock = clock
        $0.gameTimer = .live
        $0.gameSession = .live
        $0.gamePresentation.update = { _, _ in false }
      }
      await store.send(.init(control: .startOrResume)) { $0.operation = .starting(phaseIndex: 0) }
      await store.receive(\.timerStartResponse) {
        $0.operation = nil
        $0.startedAt = start
        $0.timerEndsAt = start.addingTimeInterval(TimeInterval($0.currentDurationSeconds))
      }
      await store.send(.init(control: .pause)) {
        $0.operation = .pausing(phaseIndex: 0)
        $0.timerEndsAt = nil
      }
      await store.receive(\.timerPauseResponse) { $0.operation = nil }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: gameID) }
      let restored = ScoringFeature.State(snapshot: snapshot)
      expectNoDifference(restored.startedAt, start)
      expectNoDifference(restored.elapsedSeconds, 0)
      expectNoDifference(restored.phaseStatus, .ready)
      guard case let .primary(control) = restored.scoringToolbarState.content else {
        Issue.record("Expected Start after immediate pause")
        return
      }
      expectNoDifference(control.title, "Start game")
      await store.finish()
    }
  }
}
