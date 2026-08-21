import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct GameRecoveryFeatureTests {
    @Test
    func multipleUnfinishedGamesRehydrateIndependentlyAndPaused() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens")
          Team(id: UUID(-2), name: "Swifts")
          Team(id: UUID(-3), name: "Foxes")
          Team(id: UUID(-4), name: "Owls")
          Game(
            id: UUID(-1),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: nil,
            teamAID: UUID(-1),
            teamBID: UUID(-2),
            currentPhaseIndex: 4,
            elapsedSeconds: 42,
            timerEndsAt: nil
          )
          Game(
            id: UUID(-2),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: nil,
            teamAID: UUID(-3),
            teamBID: UUID(-4),
            currentPhaseIndex: 2,
            elapsedSeconds: 75,
            timerEndsAt: nil
          )
        }
        let periods = [
          testGamePeriods(gameID: UUID(-1), durationSeconds: 900),
          testGamePeriods(gameID: UUID(-2), durationSeconds: 600),
        ].flatMap { $0 }
        try GamePeriod.insert { periods }.execute(db)
        try Goal.insert {
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            gamePeriodID: testGamePeriodID(gameID: UUID(-1), position: 1),
            teamID: UUID(-2),
            elapsedSeconds: 30,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_100)
          )
          Goal(
            id: UUID(-2),
            gameID: UUID(-2),
            gamePeriodID: testGamePeriodID(gameID: UUID(-2), position: 0),
            teamID: UUID(-3),
            elapsedSeconds: 20,
            points: 2,
            createdAt: Date(timeIntervalSince1970: 2_100)
          )
        }
        .execute(db)
      }

      let snapshots = try await database.read { db in
        (
          try GameSnapshot.fetch(db, gameID: UUID(-1)),
          try GameSnapshot.fetch(db, gameID: UUID(-2))
        )
      }
      let first = ScoringFeature.State(snapshot: snapshots.0)
      let second = ScoringFeature.State(snapshot: snapshots.1)

      expectNoDifference(first.period, 3)
      expectNoDifference(first.elapsedSeconds, 42)
      expectNoDifference(first.teamAScore, 0)
      expectNoDifference(first.teamBScore, 1)
      expectNoDifference(first.canUndo, true)
      expectNoDifference(first.centrePassTeamID, UUID(-1))
      expectNoDifference(first.isTimerRunning, false)
      expectNoDifference(second.period, 2)
      expectNoDifference(second.elapsedSeconds, 75)
      expectNoDifference(second.teamAScore, 2)
      expectNoDifference(second.teamBScore, 0)
      expectNoDifference(second.canUndo, true)
      expectNoDifference(second.centrePassTeamID, UUID(-3))
      expectNoDifference(second.isTimerRunning, false)
    }
  }
}
