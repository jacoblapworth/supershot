import Clocks
import ComposableArchitecture
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct ScoringFeatureTests {
    @Test
    func timerStartsPausesAndResumes() async throws {
      let clock = TestClock()
      let store = Self.makeScoringStore(clock: clock)

      await store.send(.startTimerButtonTapped) {
        $0.hasTimerStartedThisPeriod = true
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      }

      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 1
      }

      await store.send(.pauseTimerButtonTapped) {
        $0.isTimerRunning = false
        $0.timerEndsAt = nil
      }
      await store.receive {
        guard case .timerPauseResponse(.success) = $0 else { return false }
        return true
      }

      await store.send(.startTimerButtonTapped) {
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      }

      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 2
      }

      await store.send(.pauseTimerButtonTapped) {
        $0.isTimerRunning = false
        $0.timerEndsAt = nil
      }
      await store.receive {
        guard case .timerPauseResponse(.success) = $0 else { return false }
        return true
      }
      await store.finish()
    }

    @Test
    func timerAutoPausesAtPeriodEnd() async throws {
      let clock = TestClock()
      var state = Self.scoringState()
      state.elapsedSeconds = state.periodDurationSeconds - 1
      let store = Self.makeScoringStore(state: state, clock: clock)

      await store.send(.startTimerButtonTapped) {
        $0.hasTimerStartedThisPeriod = true
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_001)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      }

      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = $0.periodDurationSeconds
        $0.isTimerRunning = false
        $0.timerEndsAt = nil
      }
      await store.receive {
        guard case .timerReconcileResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isShowingLastCentrePassBanner = true
      }
      await store.finish()
    }

    @Test
    func nextQuarterResetsTimer() async throws {
      var state = Self.scoringState()
      state.elapsedSeconds = 42
      state.hasTimerStartedThisPeriod = true
      let store = Self.makeScoringStore(state: state)

      await store.send(.endQuarterButtonTapped) {
        $0.isShowingLastCentrePassBanner = true
      }
      await store.send(.lastCentrePassNotTakenButtonTapped) {
        $0.isTransitioningPeriod = true
      }
      await store.receive {
        guard case .lastCentrePassResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 0
        $0.hasTimerStartedThisPeriod = false
        $0.isShowingLastCentrePassBanner = false
        $0.isTransitioningPeriod = false
        $0.period = 2
      }

      let game = try await store.dependencies.defaultDatabase.read { db in
        try Game.find(UUID(3)).fetchOne(db)
      }
      expectNoDifference(game?.centrePassTeamID, UUID(1))
      expectNoDifference(game?.currentPeriod, 2)
      expectNoDifference(game?.elapsedSeconds, 0)
      expectNoDifference(game?.isAwaitingCentrePassConfirmation, false)
      await store.finish()
    }

    @Test
    func takenLastCentrePassSwitchesTeamForNextQuarter() async throws {
      var state = Self.scoringState()
      state.elapsedSeconds = 42
      state.hasTimerStartedThisPeriod = true
      let store = Self.makeScoringStore(state: state)

      await store.send(.endQuarterButtonTapped) {
        $0.isShowingLastCentrePassBanner = true
      }
      await store.send(.lastCentrePassTakenButtonTapped) {
        $0.isTransitioningPeriod = true
      }
      await store.receive {
        guard case .lastCentrePassResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.centrePassTeamID = UUID(2)
        $0.elapsedSeconds = 0
        $0.hasTimerStartedThisPeriod = false
        $0.isShowingLastCentrePassBanner = false
        $0.isTransitioningPeriod = false
        $0.period = 2
      }

      let game = try await store.dependencies.defaultDatabase.read { db in
        try Game.find(UUID(3)).fetchOne(db)
      }
      expectNoDifference(game?.centrePassTeamID, UUID(2))
      expectNoDifference(game?.currentPeriod, 2)
      await store.finish()
    }

    @Test
    func lastCentrePassBannerKeepsQuarterUntilAnswered() async throws {
      var state = Self.scoringState()
      state.elapsedSeconds = 42
      state.hasTimerStartedThisPeriod = true
      let store = Self.makeScoringStore(state: state)

      await store.send(.endQuarterButtonTapped) {
        $0.isShowingLastCentrePassBanner = true
      }

      expectNoDifference(store.state.period, 1)
      expectNoDifference(store.state.elapsedSeconds, 42)
      expectNoDifference(store.state.centrePassTeamID, UUID(1))
      expectNoDifference(store.state.canMoveToNextQuarter, false)
      await store.finish()
    }

    @Test
    func nextQuarterUnavailableBeforePeriodStarts() async throws {
      let store = Self.makeScoringStore()

      await store.send(.endQuarterButtonTapped)
    }

    @Test
    func endingQuarterRunsConfiguredBreakThenWaitsForContinue() async throws {
      let clock = TestClock()
      var state = Self.scoringState()
      state.elapsedSeconds = 42
      state.firstBreakDurationSeconds = 2
      state.hasTimerStartedThisPeriod = true
      let store = Self.makeScoringStore(state: state, clock: clock)

      await store.send(.endQuarterButtonTapped) {
        $0.clockPhase = .break
        $0.elapsedSeconds = 0
        $0.isShowingLastCentrePassBanner = true
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_002)
      }
      await store.send(.lastCentrePassNotTakenButtonTapped) {
        $0.isTransitioningPeriod = true
      }
      await store.receive {
        guard case .lastCentrePassResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isShowingLastCentrePassBanner = false
        $0.isTransitioningPeriod = false
      }

      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 1
      }

      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 2
        $0.isTimerRunning = false
        $0.timerEndsAt = nil
      }
      await store.receive {
        guard case .timerReconcileResponse(.success) = $0 else { return false }
        return true
      }

      expectNoDifference(store.state.canContinueToNextQuarter, true)
      await store.send(.continueToNextQuarterButtonTapped) {
        $0.isTransitioningPeriod = true
      }
      await store.receive {
        guard case .nextQuarterResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.clockPhase = .quarter
        $0.elapsedSeconds = 0
        $0.hasTimerStartedThisPeriod = false
        $0.isTransitioningPeriod = false
        $0.period = 2
      }

      expectNoDifference(store.state.isShowingOriginalTeamOrder, false)
      let game = try await store.dependencies.defaultDatabase.read { db in
        try Game.find(UUID(3)).fetchOne(db)
      }
      expectNoDifference(game?.currentPeriod, 2)
      expectNoDifference(game?.isInBreak, false)
      await store.finish()
    }

    @Test
    func halfTimeUsesItsOwnDurationAndDisablesGoals() async throws {
      var state = Self.scoringState()
      state.clockPhase = .break
      state.elapsedSeconds = 60
      state.firstBreakDurationSeconds = 120
      state.halfTimeDurationSeconds = 600
      state.hasTimerStartedThisPeriod = true
      state.period = 2
      state.secondBreakDurationSeconds = 300
      let store = Self.makeScoringStore(state: state)

      expectNoDifference(store.state.currentDurationSeconds, 600)
      expectNoDifference(store.state.isShowingOriginalTeamOrder, false)
      await store.send(.goalButtonTapped(UUID(1)))
      await store.send(.centrePassTeamButtonTapped(UUID(2)))

      await store.send(.skipBreakButtonTapped) {
        $0.elapsedSeconds = 600
        $0.isTransitioningPeriod = true
      }
      await store.receive {
        guard case .nextQuarterResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.clockPhase = .quarter
        $0.elapsedSeconds = 0
        $0.hasTimerStartedThisPeriod = false
        $0.isTransitioningPeriod = false
        $0.period = 3
      }

      expectNoDifference(store.state.isShowingOriginalTeamOrder, true)
      await store.finish()
    }

    @Test
    func zeroDurationBreakAdvancesToNextQuarterPaused() async throws {
      var state = Self.scoringState()
      state.elapsedSeconds = 42
      state.hasTimerStartedThisPeriod = true
      let store = Self.makeScoringStore(state: state)

      await store.send(.endQuarterButtonTapped) {
        $0.isShowingLastCentrePassBanner = true
        $0.isTimerRunning = false
      }
      await store.send(.lastCentrePassNotTakenButtonTapped) {
        $0.isTransitioningPeriod = true
      }
      await store.receive {
        guard case .lastCentrePassResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 0
        $0.hasTimerStartedThisPeriod = false
        $0.isShowingLastCentrePassBanner = false
        $0.isTransitioningPeriod = false
        $0.period = 2
      }
      await store.finish()
    }

    @Test
    func fourthQuarterNeverEntersABreak() async throws {
      let clock = TestClock()
      var state = Self.scoringState()
      state.elapsedSeconds = state.periodDurationSeconds - 1
      state.firstBreakDurationSeconds = 120
      state.halfTimeDurationSeconds = 600
      state.period = 4
      state.secondBreakDurationSeconds = 300
      let store = Self.makeScoringStore(state: state, clock: clock)

      await store.send(.startTimerButtonTapped) {
        $0.hasTimerStartedThisPeriod = true
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_001)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      }
      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = $0.periodDurationSeconds
        $0.isTimerRunning = false
        $0.timerEndsAt = nil
      }
      await store.receive {
        guard case .timerReconcileResponse(.success) = $0 else { return false }
        return true
      }

      expectNoDifference(store.state.clockPhase, .quarter)
      expectNoDifference(store.state.canFinishGame, true)
      await store.finish()
    }

    @Test
    func evenQuarterGoalRemainsAttributedToDisplayedTeamIdentity() async throws {
      var state = Self.scoringState()
      state.isTimerRunning = true
      state.period = 2
      let store = Self.makeScoringStore(state: state)

      expectNoDifference(store.state.isShowingOriginalTeamOrder, false)
      await store.send(.goalButtonTapped(UUID(2)))
      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.teamBScore = 1
      }

      let goal = try await store.dependencies.defaultDatabase.read { db in
        try Goal.fetchOne(db)
      }
      expectNoDifference(goal?.teamID, UUID(2))
      expectNoDifference(goal?.period, 2)
      await store.finish()
    }

    @Test
    func runningGoalUsesAuthoritativeEndDateForTimestamp() async throws {
      var state = Self.scoringState()
      state.elapsedSeconds = 123
      state.hasTimerStartedThisPeriod = true
      state.isTimerRunning = true
      state.timerEndsAt = Date(timeIntervalSince1970: 1_200)
      let store = Self.makeScoringStore(state: state)

      await store.send(.goalButtonTapped(UUID(1))) {
        $0.elapsedSeconds = 700
      }
      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.teamAScore = 1
      }

      let goal = try await store.dependencies.defaultDatabase.read { db in
        try Goal.fetchOne(db)
      }
      expectNoDifference(goal?.elapsedSeconds, 700)
      await store.finish()
    }

    @Test
    func backgroundingLeavesAuthoritativeTimerRunning() async throws {
      let clock = TestClock()
      let store = Self.makeScoringStore(clock: clock)

      await store.send(.startTimerButtonTapped) {
        $0.hasTimerStartedThisPeriod = true
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      }

      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 1
      }

      await store.send(.sceneBecameInactive)
      await clock.advance(by: .seconds(119))
      await store.send(.sceneBecameActive)
      await store.receive {
        guard case .timerReconcileResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 120
      }
      await clock.advance(by: .seconds(1))
      await store.receive {
        guard case .timerTick = $0 else { return false }
        return true
      } assert: {
        $0.elapsedSeconds = 121
      }
      await store.send(.sceneBecameInactive)
      await store.finish()

      let snapshot = try await store.dependencies.defaultDatabase.read { db in
        try GameSnapshot.fetch(db, gameID: UUID(3))
      }
      expectNoDifference(snapshot.game.currentPeriod, 1)
      expectNoDifference(snapshot.game.elapsedSeconds, 0)
      expectNoDifference(snapshot.game.hasTimerStartedCurrentPeriod, true)
      expectNoDifference(snapshot.game.centrePassTeamID, UUID(1))
      expectNoDifference(
        snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1_900)
      )
      expectNoDifference(store.state.elapsedSeconds, 121)
      expectNoDifference(store.state.isTimerRunning, true)
    }

    @Test
    func leavingScoringKeepsTimerRunningAndDismisses() async throws {
      let didDismiss = LockIsolated(false)
      var state = Self.scoringState()
      state.elapsedSeconds = 123
      state.hasTimerStartedThisPeriod = true
      state.isTimerRunning = true
      state.period = 2
      state.timerEndsAt = Date(timeIntervalSince1970: 1_777)
      let store = Self.makeScoringStore(
        state: state,
        dismiss: DismissEffect { didDismiss.setValue(true) }
      )

      await store.send(.closeButtonTapped)
      await store.finish()

      let game = try await store.dependencies.defaultDatabase.read { db in
        try Game.find(UUID(3)).fetchOne(db)
      }
      expectNoDifference(didDismiss.value, true)
      expectNoDifference(game?.currentPeriod, 2)
      expectNoDifference(game?.elapsedSeconds, 123)
      expectNoDifference(game?.hasTimerStartedCurrentPeriod, true)
      expectNoDifference(game?.centrePassTeamID, UUID(1))
      expectNoDifference(game?.timerEndsAt, Date(timeIntervalSince1970: 1_777))
    }

    @Test
    func pausedScoringRequiresConfirmationAndPersistsGoal() async throws {
      let store = Self.makeScoringStore()

      await store.send(.goalButtonTapped(UUID(1))) {
        $0.confirmationDialog = ConfirmationDialogState<ScoringFeature.ConfirmationDialogAction>.pausedGoalConfirmation
        $0.pendingPausedGoalTeamID = UUID(1)
      }

      await store.send(.confirmationDialog(.presented(.recordGoalButtonTapped))) {
        $0.confirmationDialog = nil
        $0.pendingPausedGoalTeamID = nil
      }

      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.teamAScore = 1
      }

      let goals = try await store.dependencies.defaultDatabase.read { db in
        try Goal.fetchAll(db)
      }
      expectNoDifference(goals.count, 1)
      expectNoDifference(goals.first?.centrePassTeamID, UUID(1))
      expectNoDifference(goals.first?.teamID, UUID(1))
      expectNoDifference(goals.first?.period, 1)
      expectNoDifference(goals.first?.elapsedSeconds, 0)
      await store.finish()
    }

    @Test
    func undoRemovesLatestGoal() async throws {
      var state = Self.scoringState()
      state.isTimerRunning = true
      let store = Self.makeScoringStore(state: state)

      await store.send(.goalButtonTapped(UUID(1)))
      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.teamAScore = 1
      }

      await store.send(.goalButtonTapped(UUID(2)))
      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.centrePassTeamID = UUID(1)
        $0.teamBScore = 1
      }

      await store.send(.undoButtonTapped)
      await store.receive {
        guard case .undoResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.centrePassTeamID = UUID(2)
        $0.teamBScore = 0
      }

      let goals = try await store.dependencies.defaultDatabase.read { db in
        try Goal.fetchAll(db)
      }
      expectNoDifference(goals.count, 1)
      expectNoDifference(goals.first?.teamID, UUID(1))
      await store.finish()
    }

    @Test
    func centrePassCorrectionPersistsAndControlsNextGoal() async throws {
      var state = Self.scoringState()
      state.isTimerRunning = true
      let store = Self.makeScoringStore(state: state)

      await store.send(.centrePassTeamButtonTapped(UUID(2)))
      await store.receive {
        guard case let .centrePassTeamResponse(.success(teamID)) = $0 else { return false }
        return teamID == UUID(2)
      } assert: {
        $0.centrePassTeamID = UUID(2)
      }

      let snapshot = try await store.dependencies.defaultDatabase.read { db in
        try GameSnapshot.fetch(db, gameID: UUID(3))
      }
      expectNoDifference(ScoringFeature.State(snapshot: snapshot).centrePassTeamID, UUID(2))

      await store.send(.goalButtonTapped(UUID(1)))
      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(1)
        $0.teamAScore = 1
      }

      let goal = try await store.dependencies.defaultDatabase.read { db in
        try Goal.fetchOne(db)
      }
      expectNoDifference(goal?.centrePassTeamID, UUID(2))
      await store.finish()
    }

    @Test
    func failedGoalWriteLeavesScoreAndCentrePassUnchanged() async throws {
      var state = Self.scoringState()
      state.isTimerRunning = true
      let store = Self.makeScoringStore(state: state)
      try await store.dependencies.defaultDatabase.write { db in
        try Game.find(UUID(3)).delete().execute(db)
      }

      await store.send(.goalButtonTapped(UUID(1)))
      await store.receive {
        guard case .goalResponse(.failure) = $0 else { return false }
        return true
      }

      expectNoDifference(store.state.centrePassTeamID, UUID(1))
      expectNoDifference(store.state.teamAScore, 0)
      expectNoDifference(store.state.canUndo, false)
    }

    @Test
    func failedCentrePassCorrectionLeavesSelectionUnchanged() async throws {
      let store = Self.makeScoringStore()
      try await store.dependencies.defaultDatabase.write { db in
        try Game.find(UUID(3)).delete().execute(db)
      }

      await store.send(.centrePassTeamButtonTapped(UUID(2)))
      await store.receive {
        guard case .centrePassTeamResponse(.failure) = $0 else { return false }
        return true
      }

      expectNoDifference(store.state.centrePassTeamID, UUID(1))
    }

    @Test
    func invalidCentrePassTeamIsIgnored() async throws {
      let store = Self.makeScoringStore()

      await store.send(.centrePassTeamButtonTapped(UUID(99)))

      expectNoDifference(store.state.centrePassTeamID, UUID(1))
    }

    @Test
    func failedQuarterTransitionLeavesProgressUnchanged() async throws {
      var state = Self.scoringState()
      state.elapsedSeconds = 42
      state.hasTimerStartedThisPeriod = true
      let store = Self.makeScoringStore(state: state)
      try await store.dependencies.defaultDatabase.write { db in
        try Game.find(UUID(3)).delete().execute(db)
      }

      await store.send(.endQuarterButtonTapped) {
        $0.isShowingLastCentrePassBanner = true
      }
      await store.send(.lastCentrePassTakenButtonTapped) {
        $0.isTransitioningPeriod = true
      }
      await store.receive {
        guard case .lastCentrePassResponse(.failure) = $0 else { return false }
        return true
      } assert: {
        $0.isTransitioningPeriod = false
      }

      expectNoDifference(store.state.centrePassTeamID, UUID(1))
      expectNoDifference(store.state.elapsedSeconds, 42)
      expectNoDifference(store.state.hasTimerStartedThisPeriod, true)
      expectNoDifference(store.state.isShowingLastCentrePassBanner, true)
      expectNoDifference(store.state.period, 1)
    }

    @Test
    func finishGameStoresEndDateAndDelegatesGameID() async throws {
      let endedAt = Date(timeIntervalSince1970: 2_000)
      var state = Self.scoringState()
      state.hasTimerStartedThisPeriod = true
      state.period = 4
      state.teamAScore = 2
      state.teamBScore = 1
      let store = Self.makeScoringStore(state: state, date: endedAt)

      var finishedGameID: Game.ID?
      await store.send(.finishGameButtonTapped)
      await store.receive {
        guard case let .finishGameResponse(.success(gameID)) = $0 else { return false }
        finishedGameID = gameID
        return true
      }
      await store.receive {
        guard case .delegate(.gameFinished) = $0 else { return false }
        return true
      }

      let game = try await store.dependencies.defaultDatabase.read { db in
        try Game.find(UUID(3)).fetchOne(db)
      }
      expectNoDifference(game?.endedAt, endedAt)
      expectNoDifference(game?.currentPeriod, 4)
      expectNoDifference(game?.hasTimerStartedCurrentPeriod, true)
      expectNoDifference(game?.centrePassTeamID, UUID(1))
      expectNoDifference(finishedGameID, UUID(3))
    }

    private static func makeScoringStore(
        state: ScoringFeature.State = scoringState(),
        date: Date = Date(timeIntervalSince1970: 1_000),
        clock: TestClock<Duration>? = nil,
        dismiss: DismissEffect? = nil,
        gameTimer: GameTimerClient? = nil
      ) -> TestStoreOf<ScoringFeature> {
        let clockStart = clock?.now
        return TestStore(initialState: state) {
          ScoringFeature()
        } withDependencies: {
          if let clock, let clockStart {
            $0.date = DateGenerator {
              let components = clockStart.duration(to: clock.now).components
              let seconds = Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
              return date.addingTimeInterval(seconds)
            }
          } else {
            $0.date.now = date
          }
          $0.uuid = .incrementing
          try! $0.bootstrapDatabase()
          try! clearDatabase($0.defaultDatabase)
          try! $0.defaultDatabase.write { db in
            try Team.insert {
              Team(id: UUID(1), name: "Ravens")
              Team(id: UUID(2), name: "Swifts")
            }
            .execute(db)

            try Game.insert {
              Game(
                id: UUID(3),
                startedAt: state.startedAt,
                endedAt: nil,
                teamAID: UUID(1),
                teamBID: UUID(2),
                centrePassTeamID: state.centrePassTeamID,
                periodDurationSeconds: state.periodDurationSeconds,
                firstBreakDurationSeconds: state.firstBreakDurationSeconds,
                halfTimeDurationSeconds: state.halfTimeDurationSeconds,
                secondBreakDurationSeconds: state.secondBreakDurationSeconds,
                isInBreak: state.clockPhase == .break,
                isAwaitingCentrePassConfirmation: state.isShowingLastCentrePassBanner,
                currentPeriod: state.period,
                elapsedSeconds: state.elapsedSeconds,
                hasTimerStartedCurrentPeriod: state.hasTimerStartedThisPeriod,
                timerEndsAt: state.timerEndsAt
              )
            }
            .execute(db)
          }
          if let clock {
            $0.continuousClock = clock
          }
          if let dismiss {
            $0.dismiss = dismiss
          }
          if let gameTimer {
            $0.gameTimer = gameTimer
          }
        }
      }


      private nonisolated static func scoringState() -> ScoringFeature.State {
        ScoringFeature.State(
          centrePassTeamID: UUID(1),
          gameID: UUID(3),
          startedAt: Date(timeIntervalSince1970: 500),
          teamA: ScoringFeature.Team(
            id: UUID(1),
            bibColorHex: TeamColorPalette.blue,
            name: "Ravens"
          ),
          teamB: ScoringFeature.Team(
            id: UUID(2),
            bibColorHex: TeamColorPalette.red,
            name: "Swifts"
          )
        )
      }
  }
}
