import ApplicationDependency
import ComposableArchitecture
import CustomDump
import Dependencies
import DependenciesAdditionsBasics
import Foundation
import SQLiteData
import SwiftUI
import Testing

@testable import Supershot
import DependenciesTestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct ScoringFeatureTests {
#if os(iOS)
    @Test(arguments: [0, 1, 6])
    func keepsScreenAwakeUntilScoringTaskIsCancelled(phaseIndex: Int) async {
      let isIdleTimerDisabled = LockIsolated(false)
      var state = Self.state()
      state.currentPhaseIndex = phaseIndex
      let store = TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        $0.application.$isIdleTimerDisabled = .init(isIdleTimerDisabled)
      }

      let task = await store.send(.keepScreenAwakeTask)
      expectNoDifference(isIdleTimerDisabled.value, true)
      await task.cancel()
      expectNoDifference(isIdleTimerDisabled.value, false)

      let resumedTask = await store.send(.keepScreenAwakeTask)
      expectNoDifference(isIdleTimerDisabled.value, true)
      await resumedTask.cancel()
      expectNoDifference(isIdleTimerDisabled.value, false)
      await store.finish()
    }
#endif

    @Test(arguments: 0...6)
    func swappingSidesPreservesGameStateAndCanBeReversed(phaseIndex: Int) async throws {
      var game = Self.game()
      game.currentPhaseIndex = phaseIndex
      let database = try await Self.seed(game)
      var state = Self.state()
      state.currentPhaseIndex = phaseIndex
      state.teamAScore = 7
      state.teamBScore = 4
      state.centrePassTeamID = state.teamB.id
      state.elapsedSeconds = 30
      let originalLayout = state.courtLayout
      let store = TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        $0.defaultDatabase = database
      }

      await store.send(.swapSidesButtonTapped) {
        $0.isSavingCourtOrientation = true
      }
      await store.receive(\.swapSidesResponse) {
        $0.isSavingCourtOrientation = false
        $0.swapSides = true
      }
      expectNoDifference(
        store.state.courtLayout,
        ScoringFeature.CourtLayout(left: originalLayout.right, right: originalLayout.left)
      )
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(snapshot.game.swapSides, true)
      expectNoDifference(snapshot.game.teamAID, state.teamA.id)
      expectNoDifference(snapshot.game.teamBID, state.teamB.id)
      expectNoDifference(snapshot.game.teamABibColorHex, game.teamABibColorHex)
      expectNoDifference(snapshot.game.teamBBibColorHex, game.teamBBibColorHex)
      let reopened = ScoringFeature.State(snapshot: snapshot)
      expectNoDifference(reopened.swapSides, true)
      expectNoDifference(reopened.courtLayout.left.id, originalLayout.right.id)

      await store.send(.swapSidesButtonTapped) {
        $0.isSavingCourtOrientation = true
      }
      await store.receive(\.swapSidesResponse) {
        $0.isSavingCourtOrientation = false
        $0.swapSides = false
      }
      expectNoDifference(store.state, state)
      let restored = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(restored.game, game)
      await store.finish()
    }

    @Test
    func pendingSwapIgnoresAdditionalTaps() async {
      var state = Self.state()
      state.isSavingCourtOrientation = true
      let store = TestStore(initialState: state) {
        ScoringFeature()
      }
      await store.send(.swapSidesButtonTapped)
      expectNoDifference(store.state, state)
      await store.finish()
    }

    @Test(arguments: [false, true], 0...6)
    func courtLayoutKeepsScoreColourAndCentrePassWithTeam(
      swapSides: Bool,
      phaseIndex: Int
    ) {
      var state = Self.state()
      state.swapSides = swapSides
      state.currentPhaseIndex = phaseIndex
      state.teamA.bibColor = .blue
      state.teamB.bibColor = .red
      state.teamAScore = 7
      state.teamBScore = 4
      state.centrePassTeamID = state.teamB.id
      let a = ScoringFeature.CourtTeam(team: state.teamA, score: 7, hasCentrePass: false)
      let b = ScoringFeature.CourtTeam(team: state.teamB, score: 4, hasCentrePass: true)
      let teamAIsLeft = [true, true, false, false, true, true, false][phaseIndex]
        != swapSides
      expectNoDifference(
        state.courtLayout,
        teamAIsLeft
          ? ScoringFeature.CourtLayout(left: a, right: b)
          : ScoringFeature.CourtLayout(left: b, right: a)
      )
    }

    @Test
    func courtSidesUsePeriodNumberRatherThanPhaseIndex() {
      var state = Self.state()
      state.periods = testGamePeriods(gameID: state.gameID, count: 2, durationSeconds: 900)
      state.periods[0].breakAfterDurationSeconds = nil
      state.currentPhaseIndex = 1
      expectNoDifference(state.period, 2)
      expectNoDifference(state.courtLayout.left.id, state.teamB.id)
    }

    @Test
    func failedSwapLeavesCourtLayoutUnchangedAndAllowsRetry() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let state = Self.state()
      let store = TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        $0.defaultDatabase = database
      }
      await store.send(.swapSidesButtonTapped) {
        $0.isSavingCourtOrientation = true
      }
      await store.receive(\.swapSidesResponse) {
        $0.isSavingCourtOrientation = false
        $0.alert = AlertState {
          TextState("Couldn’t swap sides")
        } actions: {
          ButtonState(role: .cancel, action: .dismissButtonTapped) {
            TextState("OK")
          }
        } message: {
          TextState("Please try again.")
        }
      }
      expectNoDifference(store.state.courtLayout, state.courtLayout)
      await store.send(.alert(.dismiss)) {
        $0.alert = nil
      }
      _ = try await Self.seed(Self.game())
      await store.send(.swapSidesButtonTapped) {
        $0.isSavingCourtOrientation = true
      }
      await store.receive(\.swapSidesResponse) {
        $0.isSavingCourtOrientation = false
        $0.swapSides = true
      }
      expectNoDifference(store.state.courtLayout.left.id, state.teamB.id)
      await store.finish()
    }

    @Test
    func reconciliationRestoresPersistedCourtOrientation() async throws {
      var game = Self.game()
      game.swapSides = true
      let database = try await Self.seed(game)
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: Self.state()) {
        ScoringFeature()
      }
      await store.send(.timerReconcileResponse(.success(snapshot))) {
        $0.swapSides = true
      }
      expectNoDifference(store.state.courtLayout.left.id, UUID(2))
      await store.finish()
    }

    @Test
    func gameTimelineIsFourQuartersWithBreaksBetweenThem() {
      expectNoDifference(
        GameTimeline(periods: Self.periods())!.phases,
        [
          .period(testGamePeriodReference(number: 1), durationSeconds: 900),
          .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120),
          .period(testGamePeriodReference(number: 2), durationSeconds: 900),
          .breakTime(after: testGamePeriodReference(number: 2), durationSeconds: 300),
          .period(testGamePeriodReference(number: 3), durationSeconds: 900),
          .breakTime(after: testGamePeriodReference(number: 3), durationSeconds: 120),
          .period(testGamePeriodReference(number: 4), durationSeconds: 900),
        ]
      )
    }

    @Test
    func twoPeriodGameUsesOneBreakAndFinishesAfterSecondPeriod() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 2
      let periods = testGamePeriods(
        gameID: game.id,
        count: 2,
        durationSeconds: 1_800,
        breakDurationSeconds: 600
      )
      let database = try await Self.seed(game, periods: periods)
      let client = GameTimerClient.live

      expectNoDifference(
        GameTimeline(periods: periods)!.phases,
        [
          .period(testGamePeriodReference(number: 1), durationSeconds: 1_800),
          .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 600),
          .period(testGamePeriodReference(number: 2), durationSeconds: 1_800),
        ]
      )

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(game.id, 2)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(snapshot.game.elapsedSeconds, 1_800)
      expectNoDifference(snapshot.game.timerEndsAt, nil)
      expectNoDifference(ScoringFeature.State(snapshot: snapshot).canFinishGame, true)
    }

    @Test
    func skippingQuarterStartsItsBreakAndRequestsLastCentrePass() async throws {
      let database = try await Self.seed(Self.game())
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 0)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 1)
      expectNoDifference(
        snapshot.currentPhase,
        .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120)
      )
      expectNoDifference(snapshot.game.elapsedSeconds, 0)
      expectNoDifference(
        snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1_120)
      )
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func skippingBreakAdvancesToPausedQuarterWhileCentrePassRemainsPending() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 1
      game.isAwaitingCentrePassConfirmation = true
      game.timerEndsAt = Date(timeIntervalSince1970: 1_100)
      let database = try await Self.seed(game)
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 1)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(
        snapshot.currentPhase,
        .period(testGamePeriodReference(number: 2), durationSeconds: 900)
      )
      expectNoDifference(snapshot.game.countdown, GameCountdown())
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func zeroLengthBreakPassesStraightToPausedNextQuarter() async throws {
      let game = Self.game()
      let periods = testGamePeriods(
        gameID: game.id,
        durationSeconds: 900,
        breakDurations: [0, 300, 120]
      )
      let database = try await Self.seed(game, periods: periods)

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        @Dependency(\.gameTimer) var client
        return try await client.skip(UUID(3), 0)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 1)
      expectNoDifference(snapshot.game.countdown, GameCountdown())
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func reconciliationCanCrossAQuarterAndItsBreak() async throws {
      var game = Self.game()
      game.timerEndsAt = Date(timeIntervalSince1970: 1_050)
      let database = try await Self.seed(game)
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_300)
        $0.defaultDatabase = database
      } operation: {
        try await client.reconcile(UUID(3))
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(snapshot.game.countdown, GameCountdown())
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func pausedQuarterCannotRecordGoal() async throws {
      let database = try await Self.seed(Self.game())
      let store = TestStore(initialState: Self.state()) {
        ScoringFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
        $0.uuid = .incrementing
      }

      await store.send(.goalButtonTapped(UUID(1)))

      let goals = try await database.read { db in try Goal.fetchAll(db) }
      expectNoDifference(goals, [])
    }

    @Test(arguments: [false, true])
    func runningQuarterRecordsGoalWithAuthoritativeQuarterAndElapsedTime(swappedSides: Bool) async throws {
      var game = Self.game()
      game.timerEndsAt = Date(timeIntervalSince1970: 1_600)
      game.swapSides = swappedSides
      let database = try await Self.seed(game)
      var state = Self.state()
      state.swapSides = swappedSides
      state.timerEndsAt = game.timerEndsAt
      let store = TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
        $0.uuid = .incrementing
      }

      await store.send(.goalButtonTapped(UUID(1))) {
        $0.elapsedSeconds = 300
      }
      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.goalFeedbackTrigger = 1
        $0.teamAScore = 1
      }

      let goal = try await database.read { db in try Goal.fetchOne(db) }
      expectNoDifference(goal?.gamePeriodID, testGamePeriodID(gameID: UUID(3), position: 0))
      expectNoDifference(goal?.elapsedSeconds, 300)
      expectNoDifference(goal?.teamID, UUID(1))
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let reopened = ScoringFeature.State(snapshot: snapshot)
      let scoredTeam = swappedSides ? reopened.courtLayout.right : reopened.courtLayout.left
      expectNoDifference(scoredTeam.id, UUID(1))
      expectNoDifference(scoredTeam.score, 1)
      expectNoDifference(scoredTeam.hasCentrePass, false)
      await store.finish()
    }

    @Test
    func scoringAndUndoingDisplayedLeftTeamPreservesOrientation() async throws {
      var game = Self.game()
      game.swapSides = true
      game.timerEndsAt = Date(timeIntervalSince1970: 1_600)
      let database = try await Self.seed(game)
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: ScoringFeature.State(snapshot: snapshot)) {
        ScoringFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
        $0.uuid = .incrementing
      }

      await store.send(.goalButtonTapped(store.state.courtLayout.left.id)) {
        $0.elapsedSeconds = 300
      }
      await store.receive(\.goalResponse) {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.goalFeedbackTrigger = 1
        $0.teamBScore = 1
      }
      expectNoDifference(store.state.courtLayout.left.score, 1)
      expectNoDifference(store.state.courtLayout.right.score, 0)
      expectNoDifference(store.state.courtLayout.left.hasCentrePass, true)

      await store.send(.undoButtonTapped)
      await store.receive(\.undoResponse) {
        $0.canUndo = false
        $0.centrePassTeamID = UUID(1)
        $0.teamBScore = 0
      }
      expectNoDifference(store.state.courtLayout.left.id, UUID(2))
      expectNoDifference(store.state.courtLayout.left.score, 0)
      expectNoDifference(store.state.courtLayout.right.hasCentrePass, true)
      let reopened = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(reopened.game.swapSides, true)
      expectNoDifference(reopened.goals, [])
      await store.finish()
    }

    @Test
    func disabledGoalSoundsDoNotPlay() async {
      let soundPlayed = LockIsolated(false)
      var state = Self.state()
      state.$soundEffectsEnabled.withLock { $0 = false }
      var gameTimer = GameTimerClient.live
      gameTimer.refreshActivity = { _ in }
      let store = TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        $0.gameTimer = gameTimer
        $0.soundEffects = SoundEffectsClient(
          playGoal: { soundPlayed.setValue(true) }
        )
      }

      await store.send(
        .goalResponse(
          .success(
            ScoringFeature.ScoreSnapshot(
              canUndo: true,
              centrePassTeamID: UUID(2),
              teamAScore: 1
            )
          )
        )
      ) {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.goalFeedbackTrigger = 1
        $0.teamAScore = 1
      }
      await store.finish()

      expectNoDifference(soundPlayed.value, false)
    }

    @Test
    func pendingCentrePassBlocksNextQuarterStart() async {
      var quarter = Self.state()
      quarter.currentPhaseIndex = 2
      quarter.isShowingLastCentrePassBanner = true
      let quarterStore = TestStore(initialState: quarter) {
        ScoringFeature()
      }

      await quarterStore.send(.startTimerButtonTapped)
      expectNoDifference(quarterStore.state.timerEndsAt, nil)
    }

    @Test
    func skippingFinalQuarterMakesGameFinishable() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 6
      let database = try await Self.seed(game)
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 6)
      }
      let state = ScoringFeature.State(snapshot: snapshot)

      expectNoDifference(snapshot.game.currentPhaseIndex, 6)
      expectNoDifference(snapshot.game.elapsedSeconds, 900)
      expectNoDifference(snapshot.game.timerEndsAt, nil)
      expectNoDifference(state.canFinishGame, true)
    }

    @Test
    func finishingFinalQuarterPersistsResultAndEndsPresentation() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 6
      game.elapsedSeconds = 900
      game.lateScoringPeriodNumber = 4
      let database = try await Self.seed(game)
      let endedPresentations = LockIsolated<[Game.ID]>([])
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: ScoringFeature.State(snapshot: snapshot)) {
        ScoringFeature()
      } withDependencies: {
        $0.defaultDatabase = database
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.gameTimer.endPresentation = { id in endedPresentations.withValue { $0.append(id) } }
      }

      expectNoDifference(store.state.canScoreGoal, true)
      expectNoDifference(store.state.canFinishGame, true)
      await store.send(.finishGameButtonTapped)
      await store.receive(\.finishGameResponse)
      await store.receive {
        if case let .delegate(.gameFinished(id)) = $0 { id == game.id } else { false }
      }

      let stored = try await database.read { try Game.find(game.id).fetchOne($0) }
      expectNoDifference(stored?.endedAt, Date(timeIntervalSince1970: 1_000))
      expectNoDifference(stored?.elapsedSeconds, 900)
      expectNoDifference(stored?.timerEndsAt, nil)
      expectNoDifference(endedPresentations.value, [game.id])
      await store.finish()
    }

    @Test
    func finalQuarterConfirmationMustBeAnsweredBeforeFinishing() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 6
      game.elapsedSeconds = 900
      game.lateScoringPeriodNumber = 4
      game.isAwaitingCentrePassConfirmation = true
      let database = try await Self.seed(game)
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: ScoringFeature.State(snapshot: snapshot)) {
        ScoringFeature()
      }

      expectNoDifference(store.state.canScoreGoal, true)
      expectNoDifference(store.state.canFinishGame, false)
      await store.send(.finishGameButtonTapped)
      let stored = try await database.read { try Game.find(game.id).fetchOne($0) }
      expectNoDifference(stored?.endedAt, nil)
      await store.finish()
    }

    @Test
    func finishRejectsStaleScreenProgress() async throws {
      let database = try await Self.seed(Self.game())
      var state = Self.state()
      state.currentPhaseIndex = 6
      state.elapsedSeconds = 900
      let store = TestStore(initialState: state) { ScoringFeature() } withDependencies: {
        $0.defaultDatabase = database
        $0.date.now = Date(timeIntervalSince1970: 1_000)
      }
      await store.send(.finishGameButtonTapped)
      await store.receive { if case .finishGameResponse(.failure) = $0 { true } else { false } }
      let stored = try await database.read { try Game.find(UUID(3)).fetchOne($0) }
      expectNoDifference(stored?.currentPhaseIndex, 0)
      expectNoDifference(stored?.elapsedSeconds, 0)
      expectNoDifference(stored?.endedAt, nil)
      await store.finish()
    }

    private nonisolated static func game() -> Game {
      Game(
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 500),
        endedAt: nil,
        teamAID: UUID(1),
        teamBID: UUID(2),
        centrePassTeamID: UUID(1)
      )
    }

    private nonisolated static func periods() -> [GamePeriod] {
      testGamePeriods(
        gameID: UUID(3),
        durationSeconds: 900,
        breakDurations: [120, 300, 120]
      )
    }

    private nonisolated static func state() -> ScoringFeature.State {
      ScoringFeature.State(
        centrePassTeamID: UUID(1),
        gameID: UUID(3),
        periods: periods(),
        startedAt: Date(timeIntervalSince1970: 500),
        teamA: ScoringFeature.Team(id: UUID(1), name: "Ravens"),
        teamB: ScoringFeature.Team(id: UUID(2), name: "Swifts")
      )
    }

    private static func seed(
      _ game: Game,
      periods: [GamePeriod] = periods()
    ) async throws -> any DatabaseWriter {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(1), name: "Ravens")
          Team(id: UUID(2), name: "Swifts")
          game
        }
        try GamePeriod.insert { periods }.execute(db)
      }
      return database
    }
  }
}
