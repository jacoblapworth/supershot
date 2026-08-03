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
            periodDurationSeconds: 900,
            currentPeriod: 3,
            elapsedSeconds: 42,
            hasTimerStartedCurrentPeriod: true
          )
          Game(
            id: UUID(-2),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: nil,
            teamAID: UUID(-3),
            teamBID: UUID(-4),
            periodDurationSeconds: 600,
            currentPeriod: 2,
            elapsedSeconds: 75,
            hasTimerStartedCurrentPeriod: true
          )
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            teamID: UUID(-2),
            period: 2,
            elapsedSeconds: 30,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_100)
          )
          Goal(
            id: UUID(-2),
            gameID: UUID(-2),
            teamID: UUID(-3),
            period: 1,
            elapsedSeconds: 20,
            points: 2,
            createdAt: Date(timeIntervalSince1970: 2_100)
          )
        }
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
