@testable import AlarmClient
import AppUI
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import GameCore
@testable import GameServices
@testable import SharedModels
import SQLiteData
@testable import SubscriptionClient
import Testing
import TestSupport
@testable import UI
@testable import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  struct GameSessionTests {
    let now = Date(timeIntervalSince1970: 1000)

    @Test func expiredLiveGoalRejectsAndCommitsClockReconciliation() async throws {
      let before = try seed(endsAt: now)
      let update = try await execute(.recordGoal(command(context: .livePeriod(number: 1))))
      expectNoDifference(update.outcome, .rejected(.stalePhase))
      expectNoDifference(update.snapshot.game.currentPhaseIndex, 1)
      expectNoDifference(update.snapshot.game.timerEndsAt, now.addingTimeInterval(120))
      expectNoDifference(update.snapshot.game.lateScoringPeriodNumber, 1)
      expectNoDifference(update.snapshot.game.isAwaitingCentrePassConfirmation, true)
      expectNoDifference(update.snapshot.game.centrePassTeamID, before.game.centrePassTeamID)
      expectNoDifference(update.snapshot.goals, [])
      let persisted = try await read()
      expectNoDifference(persisted, update.snapshot)
    }

    @Test func stalePauseAtExpiredBreakCommitsNextWaitingPeriod() async throws {
      _ = try seed(phase: 1, endsAt: now, pending: true, late: 1)
      let update = try await execute(.timing(.pause, expectedPhaseIndex: 1))
      expectNoDifference(update.outcome, .rejected(.stalePhase))
      expectNoDifference(update.snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(update.snapshot.game.countdown, GameCountdown())
      expectNoDifference(update.snapshot.game.lateScoringPeriodNumber, 1)
      expectNoDifference(update.snapshot.game.isAwaitingCentrePassConfirmation, true)
      let persisted = try await read()
      expectNoDifference(persisted, update.snapshot)
    }

    @Test func lateGoalPreservesClockAndConfirmationAndUsesRecordingDate() async throws {
      let before = try seed(phase: 1, elapsed: 20, endsAt: now.addingTimeInterval(100), pending: true, late: 1)
      var goal = command(phase: 1, context: .completedPeriod(number: 1))
      goal.createdAt = now.addingTimeInterval(10)
      let update = try await execute(.recordGoal(goal), at: now.addingTimeInterval(500))
      expectNoDifference(update.outcome, .applied)
      expectNoDifference(update.snapshot.game.countdown, before.game.countdown)
      expectNoDifference(update.snapshot.game.isAwaitingCentrePassConfirmation, true)
      expectNoDifference(update.snapshot.goals.first?.createdAt, goal.createdAt)
      expectNoDifference(update.snapshot.goals.first?.elapsedSeconds, 900)
      expectNoDifference(update.snapshot.goals.first?.gamePeriodID, before.periods[0].id)
      let answer = try await execute(.resolveCentrePass(completedPeriod: 1, taken: true))
      expectNoDifference(answer.snapshot.game.centrePassTeamID, UUID(1))
      expectNoDifference(answer.snapshot.game.countdown, before.game.countdown)
      let repeated = try await execute(.resolveCentrePass(completedPeriod: 1, taken: true))
      expectNoDifference(repeated.outcome, .unchanged)
    }

    @Test func confirmationGatesStartAndImmediatePauseDoesNotReopenLateWindow() async throws {
      _ = try seed(phase: 2, pending: true, late: 1)
      let blocked = try await execute(.timing(.startOrResume, expectedPhaseIndex: 2))
      expectNoDifference(blocked.outcome, .rejected(.confirmationRequired))
      _ = try await execute(.resolveCentrePass(completedPeriod: 1, taken: false))
      let started = try await execute(.timing(.startOrResume, expectedPhaseIndex: 2))
      expectNoDifference(started.outcome, .applied)
      expectNoDifference(started.snapshot.game.lateScoringPeriodNumber, nil)
      let paused = try await execute(.timing(.pause, expectedPhaseIndex: 2))
      expectNoDifference(paused.snapshot.game.countdown, GameCountdown())
      let late = try await execute(.recordGoal(command(phase: 2, context: .completedPeriod(number: 1))))
      expectNoDifference(late.outcome, .rejected(.scoringUnavailable))
      expectNoDifference(late.snapshot.goals, [])
    }

    @Test(arguments: [BreakStartPolicy.automatic, .manual], [0, 120])
    func recoveryPreservesBreakPolicyAndNeverStartsPlayingPeriod(policy: BreakStartPolicy, breakSeconds: Int) async throws {
      _ = try seed(endsAt: now, policy: policy, breakSeconds: breakSeconds)
      let recovered = try await execute(.reconcile, at: now.addingTimeInterval(50))
      let hasBreak = breakSeconds > 0
      expectNoDifference(recovered.snapshot.game.currentPhaseIndex, 1)
      expectNoDifference(
        recovered.snapshot.game.timerEndsAt,
        hasBreak && policy == .automatic ? now.addingTimeInterval(120) : nil
      )
      expectNoDifference(recovered.snapshot.game.elapsedSeconds, hasBreak && policy == .automatic ? 50 : 0)
      expectNoDifference(recovered.snapshot.game.lateScoringPeriodNumber, 1)
      let again = try await execute(.reconcile, at: now.addingTimeInterval(50))
      expectNoDifference(again.outcome, .unchanged)
    }

    @Test func finishPreventsGoalsUndoAndCentrePassChanges() async throws {
      _ = try seed(phase: 6, endsAt: now)
      let finished = try await execute(.finish)
      expectNoDifference(finished.outcome, .applied)
      expectNoDifference(finished.snapshot.game.endedAt, now)
      let commands: [GameSessionCommand] = [
        .recordGoal(command(phase: 6, context: .completedPeriod(number: 4))),
        .undoGoal,
        .deleteGoal(UUID(10)),
        .selectCentrePass(UUID(2)),
        .resolveCentrePass(completedPeriod: 3, taken: true),
        .swapSides,
      ]
      for command in commands {
        let update = try await execute(command)
        expectNoDifference(update.outcome, .rejected(.gameFinished))
        expectNoDifference(update.snapshot, finished.snapshot)
      }
    }

    @Test func staleUndoDoesNotDeleteAnEarlierPeriodsLateGoal() async throws {
      let before = try seed(phase: 3, pending: true, late: 2)
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Goal.insert {
          Goal(
            id: UUID(10),
            gameID: UUID(3),
            gamePeriodID: before.periods[0].id,
            teamID: UUID(1),
            elapsedSeconds: 900,
            isLate: true,
            createdAt: .distantPast
          )
        }.execute(db)
      }
      let seeded = try await read()
      let update = try await execute(.undoGoal)
      expectNoDifference(update.outcome, .rejected(.confirmationRequired))
      expectNoDifference(update.snapshot, seeded)
    }

    @Test func storageFailureRollsBackReconciliationAndScoringTogether() async throws {
      let before = try seed(phase: 6, endsAt: now)
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try db.execute(sql:
          "CREATE TEMP TRIGGER reject_goal BEFORE INSERT ON goals BEGIN SELECT RAISE(ABORT, 'test failure'); END")
      }
      await #expect(throws: (any Error).self) {
        try await execute(.recordGoal(command(phase: 6, context: .completedPeriod(number: 4))))
      }
      let persisted = try await read()
      expectNoDifference(persisted, before)
      try await database.write { try $0.execute(sql: "DROP TRIGGER reject_goal") }
    }

    @Test func invalidCorrectionDoesNotReconcileRunningClock() async throws {
      let before = try seed(endsAt: now)
      let update = try await execute(.timing(.setRemainingTime(30), expectedPhaseIndex: 0))
      expectNoDifference(update.outcome, .rejected(.invalidCorrection))
      expectNoDifference(update.snapshot, before)
    }

    @Test(arguments: [0, 1, 2, 6], [false, true])
    func deletingHistoricalGoalUpdatesScoresWithoutChangingPlay(phase: Int, running: Bool) async throws {
      let before = try seed(
        phase: phase,
        elapsed: 30,
        endsAt: running ? now.addingTimeInterval(100) : nil,
        pending: phase == 1,
        late: phase == 1 ? 1 : nil
      )
      @Dependency(\.defaultDatabase) var database
      let deleted = Goal(
        id: UUID(10),
        gameID: UUID(3),
        gamePeriodID: before.periods[0].id,
        teamID: UUID(1),
        elapsedSeconds: 10,
        points: 2,
        createdAt: .distantPast
      )
      let retained = Goal(
        id: UUID(11),
        gameID: UUID(3),
        gamePeriodID: before.periods[0].id,
        teamID: UUID(2),
        elapsedSeconds: 20,
        createdAt: now
      )
      try await database.write { db in
        try Goal.insert { deleted; retained }.execute(db)
      }
      let update = try await execute(.deleteGoal(deleted.id))
      expectNoDifference(update.outcome, .applied)
      expectNoDifference(update.snapshot.game, before.game)
      expectNoDifference(update.snapshot.goals, [retained])
      expectNoDifference(update.snapshot.teamAScore, 0)
      expectNoDifference(update.snapshot.teamBScore, 1)
      let analysis = try await database.read { try GameAnalysisRequest(gameID: UUID(3)).fetch($0).analysis }
      let quarter = try #require(analysis.goalTimeline.quarters.last)
      expectNoDifference(quarter.teamAQuarterScore, 0)
      expectNoDifference(quarter.teamBQuarterScore, 1)
      expectNoDifference(quarter.goals.first?.teamAScore, 0)
      expectNoDifference(quarter.goals.first?.teamBScore, 1)
      let persisted = try await read()
      expectNoDifference(persisted, update.snapshot)
      let repeated = try await execute(.deleteGoal(deleted.id))
      expectNoDifference(repeated.outcome, .unchanged)
      expectNoDifference(repeated.snapshot, persisted)
    }

    @Test func completionPreventsDeletingAnExistingGoal() async throws {
      let before = try seed(phase: 6, endsAt: now)
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Goal.insert {
          Goal(
            id: UUID(10),
            gameID: UUID(3),
            gamePeriodID: before.periods[0].id,
            teamID: UUID(1),
            elapsedSeconds: 10,
            createdAt: .distantPast
          )
        }.execute(db)
      }
      let finished = try await execute(.finish)
      let deletion = try await execute(.deleteGoal(UUID(10)))
      expectNoDifference(deletion.outcome, .rejected(.gameFinished))
      expectNoDifference(deletion.snapshot, finished.snapshot)
      let persisted = try await read()
      expectNoDifference(persisted, finished.snapshot)
    }

    @Test func failedDeletionPreservesGoalAndGame() async throws {
      _ = try seed(endsAt: now.addingTimeInterval(100))
      _ = try await execute(.recordGoal(command(context: .livePeriod(number: 1))))
      let before = try await read()
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try db.execute(sql: "CREATE TEMP TRIGGER reject_delete BEFORE DELETE ON goals BEGIN SELECT RAISE(ABORT, 'test failure'); END")
      }
      await #expect(throws: (any Error).self) {
        try await execute(.deleteGoal(UUID(10)))
      }
      let persisted = try await read()
      expectNoDifference(persisted, before)
      try await database.write { try $0.execute(sql: "DROP TRIGGER reject_delete") }
    }

    @Test func deletingForeignGoalDoesNotAffectEitherGame() async throws {
      let before = try seed()
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Game.insert { Game(id: UUID(4), startedAt: .distantPast, teamAID: UUID(1), teamBID: UUID(2)) }.execute(db)
        let periods = testGamePeriods(gameID: UUID(4))
        try GamePeriod.insert { periods }.execute(db)
        try Goal.insert {
          Goal(id: UUID(20), gameID: UUID(4), gamePeriodID: periods[0].id, teamID: UUID(1), elapsedSeconds: 10, createdAt: .distantPast)
        }.execute(db)
      }
      let update = try await execute(.deleteGoal(UUID(20)))
      expectNoDifference(update.outcome, .unchanged)
      expectNoDifference(update.snapshot, before)
      let count = try await database.read { try Goal.find(UUID(20)).fetchCount($0) }
      expectNoDifference(count, 1)
    }

    private func command(phase: Int = 0, context: GameScoringContext) -> RecordGoalCommand {
      RecordGoalCommand(
        gameID: UUID(3),
        teamID: UUID(2),
        expectedPhaseIndex: phase,
        goalID: UUID(10),
        createdAt: now,
        scoringContext: context
      )
    }

    @Test func unstartedGameAllowsPreparationButRejectsScoringAndProgression() async throws {
      @Dependency(\.defaultDatabase) var database
      _ = try seed()
      try await database.write { db in
        try Game.find(UUID(3)).update { $0.startedAt = #bind(nil as Date?) }.execute(db)
      }
      let before = try await read()
      let commands: [GameSessionCommand] = [
        .timing(.pause, expectedPhaseIndex: nil),
        .timing(.skip, expectedPhaseIndex: nil),
        .recordGoal(command(context: .livePeriod(number: 1))),
        .undoGoal,
        .deleteGoal(UUID(10)),
        .resolveCentrePass(completedPeriod: 1, taken: true),
        .finish,
      ]
      for command in commands {
        let update = try await execute(command)
        expectNoDifference(update.outcome, .rejected(.gameNotStarted))
        expectNoDifference(update.snapshot, before)
        _ = await GamePresentationClient.live.update(update, command)
      }
      let reconciled = try await execute(.reconcile)
      expectNoDifference(reconciled.outcome, .unchanged)
      let prepared = try await execute(.selectCentrePass(UUID(2)))
      expectNoDifference(prepared.snapshot.game.centrePassTeamID, UUID(2))
      let swapped = try await execute(.swapSides)
      #expect(swapped.snapshot.game.swapSides)
      let corrected = try await execute(.timing(.setRemainingTime(600), expectedPhaseIndex: 0))
      #expect(corrected.snapshot.game.startedAt == nil)
      #expect(corrected.snapshot.scoringContext == nil)
      #expect(!corrected.snapshot.isFinalPeriodComplete)
    }

    @Test func firstClockStartsLifecycleOnceAndImmediatePauseIsReady() async throws {
      @Dependency(\.defaultDatabase) var database
      _ = try seed()
      try await database.write { db in
        try Game.find(UUID(3)).update { $0.startedAt = #bind(nil as Date?) }.execute(db)
      }
      let stale = try await execute(.timing(.startOrResume, expectedPhaseIndex: 2))
      expectNoDifference(stale.outcome, .rejected(.stalePhase))
      #expect(stale.snapshot.game.startedAt == nil)
      let started = try await execute(.timing(.startOrResume, expectedPhaseIndex: 0))
      expectNoDifference(started.outcome, .applied)
      expectNoDifference(started.snapshot.game.startedAt, now)
      expectNoDifference(started.snapshot.game.timerEndsAt, now.addingTimeInterval(900))
      let duplicate = try await execute(
        .timing(.startOrResume, expectedPhaseIndex: 0),
        at: now.addingTimeInterval(1)
      )
      expectNoDifference(duplicate.outcome, .unchanged)
      expectNoDifference(duplicate.snapshot.game.startedAt, now)
      let paused = try await execute(.timing(.pause, expectedPhaseIndex: 0))
      expectNoDifference(paused.snapshot.game.elapsedSeconds, 0)
      expectNoDifference(paused.snapshot.game.timing.status(in: paused.snapshot.timeline), .ready)
      let corrected = try await execute(.timing(.setRemainingTime(900), expectedPhaseIndex: 0))
      expectNoDifference(corrected.snapshot.game.timing.status(in: corrected.snapshot.timeline), .ready)
      let resumed = try await execute(
        .timing(.startOrResume, expectedPhaseIndex: 0),
        at: now.addingTimeInterval(10)
      )
      expectNoDifference(resumed.snapshot.game.startedAt, now)
      expectNoDifference(resumed.snapshot.game.timerEndsAt, now.addingTimeInterval(910))
      let persisted = try await read()
      expectNoDifference(persisted, resumed.snapshot)
    }

    @Test func failedFirstClockCommitDoesNotMarkGameStarted() async throws {
      @Dependency(\.defaultDatabase) var database
      _ = try seed()
      try await database.write { db in
        try Game.find(UUID(3)).update { $0.startedAt = #bind(nil as Date?) }.execute(db)
        try db.execute(sql: "CREATE TEMP TRIGGER reject_start BEFORE UPDATE ON games BEGIN SELECT RAISE(ABORT, 'test failure'); END")
      }
      let before = try await read()
      await #expect(throws: (any Error).self) {
        try await execute(.timing(.startOrResume, expectedPhaseIndex: 0))
      }
      let persisted = try await read()
      expectNoDifference(persisted, before)
      try await database.write { try $0.execute(sql: "DROP TRIGGER reject_start") }
    }

    private func execute(_ command: GameSessionCommand, at date: Date? = nil) async throws
      -> GameSessionUpdate
    {
      try await GameSessionClient.live.execute(UUID(3), command, date ?? now)
    }

    private func read() async throws -> GameSnapshot {
      @Dependency(\.defaultDatabase) var database
      return try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
    }

    private func seed(
      phase: Int = 0,
      elapsed: Int = 0,
      endsAt: Date? = nil,
      pending: Bool = false,
      late: Int? = nil,
      policy: BreakStartPolicy = .automatic,
      breakSeconds: Int = 120
    ) throws -> GameSnapshot {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      return try database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: "A")
          Team(id: UUID(2), name: "B")
        }.execute(db)
        try Game.insert {
          Game(
            id: UUID(3),
            startedAt: .distantPast,
            teamAID: UUID(1),
            teamBID: UUID(2),
            centrePassTeamID: UUID(1),
            isAwaitingCentrePassConfirmation: pending,
            lateScoringPeriodNumber: late,
            currentPhaseIndex: phase,
            elapsedSeconds: elapsed,
            timerEndsAt: endsAt,
            breakStartPolicy: policy
          )
        }.execute(db)
        for period in testGamePeriods(gameID: UUID(3), breakDurationSeconds: breakSeconds) {
          try GamePeriod.insert { period }.execute(db)
        }
        return try GameSnapshot.fetch(db, gameID: UUID(3))
      }
    }
  }
}
