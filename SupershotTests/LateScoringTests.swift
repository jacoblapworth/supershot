import ComposableArchitecture
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.date.now = Date(timeIntervalSince1970: 1_000)
    $0.uuid = .incrementing
    $0.gameTimer.refreshActivity = { _ in }
    $0.soundEffects.playGoal = {}
  })
  struct LateScoringTests {
    enum Window: CaseIterable {
      case runningBreak, pausedBreak, waitingQuarter, finalQuarter
    }

    @Test(arguments: Window.allCases, [false, true])
    func lateGoalsPreserveClockAndConfirmation(window: Window, pending: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: window, pending: pending)
      let completed = game.lateScoringPeriodNumber!
      for team in [UUID(1), UUID(2)] {
        _ = try await ScoreGoalIntent(gameID: game.id, teamID: team,
          expectedPhaseIndex: game.currentPhaseIndex, completedPeriodNumber: completed).perform()
      }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(snapshot.teamAScore, 1)
      expectNoDifference(snapshot.teamBScore, 1)
      expectNoDifference(snapshot.game.countdown, game.countdown)
      expectNoDifference(snapshot.game.currentPhaseIndex, game.currentPhaseIndex)
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, pending)
      expectNoDifference(snapshot.game.centrePassTeamID, game.centrePassTeamID)
      for goal in snapshot.goals {
        expectNoDifference(goal.gamePeriodID, testGamePeriodID(gameID: game.id, position: completed - 1))
        expectNoDifference(goal.elapsedSeconds, 900)
        expectNoDifference(goal.createdAt, Date(timeIntervalSince1970: 1_000))
        #expect(goal.isLate)
      }
      let content = GameActivityAttributes.ContentState(
        centrePassTeamID: snapshot.game.centrePassTeamID!,
        elapsedSeconds: snapshot.game.elapsedSeconds, phaseIndex: snapshot.game.currentPhaseIndex,
        phase: snapshot.currentPhase, teamAScore: snapshot.teamAScore, teamBScore: snapshot.teamBScore,
        timerEndsAt: snapshot.game.timerEndsAt, isAwaitingCentrePassConfirmation: pending,
        lateScoringPeriodNumber: completed)
      expectNoDifference(content.scoringContext, .completedPeriod(number: completed))
      let state = ScoringFeature.State(snapshot: snapshot)
      #expect(state.canScoreGoal)
      #expect(state.canUndoGoal)
    }

    @Test
    func appLateGoalAndUndoPreservePendingQuestionAndBreak() async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .runningBreak, pending: true)
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: ScoringFeature.State(snapshot: snapshot)) { ScoringFeature() }
      await store.send(.goalButtonTapped(UUID(2)))
      await store.receive { if case .goalResponse(.success) = $0 { true } else { false } } assert: {
        $0.canUndo = true
        $0.canUndoDuringConfirmation = true
        $0.centrePassTeamID = UUID(2)
        $0.teamBScore = 1
        $0.goalFeedbackTrigger = 1
      }
      await store.send(.undoButtonTapped)
      await store.receive { if case .undoResponse(.success) = $0 { true } else { false } } assert: {
        $0.canUndo = false
        $0.canUndoDuringConfirmation = false
        $0.centrePassTeamID = UUID(1)
        $0.teamBScore = 0
      }
      let stored = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(stored.game.countdown, game.countdown)
      #expect(stored.game.isAwaitingCentrePassConfirmation)
      #expect(stored.goals.isEmpty)
      await store.finish()
    }

    @Test
    func startingAndImmediatelyPausingNextQuarterClosesLateWindow() async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .waitingQuarter, pending: false)
      let client = GameTimerClient.live
      _ = try await client.startOrResume(game.id, game.currentPhaseIndex)
      let paused = try await client.pause(game.id, game.currentPhaseIndex)
      expectNoDifference(paused.game.elapsedSeconds, 0)
      expectNoDifference(paused.game.lateScoringPeriodNumber, nil)
      #expect(!ScoringFeature.State(snapshot: paused).canScoreGoal)
      await #expect(throws: (any Error).self) {
        try await database.write {
          try ScoringFeature.insertGoal($0, gameID: game.id, teamID: UUID(1),
            expectedPhaseIndex: game.currentPhaseIndex, goalID: UUID(10),
            createdAt: Date(timeIntervalSince1970: 1_000), scoringContext: .completedPeriod(number: 1))
        }
      }
    }

    @Test(arguments: [false, true])
    func zeroBreakOpensLateWindowAfterNaturalOrSkippedCompletion(skip: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .waitingQuarter, pending: false)
      let endsAt = Date(timeIntervalSince1970: skip ? 1_050 : 1_000)
      try await database.write { db in
        try Game.find(game.id).update {
          $0.currentPhaseIndex = 0
          $0.lateScoringPeriodNumber = #bind(nil as Int?)
          $0.timerEndsAt = #bind(endsAt)
        }.execute(db)
        try GamePeriod.find(testGamePeriodID(gameID: game.id, position: 0)).update {
          $0.breakAfterDurationSeconds = #bind(nil as Int?)
        }.execute(db)
      }
      let client = GameTimerClient.live
      let completed = try await (skip ? client.skip(game.id, 0) : client.reconcile(game.id))
      expectNoDifference(completed.game.currentPhaseIndex, 1)
      expectNoDifference(completed.game.lateScoringPeriodNumber, 1)
      #expect(completed.game.isAwaitingCentrePassConfirmation)
      await #expect(throws: (any Error).self) {
        try await database.write {
          try ScoringFeature.insertGoal($0, gameID: game.id, teamID: UUID(1), expectedPhaseIndex: 0,
            goalID: UUID(9), createdAt: Date(timeIntervalSince1970: 1_000),
            scoringContext: .completedPeriod(number: 1))
        }
      }
      let staleTimer = try await client.startOrResume(game.id, 0)
      expectNoDifference(staleTimer.snapshot.game.countdown, completed.game.countdown)
      _ = try await database.write {
        try ScoringFeature.insertGoal($0, gameID: game.id, teamID: UUID(1), expectedPhaseIndex: 1,
          goalID: UUID(10), createdAt: Date(timeIntervalSince1970: 1_000),
          scoringContext: .completedPeriod(number: 1))
      }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(snapshot.goals.first?.elapsedSeconds, 900)
    }

    @Test(arguments: ["phase", "period", "finished", "expiredBreak"])
    func staleLateGoalCannotChangeScore(reason: String) async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .runningBreak, pending: true)
      if reason == "finished" {
        try await database.write { db in
          try Game.find(game.id).update { $0.endedAt = #bind(Date(timeIntervalSince1970: 999)) }.execute(db)
        }
      }
      await #expect(throws: (any Error).self) {
        try await database.write {
          try ScoringFeature.insertGoal($0, gameID: game.id, teamID: UUID(1),
            expectedPhaseIndex: reason == "phase" ? 0 : 1, goalID: UUID(10),
            createdAt: Date(timeIntervalSince1970: reason == "expiredBreak" ? 1_100 : 1_000),
            scoringContext: .completedPeriod(number: reason == "period" ? 2 : 1))
        }
      }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      #expect(snapshot.goals.isEmpty)
      expectNoDifference(snapshot.game.centrePassTeamID, game.centrePassTeamID)
      expectNoDifference(snapshot.game.countdown, game.countdown)
    }

    @Test
    func pendingQuestionDoesNotAllowUndoOfAnEarlierQuartersLateGoal() async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .runningBreak, pending: true)
      try await database.write { db in
        try Game.find(game.id).update {
          $0.currentPhaseIndex = 3
          $0.lateScoringPeriodNumber = #bind(2)
        }.execute(db)
        try Goal.insert {
          Goal(id: UUID(10), gameID: game.id,
            gamePeriodID: testGamePeriodID(gameID: game.id, position: 0), teamID: UUID(1),
            elapsedSeconds: 900, isLate: true, createdAt: Date(timeIntervalSince1970: 999))
        }.execute(db)
      }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: ScoringFeature.State(snapshot: snapshot)) { ScoringFeature() }
      #expect(!store.state.canUndoGoal)
      await store.send(.undoButtonTapped)
      let stored = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(stored, snapshot)
      await store.finish()
    }

    @Test(arguments: [1_099.999, 1_100, 1_100.001], [false, true])
    func lateGoalAtBreakBoundaryRejectsStalePhase(timestamp: Double, pending: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .runningBreak, pending: pending)
      let record = {
        try await database.write {
          try ScoringFeature.insertGoal($0, gameID: game.id, teamID: UUID(1),
            expectedPhaseIndex: 1, goalID: UUID(10),
            createdAt: Date(timeIntervalSince1970: timestamp),
            scoringContext: .completedPeriod(number: 1))
        }
      }
      if timestamp < 1_100 {
        _ = try await record()
      } else {
        await #expect(throws: (any Error).self) { try await record() }
      }
      let stored = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      #expect(stored.goals.count == (timestamp < 1_100 ? 1 : 0))
      expectNoDifference(stored.game.countdown, game.countdown)
      expectNoDifference(stored.game.currentPhaseIndex, game.currentPhaseIndex)
    }

    @Test
    func staleUndoCannotDeleteEarlierQuartersLateGoalDuringConfirmation() async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .runningBreak, pending: true)
      _ = try await database.write {
        try ScoringFeature.insertGoal($0, gameID: game.id, teamID: UUID(1),
          expectedPhaseIndex: 1, goalID: UUID(10), createdAt: Date(timeIntervalSince1970: 1_000),
          scoringContext: .completedPeriod(number: 1))
      }
      let before = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: ScoringFeature.State(snapshot: before)) { ScoringFeature() }
      #expect(store.state.canUndoGoal)
      try await database.write { db in
        try Game.find(game.id).update {
          $0.currentPhaseIndex = 3
          $0.lateScoringPeriodNumber = #bind(2)
        }.execute(db)
      }
      let advanced = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      await store.send(.undoButtonTapped)
      await store.receive { if case .undoResponse(.failure) = $0 { true } else { false } }
      let after = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(after, advanced)
      await store.finish()
    }

    @Test
    func finishRaceCannotDeleteALateGoal() async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: .finalQuarter, pending: false)
      _ = try await database.write {
        try ScoringFeature.insertGoal($0, gameID: game.id, teamID: UUID(1), expectedPhaseIndex: 6,
          goalID: UUID(10), createdAt: Date(timeIntervalSince1970: 1_000),
          scoringContext: .completedPeriod(number: 4))
      }
      let before = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      let store = TestStore(initialState: ScoringFeature.State(snapshot: before)) { ScoringFeature() }
      try await database.write { db in
        try Game.find(game.id).update { $0.endedAt = #bind(Date(timeIntervalSince1970: 1_001)) }.execute(db)
      }
      await store.send(.undoButtonTapped)
      await store.receive { if case .undoResponse(.failure) = $0 { true } else { false } }
      let after = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(after.goals, before.goals)
      expectNoDifference(after.game.centrePassTeamID, before.game.centrePassTeamID)
      await store.finish()
    }

    private func seed(window: Window, pending: Bool) throws -> Game {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let game = Game(
        id: UUID(3), startedAt: Date(timeIntervalSince1970: 900),
        teamAID: UUID(1), teamBID: UUID(2), centrePassTeamID: UUID(1),
        isAwaitingCentrePassConfirmation: pending,
        lateScoringPeriodNumber: window == .finalQuarter ? 4 : 1,
        currentPhaseIndex: window == .finalQuarter ? 6 : window == .waitingQuarter ? 2 : 1,
        elapsedSeconds: window == .finalQuarter ? 900 : window == .waitingQuarter ? 0 : 20,
        timerEndsAt: window == .runningBreak ? Date(timeIntervalSince1970: 1_100) : nil
      )
      try database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: "Ravens")
          Team(id: UUID(2), name: "Swifts")
        }.execute(db)
        try Game.insert { game }.execute(db)
        try GamePeriod.insert { testGamePeriods(gameID: game.id, breakDurationSeconds: 120) }.execute(db)
      }
      return game
    }
  }
}
